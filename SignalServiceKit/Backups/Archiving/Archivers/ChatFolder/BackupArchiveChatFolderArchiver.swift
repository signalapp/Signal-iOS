//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class BackupArchiveChatFolderArchiver {
    class RestoringContext {
        let recipientContext: BackupArchive.RecipientRestoringContext
        /// For assigning the chat folders' `position` property
        var nextPosition: UInt32 = 0
        var restoredIds = Set<UUID>()
        var hasRestoredAllChats = false

        init(recipientContext: BackupArchive.RecipientRestoringContext) {
            self.recipientContext = recipientContext
        }
    }

    private let chatFolderStore: ChatFolderStore
    private let groupStore: GroupStore

    init(chatFolderStore: ChatFolderStore, groupStore: GroupStore) {
        self.chatFolderStore = chatFolderStore
        self.groupStore = groupStore
    }

    func archiveChatFolders(
        stream: BackupArchiveOutputStream,
        context: BackupArchive.RecipientArchivingContext,
    ) throws(CancellationError) -> BackupArchive.ArchiveMultiFrameResult {
        // Fetch only non-deleted chat folders
        let records = chatFolderStore.fetchDisplayableRecords(tx: context.tx)
        // If there's _only_ the All Chats folder, don't back it up
        guard records.contains(where: { $0.folderType == .custom }) else { return .success }
        var errors = [BackupArchive.ArchiveFrameError]()
        for record in records {
            if Task.isCancelled {
                throw CancellationError()
            }
            let error: BackupArchive.ArchiveFrameError? = context.processFrame { frameBencher in
                var proto = BackupProto_ChatFolder()
                proto.id = record.chatFolderId.data
                switch record.folderType {
                case .all:
                    proto.folderType = .all
                    proto.showMutedChats = true
                    proto.includeAllIndividualChats = true
                    proto.includeAllGroupChats = true
                case .custom:
                    proto.folderType = .custom
                    proto.name = record.name
                    proto.showOnlyUnread = record.showOnlyUnread
                    proto.showMutedChats = record.showMutedChats
                    proto.includeAllIndividualChats = record.includeAllIndividualChats
                    proto.includeAllGroupChats = record.includeAllGroupChats
                    for membership in chatFolderStore.fetchMemberships(folderRowId: record.id, tx: context.tx) {
                        let recipientId: BackupArchive.RecipientId?
                        switch membership.chat {
                        case .contact(let rowId):
                            recipientId = context.recipientId(forRecipientDbRowId: rowId)
                        case .group(let rowId):
                            let groupRecord = groupStore.fetchGroup(rowId: rowId, tx: context.tx)
                            recipientId = groupRecord.flatMap { groupRecord in
                                let groupId = BackupArchive.GroupId(groupId: groupRecord.groupId)
                                return context[.group(groupId)]
                            }
                        }
                        guard let recipientId else { continue }
                        switch membership.membershipType {
                        case .included:
                            proto.includedRecipientIds.append(recipientId.value)
                        case .excluded:
                            proto.excludedRecipientIds.append(recipientId.value)
                        }
                    }
                }
                return context.writeFrame(toStream: stream, flush: nil, frameBencher: frameBencher) {
                    var frame = BackupProto_Frame()
                    frame.item = .chatFolder(proto)
                    return frame
                }
            }
            if let error {
                errors.append(error)
            }
        }
        return errors.isEmpty ? .success : .partialSuccess(errors)
    }

    func restore(
        _ proto: BackupProto_ChatFolder,
        context: RestoringContext,
    ) -> BackupArchive.RestoreFrameResult {
        guard proto.id.count == 16, let id = UUID(data: proto.id) else {
            return .failure([.restoreFrameError(.invalidProtoData(.invalidChatFolderId))])
        }
        let isAllChats = proto.folderType == .all
        guard
            !context.restoredIds.contains(id),
            !(isAllChats && context.hasRestoredAllChats)
        else {
            return .failure([.restoreFrameError(.invalidProtoData(.duplicateChatFolder))])
        }
        let recipientContext = context.recipientContext
        let tx = recipientContext.tx
        var record: ChatFolderRecord
        if isAllChats {
            record = chatFolderStore.fetchOrInsertAllChatsRecord(tx: tx)
            record.position = context.nextPosition
            chatFolderStore.update(record, tx: tx)
            chatFolderStore.setAllChatsChatFolderId(id, tx: tx)
        } else {
            record = chatFolderStore.insertCustomFolderRecord(
                chatFolderId: id,
                name: proto.name,
                position: context.nextPosition,
                showOnlyUnread: proto.showOnlyUnread,
                showMutedChats: proto.showMutedChats,
                includeAllIndividualChats: proto.includeAllIndividualChats,
                includeAllGroupChats: proto.includeAllGroupChats,
                deletedAtTimestampMs: 0,
                tx: tx,
            )
        }
        context.nextPosition += 1
        context.restoredIds.insert(id)
        context.hasRestoredAllChats = context.hasRestoredAllChats || isAllChats

        if isAllChats {
            return .success
        }

        var errors = [BackupArchive.RestoreFrameError]()
        func chats(recipientIds ids: [UInt64]) -> Set<ChatFolderChatRecord.Chat> {
            var chats = Set<ChatFolderChatRecord.Chat>()
            for value in ids {
                let recipientId = BackupArchive.RecipientId(value: value)
                guard let address = recipientContext[recipientId] else {
                    errors.append(.restoreFrameError(.invalidProtoData(.recipientIdNotFound(recipientId))))
                    continue
                }
                let chat: ChatFolderChatRecord.Chat?
                switch address {
                case .localAddress:
                    chat = recipientContext.localSignalRecipientRowId.map { .contact(recipientRowId: $0) }
                case .contact:
                    let recipientRowId = recipientContext.recipientDbRowId(forBackupRecipientId: recipientId)
                    chat = recipientRowId.map { recipientRowId in
                        .contact(recipientRowId: recipientRowId)
                    }
                case .group(let groupId):
                    let groupRecord = groupStore.fetchGroup(forGroupIdData: groupId.value, tx: tx)
                    chat = groupRecord.map { groupRecord in
                        .group(groupRowId: groupRecord.rowId)
                    }
                case .releaseNotesChannel, .distributionList, .callLink:
                    chat = nil
                }
                if let chat {
                    chats.insert(chat)
                } else {
                    errors.append(.restoreFrameError(.invalidProtoData(.invalidChatFolderRecipient(recipientId))))
                }
            }
            return chats
        }
        let includedChats = chats(recipientIds: proto.includedRecipientIds)
        let excludedChats = chats(recipientIds: proto.excludedRecipientIds)
        chatFolderStore.replaceMemberships(
            folderRowId: record.id,
            includedChats: includedChats,
            excludedChats: excludedChats,
            tx: tx,
        )
        return errors.isEmpty ? .success : .partialRestore(errors)
    }
}
