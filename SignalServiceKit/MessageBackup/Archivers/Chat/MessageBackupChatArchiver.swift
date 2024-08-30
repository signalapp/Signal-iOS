//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol MessageBackupChatArchiver: MessageBackupProtoArchiver {

    typealias ChatId = MessageBackup.ChatId

    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<MessageBackup.ThreadUniqueId>

    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<ChatId>

    /// Archive all ``TSThread``s (they map to ``BackupProto_Chat``).
    ///
    /// - Returns: ``ArchiveMultiFrameResult.success`` if all frames were written without error, or either
    /// partial or complete failure otherwise.
    /// How to handle ``ArchiveMultiFrameResult.partialSuccess`` is up to the caller,
    /// but typically an error will be shown to the user, but the backup will be allowed to proceed.
    /// ``ArchiveMultiFrameResult.completeFailure``, on the other hand, will stop the entire backup,
    /// and should be used if some critical or category-wide failure occurs.
    func archiveChats(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveMultiFrameResult

    /// Restore a single ``BackupProto_Chat`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if all frames were read without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ chat: BackupProto_Chat,
        context: MessageBackup.ChatRestoringContext
    ) -> RestoreFrameResult
}

public class MessageBackupChatArchiverImpl: MessageBackupChatArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.ThreadUniqueId>

    private let chatStyleArchiver: MessageBackupChatStyleArchiver
    private let dmConfigurationStore: DisappearingMessagesConfigurationStore
    private let pinnedThreadManager: PinnedThreadManager
    private let threadStore: ThreadStore

    public init(
        chatStyleArchiver: MessageBackupChatStyleArchiver,
        dmConfigurationStore: DisappearingMessagesConfigurationStore,
        pinnedThreadManager: PinnedThreadManager,
        threadStore: ThreadStore
    ) {
        self.chatStyleArchiver = chatStyleArchiver
        self.dmConfigurationStore = dmConfigurationStore
        self.pinnedThreadManager = pinnedThreadManager
        self.threadStore = threadStore
    }

    // MARK: - Archiving

    public func archiveChats(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveMultiFrameResult {
        var completeFailureError: MessageBackup.FatalArchivingError?
        var partialErrors = [ArchiveFrameError]()

        func archiveThread(_ thread: TSThread) -> Bool {
            let result: ArchiveMultiFrameResult
            if let thread = thread as? TSContactThread {
                // Check address directly; isNoteToSelf uses global state.
                if thread.contactAddress.isEqualToAddress(context.recipientContext.localIdentifiers.aciAddress) {
                    result = self.archiveNoteToSelfThread(
                        thread,
                        stream: stream,
                        context: context
                    )
                } else {
                    result = self.archiveContactThread(
                        thread,
                        stream: stream,
                        context: context
                    )
                }
            } else if let thread = thread as? TSGroupThread, thread.isGroupV2Thread {
                result = self.archiveGroupV2Thread(
                    thread,
                    stream: stream,
                    context: context
                )
            } else {
                result = .completeFailure(.fatalArchiveError(.unrecognizedThreadType))
            }

            switch result {
            case .success:
                break
            case .completeFailure(let error):
                completeFailureError = error
                return false
            case .partialSuccess(let errors):
                partialErrors.append(contentsOf: errors)
            }

            return true
        }

        do {
            try threadStore.enumerateNonStoryThreads(tx: context.tx, block: archiveThread(_:))
        } catch let error {
            return .completeFailure(.fatalArchiveError(.threadIteratorError(error)))
        }

        if let completeFailureError {
            return .completeFailure(completeFailureError)
        } else if partialErrors.isEmpty {
            return .success
        } else {
            return .partialSuccess(partialErrors)
        }
    }

    private func archiveNoteToSelfThread(
        _ thread: TSContactThread,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveMultiFrameResult {
        let chatId = context.assignChatId(to: MessageBackup.ThreadUniqueId(thread: thread))

        guard let threadRowId = thread.sqliteRowId else {
            return .completeFailure(.fatalArchiveError(
                .fetchedThreadMissingRowId
            ))
        }

        return archiveThread(
            .init(threadType: .contact(thread), threadRowId: threadRowId),
            chatId: chatId,
            recipientId: context.recipientContext.localRecipientId,
            stream: stream,
            context: context
        )
    }

    private func archiveContactThread(
        _ thread: TSContactThread,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveMultiFrameResult {
        let chatId = context.assignChatId(to: MessageBackup.ThreadUniqueId(thread: thread))

        let contactServiceId: ServiceId? = thread.contactUUID.flatMap { try? ServiceId.parseFrom(serviceIdString: $0) }
        guard
            let recipientAddress = MessageBackup.ContactAddress(
                serviceId: contactServiceId,
                e164: E164(thread.contactPhoneNumber)
            )?.asArchivingAddress()
        else {
            return .partialSuccess([.archiveFrameError(
                .contactThreadMissingAddress,
                thread.uniqueThreadIdentifier
            )])
        }

        guard let recipientId = context.recipientContext[recipientAddress] else {
            return .partialSuccess([.archiveFrameError(
                .referencedRecipientIdMissing(recipientAddress),
                thread.uniqueThreadIdentifier
            )])
        }

        guard let threadRowId = thread.sqliteRowId else {
            return .completeFailure(.fatalArchiveError(
                .fetchedThreadMissingRowId
            ))
        }

        return archiveThread(
            .init(threadType: .contact(thread), threadRowId: threadRowId),
            chatId: chatId,
            recipientId: recipientId,
            stream: stream,
            context: context
        )
    }

    private func archiveGroupV2Thread(
        _ thread: TSGroupThread,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveMultiFrameResult {
        let chatId = context.assignChatId(to: MessageBackup.ThreadUniqueId(thread: thread))

        let recipientAddress = MessageBackup.RecipientArchivingContext.Address.group(thread.groupId)
        guard let recipientId = context.recipientContext[recipientAddress] else {
            return .partialSuccess([.archiveFrameError(
                .referencedRecipientIdMissing(recipientAddress),
                thread.uniqueThreadIdentifier
            )])
        }

        guard let threadRowId = thread.sqliteRowId else {
            return .completeFailure(.fatalArchiveError(
                .fetchedThreadMissingRowId
            ))
        }

        return archiveThread(
            .init(threadType: .groupV2(thread), threadRowId: threadRowId),
            chatId: chatId,
            recipientId: recipientId,
            stream: stream,
            context: context
        )
    }

    private func archiveThread(
        _ thread: MessageBackup.ChatThread,
        chatId: ChatId,
        recipientId: MessageBackup.RecipientId,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveMultiFrameResult {
        var partialErrors = [ArchiveFrameError]()

        let threadAssociatedData = threadStore.fetchOrDefaultAssociatedData(for: thread.tsThread, tx: context.tx)

        let thisThreadPinnedOrder: UInt32
        let pinnedThreadIds = pinnedThreadManager.pinnedThreadIds(tx: context.tx)
        if let pinnedThreadIndex: Int = pinnedThreadIds.firstIndex(of: thread.tsThread.uniqueId) {
            // Add one so we don't start at 0.
            thisThreadPinnedOrder = UInt32(clamping: pinnedThreadIndex + 1)
        } else {
            // Hardcoded 0 for unpinned.
            thisThreadPinnedOrder = 0
        }

        let expirationTimerSeconds = dmConfigurationStore.durationSeconds(for: thread.tsThread, tx: context.tx)

        let dontNotifyForMentionsIfMuted: Bool
        switch thread.tsThread.mentionNotificationMode {
        case .default, .always:
            dontNotifyForMentionsIfMuted = false
        case .never:
            dontNotifyForMentionsIfMuted = true
        }

        var chat = BackupProto_Chat()
        chat.id = chatId.value
        chat.recipientID = recipientId.value
        chat.archived = threadAssociatedData.isArchived
        chat.pinnedOrder = thisThreadPinnedOrder
        chat.expirationTimerMs = UInt64(expirationTimerSeconds * 1000)
        chat.muteUntilMs = threadAssociatedData.mutedUntilTimestamp
        chat.markedUnread = threadAssociatedData.isMarkedUnread
        chat.dontNotifyForMentionsIfMuted = dontNotifyForMentionsIfMuted

        let chatStyleResult = chatStyleArchiver.archiveChatStyle(
            thread: thread,
            chatId: chatId,
            context: context.customChatColorContext
        )
        switch chatStyleResult {
        case .success(let chatStyleProto):
            if let chatStyleProto {
                chat.style = chatStyleProto
            }
        case .failure(let error):
            partialErrors.append(error)
        }

        let error = Self.writeFrameToStream(
            stream,
            objectId: thread.tsThread.uniqueThreadIdentifier
        ) {
            var frame = BackupProto_Frame()
            frame.item = .chat(chat)
            return frame
        }

        if let error {
            partialErrors.append(error)
        }

        if partialErrors.isEmpty {
            return .success
        } else {
            return .partialSuccess(partialErrors)
        }
    }

    // MARK: - Restoring

    public func restore(
        _ chat: BackupProto_Chat,
        context: MessageBackup.ChatRestoringContext
    ) -> RestoreFrameResult {
        var partialErrors = [MessageBackup.RestoreFrameError<ChatId>]()

        let chatThread: MessageBackup.ChatThread
        switch context.recipientContext[chat.typedRecipientId] {
        case .none:
            return .failure([.restoreFrameError(
                .invalidProtoData(.recipientIdNotFound(chat.typedRecipientId)),
                chat.chatId
            )])
        case .localAddress:
            let noteToSelfThread = threadStore.getOrCreateContactThread(
                with: context.recipientContext.localIdentifiers.aciAddress,
                tx: context.tx
            )
            guard let noteToSelfRowId = noteToSelfThread.sqliteRowId else {
                return .failure([.restoreFrameError(
                    .databaseModelMissingRowId(modelClass: TSContactThread.self),
                    chat.chatId
                )])
            }
            chatThread = MessageBackup.ChatThread(
                threadType: .contact(noteToSelfThread),
                threadRowId: noteToSelfRowId
            )
        case .releaseNotesChannel:
            // TODO: [Backups] Implement restoring the Release Notes channel chat.
            return .success
        case .group(let groupId):
            // We don't create the group thread here; that happened when parsing the Group Recipient.
            // Instead, just set metadata.
            guard
                let groupThread = threadStore.fetchGroupThread(groupId: groupId, tx: context.tx),
                groupThread.isGroupV2Thread
            else {
                return .failure([.restoreFrameError(
                    .referencedGroupThreadNotFound(groupId),
                    chat.chatId
                )])
            }
            guard let groupThreadRowId = groupThread.sqliteRowId else {
                return .failure([.restoreFrameError(
                    .databaseModelMissingRowId(modelClass: TSGroupThread.self),
                    chat.chatId
                )])
            }
            chatThread = MessageBackup.ChatThread(
                threadType: .groupV2(groupThread),
                threadRowId: groupThreadRowId
            )
        case .contact(let address):
            let contactThread = threadStore.getOrCreateContactThread(with: address.asInteropAddress(), tx: context.tx)
            guard let contactThreadRowId = contactThread.sqliteRowId else {
                return .failure([.restoreFrameError(
                    .databaseModelMissingRowId(modelClass: TSContactThread.self),
                    chat.chatId
                )])
            }
            chatThread = MessageBackup.ChatThread(
                threadType: .contact(contactThread),
                threadRowId: contactThreadRowId
            )
        case .distributionList:
            return .failure([
                .restoreFrameError(
                    .developerError(OWSAssertionError("Distribution Lists cannot be chat authors")),
                    chat.chatId)])
        }

        context.mapChatId(chat.chatId, to: chatThread)

        var associatedDataNeedsUpdate = false
        var isArchived: Bool?
        var isMarkedUnread: Bool?
        var mutedUntilTimestamp: UInt64?

        if chat.archived {
            // Unarchived is the default, no need to set it if archived = false.
            isArchived = true
            associatedDataNeedsUpdate = true
        }
        if chat.markedUnread {
            associatedDataNeedsUpdate = true
            isMarkedUnread = true
        }
        if chat.muteUntilMs != 0 {
            associatedDataNeedsUpdate = true
            mutedUntilTimestamp = chat.muteUntilMs
        }

        if associatedDataNeedsUpdate {
            let threadAssociatedData = threadStore.fetchOrDefaultAssociatedData(for: chatThread.tsThread, tx: context.tx)
            threadStore.updateAssociatedData(
                threadAssociatedData,
                isArchived: isArchived,
                isMarkedUnread: isMarkedUnread,
                mutedUntilTimestamp: mutedUntilTimestamp,
                updateStorageService: false,
                tx: context.tx
            )
        }

        if chat.pinnedOrder != 0 {
            let newPinnedThreadIds = context.pinnedThreadOrder(
                newPinnedThreadId: MessageBackup.ThreadUniqueId(chatThread: chatThread),
                newPinnedThreadIndex: chat.pinnedOrder
            )
            pinnedThreadManager.updatePinnedThreadIds(newPinnedThreadIds.map(\.value), updateStorageService: false, tx: context.tx)
        }

        if chat.expirationTimerMs != 0 {
            dmConfigurationStore.set(
                token: .init(
                    isEnabled: true,
                    durationSeconds: UInt32(chat.expirationTimerMs / 1000),
                    // TODO: [Backups] add DM timer version to backups
                    version: nil
                ),
                for: .thread(chatThread.tsThread),
                tx: context.tx
            )
        }

        if chat.dontNotifyForMentionsIfMuted {
            // We only need to set if its not the default.
            threadStore.update(
                thread: chatThread.tsThread,
                withMentionNotificationMode: .never,
                // Don't trigger a storage service update.
                wasLocallyInitiated: false,
                tx: context.tx
            )
        }

        let chatStyleToRestore: BackupProto_ChatStyle?
        if chat.hasStyle {
            chatStyleToRestore = chat.style
        } else {
            chatStyleToRestore = nil
        }
        let chatStyleResult = chatStyleArchiver.restoreChatStyle(
            chatStyleToRestore,
            thread: chatThread,
            chatId: chat.chatId,
            context: context.customChatColorContext
        )
        switch chatStyleResult {
        case .success:
            break
        case .partialRestore(let errors):
            partialErrors.append(contentsOf: errors)
        case .failure(let errors):
            partialErrors.append(contentsOf: errors)
            return .failure(partialErrors)
        }

        if partialErrors.isEmpty {
            return .success
        } else {
            return .partialRestore(partialErrors)
        }
    }
}
