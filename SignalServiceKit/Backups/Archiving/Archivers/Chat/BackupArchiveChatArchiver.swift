//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class BackupArchiveChatArchiver: BackupArchiveProtoStreamWriter {
    typealias ChatId = BackupArchive.ChatId
    typealias ArchiveMultiFrameResult = BackupArchive.ArchiveMultiFrameResult
    typealias RestoreFrameResult = BackupArchive.RestoreFrameResult

    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError

    private let chatStyleArchiver: BackupArchiveChatStyleArchiver
    private let contactRecipientArchiver: BackupArchiveContactRecipientArchiver
    private let dmConfigurationStore: DisappearingMessagesConfigurationStore
    private let pinnedThreadStore: PinnedThreadStoreWrite
    private let threadStore: BackupArchiveThreadStore

    public init(
        chatStyleArchiver: BackupArchiveChatStyleArchiver,
        contactRecipientArchiver: BackupArchiveContactRecipientArchiver,
        dmConfigurationStore: DisappearingMessagesConfigurationStore,
        pinnedThreadStore: PinnedThreadStoreWrite,
        threadStore: BackupArchiveThreadStore,
    ) {
        self.chatStyleArchiver = chatStyleArchiver
        self.contactRecipientArchiver = contactRecipientArchiver
        self.dmConfigurationStore = dmConfigurationStore
        self.pinnedThreadStore = pinnedThreadStore
        self.threadStore = threadStore
    }

    // MARK: - Archiving

    /// Archive all ``TSThread``s (they map to ``BackupProto_Chat``).
    ///
    /// - Returns: ``ArchiveMultiFrameResult.success`` if all frames were written without error, or either
    /// partial or complete failure otherwise.
    /// How to handle ``ArchiveMultiFrameResult.partialSuccess`` is up to the caller,
    /// but typically an error will be shown to the user, but the backup will be allowed to proceed.
    /// ``ArchiveMultiFrameResult.completeFailure``, on the other hand, will stop the entire backup,
    /// and should be used if some critical or category-wide failure occurs.
    func archiveChats(
        stream: BackupArchiveProtoOutputStream,
        context: BackupArchive.ChatArchivingContext,
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var completeFailureError: BackupArchive.FatalArchivingError?
        var partialErrors = [ArchiveFrameError]()

        try context.bencher.wrapEnumeration(
            tx: context.tx,
            enumerationBlock: { tx, block throws(CancellationError) in
                try threadStore.enumerateNonStoryThreads(tx: tx, block: block)
            },
            perEnumerantBlock: { [self] thread, frameBencher in
                let result = archiveThread(
                    thread: thread,
                    stream: stream,
                    frameBencher: frameBencher,
                    context: context,
                )

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
            },
        )

        if let completeFailureError {
            return .completeFailure(completeFailureError)
        } else if partialErrors.isEmpty {
            return .success
        } else {
            return .partialSuccess(partialErrors)
        }
    }

    private func archiveThread(
        thread: TSThread,
        stream: BackupArchiveProtoOutputStream,
        frameBencher: BackupArchive.Bencher.FrameBencher,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveMultiFrameResult {
        if let thread = thread as? TSContactThread {
            if thread.contactAddress.isEqualToAddress(context.recipientContext.localIdentifiers.aciAddress) {
                return archiveNoteToSelfThread(
                    thread,
                    threadRowId: thread.sqliteRowId!,
                    stream: stream,
                    frameBencher: frameBencher,
                    context: context,
                )
            } else {
                return self.archiveContactThread(
                    thread,
                    threadRowId: thread.sqliteRowId!,
                    stream: stream,
                    frameBencher: frameBencher,
                    context: context,
                )
            }
        } else if let thread = thread as? TSGroupThread, thread.isGroupV2Thread {
            return archiveGroupV2Thread(
                thread,
                threadRowId: thread.sqliteRowId!,
                stream: stream,
                frameBencher: frameBencher,
                context: context,
            )
        } else if let thread = thread as? TSGroupThread, thread.isGroupV1Thread {
            // Remember which threads were gv1 so we can silently drop their messages.
            context.gv1ThreadIds.insert(thread.uniqueThreadIdentifier)
            // Skip gv1 threads; count as success.
            return .success
        } else if thread.isReleaseNotesThread {
            // TODO: [KC] implement release notes in backups
            return .success
        } else {
            return .completeFailure(.fatalArchiveError(.developerError(
                message: "Unexpected thread type! \(type(of: thread))",
            )))
        }
    }

    private func archiveNoteToSelfThread(
        _ thread: TSContactThread,
        threadRowId: TSThread.RowId,
        stream: BackupArchiveProtoOutputStream,
        frameBencher: BackupArchive.Bencher.FrameBencher,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveMultiFrameResult {
        return archiveThread(
            BackupArchive.ChatThread(threadType: .contact(thread), threadRowId: threadRowId),
            recipientId: context.recipientContext.localRecipientId,
            stream: stream,
            frameBencher: frameBencher,
            context: context,
        )
    }

    private func archiveContactThread(
        _ thread: TSContactThread,
        threadRowId: TSThread.RowId,
        stream: BackupArchiveProtoOutputStream,
        frameBencher: BackupArchive.Bencher.FrameBencher,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveMultiFrameResult {
        let contactServiceId: ServiceId? = thread.contactUUID.flatMap { try? ServiceId.parseFrom(serviceIdString: $0) }
        guard
            let contactAddress = BackupArchive.ContactAddress(
                serviceId: contactServiceId,
                e164: E164(thread.contactPhoneNumber),
            )
        else {
            return .partialSuccess([.archiveFrameError(.contactThreadMissingAddress)])
        }
        let recipientAddress = contactAddress.asArchivingAddress()

        let recipientId: BackupArchive.RecipientId
        if let _recipientId = context.recipientContext[recipientAddress] {
            recipientId = _recipientId
        } else {
            // Try and create a recipient for this orphaned TSContactThread
            // that has no corresponding SignalRecipient.
            switch contactRecipientArchiver.archiveContactRecipientForOrphanedContactThread(
                address: contactAddress,
                stream: stream,
                frameBencher: frameBencher,
                context: context,
            ) {
            case .success(let _recipientId):
                recipientId = _recipientId
            case .failure(let error):
                return .partialSuccess([error])
            }
        }

        return archiveThread(
            BackupArchive.ChatThread(threadType: .contact(thread), threadRowId: threadRowId),
            recipientId: recipientId,
            stream: stream,
            frameBencher: frameBencher,
            context: context,
        )
    }

    private func archiveGroupV2Thread(
        _ thread: TSGroupThread,
        threadRowId: TSThread.RowId,
        stream: BackupArchiveProtoOutputStream,
        frameBencher: BackupArchive.Bencher.FrameBencher,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveMultiFrameResult {
        let recipientAddress = BackupArchive.RecipientArchivingContext.Address.group(
            BackupArchive.GroupId(groupModel: thread.groupModel),
        )
        guard let recipientId = context.recipientContext[recipientAddress] else {
            return .partialSuccess([.archiveFrameError(.referencedRecipientIdMissing(recipientAddress))])
        }

        return archiveThread(
            BackupArchive.ChatThread(threadType: .groupV2(thread), threadRowId: threadRowId),
            recipientId: recipientId,
            stream: stream,
            frameBencher: frameBencher,
            context: context,
        )
    }

    private func archiveThread(
        _ thread: BackupArchive.ChatThread,
        recipientId: BackupArchive.RecipientId,
        stream: BackupArchiveProtoOutputStream,
        frameBencher: BackupArchive.Bencher.FrameBencher,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveMultiFrameResult {
        var partialErrors = [ArchiveFrameError]()

        let threadAssociatedData = threadStore.fetchOrDefaultAssociatedData(
            for: thread.tsThread,
            tx: context.tx,
        )

        let thisThreadPinnedOrder: UInt32?
        let pinnedThreadIds = pinnedThreadStore.pinnedThreadIds(tx: context.tx)
        if let pinnedThreadIndex: Int = pinnedThreadIds.firstIndex(of: thread.tsThread.uniqueId) {
            // Add one so we don't start at 0.
            thisThreadPinnedOrder = UInt32(clamping: pinnedThreadIndex + 1)
        } else {
            thisThreadPinnedOrder = nil
        }

        let versionedExpireTimerToken = dmConfigurationStore.fetchOrBuildDefault(
            for: .thread(thread.tsThread),
            tx: context.tx,
        ).asVersionedToken

        let dontNotifyForMentionsIfMuted: Bool
        switch thread.tsThread.mentionNotificationMode {
        case .default, .always:
            dontNotifyForMentionsIfMuted = false
        case .never:
            dontNotifyForMentionsIfMuted = true
        }

        var chat = BackupProto_Chat()
        chat.id = context.assignChatId(to: thread.tsThread).value
        chat.recipientID = recipientId.value
        chat.archived = threadAssociatedData.isArchived
        if let thisThreadPinnedOrder {
            chat.pinnedOrder = thisThreadPinnedOrder
        }
        if versionedExpireTimerToken.isEnabled {
            chat.expirationTimerMs = UInt64(versionedExpireTimerToken.durationSeconds) * 1000
        }
        chat.expireTimerVersion = versionedExpireTimerToken.version
        if threadAssociatedData.mutedUntilTimestamp > 0 {
            let muteUntilMs = threadAssociatedData.mutedUntilTimestamp
            if BackupArchive.Timestamps.isValid(muteUntilMs) {
                chat.muteUntilMs = muteUntilMs
            } else {
                chat.muteUntilMs = ThreadAssociatedData.alwaysMutedTimestamp
            }
        }
        chat.markedUnread = threadAssociatedData.isMarkedUnread
        chat.dontNotifyForMentionsIfMuted = dontNotifyForMentionsIfMuted

        let chatStyleResult = chatStyleArchiver.archiveChatStyle(
            thread: thread,
            context: context.customChatColorContext,
        )
        switch chatStyleResult {
        case .success(let chatStyleProto):
            if let chatStyleProto {
                chat.style = chatStyleProto
            }
        case .failure(let error):
            partialErrors.append(error)
        }

        let error: ArchiveFrameError? = Self.writeFrameToStream(
            stream,
            frameBencher: frameBencher,
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

    /// Restore a single ``BackupProto_Chat`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if all frames were read without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ chat: BackupProto_Chat,
        context: BackupArchive.ChatRestoringContext,
    ) -> RestoreFrameResult {
        var partialErrors = [BackupArchive.RestoreFrameError]()

        let chatThread: BackupArchive.ChatThread
        switch context.recipientContext[chat.typedRecipientId] {
        case .none:
            return .failure([.restoreFrameError(.invalidProtoData(.recipientIdNotFound(chat.typedRecipientId)))])
        case .localAddress:
            let noteToSelfThread: TSContactThread
            do {
                noteToSelfThread = try threadStore.createNoteToSelfThread(
                    context: context,
                )
            } catch let error {
                return .failure([.restoreFrameError(.databaseInsertionFailed(error))])
            }
            guard let noteToSelfRowId = noteToSelfThread.sqliteRowId else {
                return .failure([.restoreFrameError(.databaseModelMissingRowId(modelClass: TSContactThread.self))])
            }
            chatThread = BackupArchive.ChatThread(
                threadType: .contact(noteToSelfThread),
                threadRowId: noteToSelfRowId,
            )
        case .releaseNotesChannel:
            // TODO: [Backups] Implement restoring the Release Notes channel chat.
            return .success
        case .group(let groupId):
            // We don't create the group thread here; that happened when parsing the Group Recipient.
            // Instead, just set metadata.
            guard
                let groupThread = context.recipientContext[groupId],
                groupThread.isGroupV2Thread
            else {
                return .failure([.restoreFrameError(.referencedGroupThreadNotFound(groupId))])
            }
            guard let groupThreadRowId = groupThread.sqliteRowId else {
                return .failure([.restoreFrameError(.databaseModelMissingRowId(modelClass: TSGroupThread.self))])
            }
            chatThread = BackupArchive.ChatThread(
                threadType: .groupV2(groupThread),
                threadRowId: groupThreadRowId,
            )
        case .contact(let address):
            let contactThread: TSContactThread
            do {
                contactThread = try threadStore.createContactThread(with: address, context: context)
            } catch let error {
                return .failure([.restoreFrameError(.databaseInsertionFailed(error))])
            }
            guard let contactThreadRowId = contactThread.sqliteRowId else {
                return .failure([.restoreFrameError(.databaseModelMissingRowId(modelClass: TSContactThread.self))])
            }
            chatThread = BackupArchive.ChatThread(
                threadType: .contact(contactThread),
                threadRowId: contactThreadRowId,
            )
        case .distributionList:
            return .failure([.restoreFrameError(.invalidProtoData(.distributionListUsedAsChatRecipient))])
        case .callLink:
            return .failure([.restoreFrameError(.invalidProtoData(.callLinkUsedAsChatRecipient))])
        }

        context.mapChatId(chat.chatId, to: chatThread, recipientId: chat.typedRecipientId)

        var mutedUntilTimestamp: UInt64?
        if chat.hasMuteUntilMs {
            mutedUntilTimestamp = chat.muteUntilMs
        }

        do {
            try threadStore.createAssociatedData(
                for: chatThread.tsThread,
                isArchived: chat.archived,
                isMarkedUnread: chat.markedUnread,
                mutedUntilTimestamp: mutedUntilTimestamp,
                context: context,
            )
        } catch let error {
            return .failure(partialErrors + [.restoreFrameError(.databaseInsertionFailed(error))])
        }

        if chat.hasPinnedOrder {
            let newPinnedThreadIds = context.pinnedThreadOrder(
                newPinnedThreadId: BackupArchive.ThreadUniqueId(chatThread: chatThread),
                newPinnedThreadChatId: chat.chatId,
                newPinnedThreadIndex: chat.pinnedOrder,
            )
            pinnedThreadStore.updatePinnedThreadIds(newPinnedThreadIds.map(\.value), tx: context.tx)
        }

        let expiresInSeconds: UInt32
        if chat.hasExpirationTimerMs {
            guard let _expiresInSeconds: UInt32 = .msToSecs(chat.expirationTimerMs) else {
                return .failure([.restoreFrameError(.invalidProtoData(.expirationTimerOverflowedLocalType))])
            }
            expiresInSeconds = _expiresInSeconds
        } else {
            expiresInSeconds = 0
        }

        dmConfigurationStore.set(
            token: VersionedDisappearingMessageToken(
                isEnabled: expiresInSeconds > 0,
                durationSeconds: expiresInSeconds,
                version: chat.expireTimerVersion,
            ),
            for: .thread(chatThread.tsThread),
            tx: context.tx,
        )

        do {
            try threadStore.update(
                thread: chatThread,
                dontNotifyForMentionsIfMuted: chat.dontNotifyForMentionsIfMuted,
                context: context,
            )
        } catch let error {
            return .failure([.restoreFrameError(.databaseInsertionFailed(error))])
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
            context: context.customChatColorContext,
        )
        switch chatStyleResult {
        case .success:
            break
        case .unrecognizedEnum:
            return chatStyleResult
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
