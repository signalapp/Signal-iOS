//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol MessageBackupChatArchiver: MessageBackupProtoArchiver {

    typealias ChatId = MessageBackup.ChatId

    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<MessageBackup.ThreadUniqueId>

    /// Archive all ``TSThread``s (they map to ``BackupProto.Chat``).
    ///
    /// - Returns: ``ArchiveMultiFrameResult.success`` if all frames were written without error, or either
    /// partial or complete failure otherwise.
    /// How to handle ``ArchiveMultiFrameResult.partialSuccess`` is up to the caller,
    /// but typically an error will be shown to the user, but the backup will be allowed to proceed.
    /// ``ArchiveMultiFrameResult.completeFailure``, on the other hand, will stop the entire backup,
    /// and should be used if some critical or category-wide failure occurs.
    func archiveChats(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult

    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<ChatId>

    /// Restore a single ``BackupProto.Chat`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if all frames were read without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ chat: BackupProto.Chat,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult
}

public class MessageBackupChatArchiverImpl: MessageBackupChatArchiver {

    private let dmConfigurationStore: DisappearingMessagesConfigurationStore
    private let pinnedThreadManager: PinnedThreadManager
    private let threadStore: ThreadStore

    public init(
        dmConfigurationStore: DisappearingMessagesConfigurationStore,
        pinnedThreadManager: PinnedThreadManager,
        threadStore: ThreadStore
    ) {
        self.dmConfigurationStore = dmConfigurationStore
        self.pinnedThreadManager = pinnedThreadManager
        self.threadStore = threadStore
    }

    // MARK: - Archiving

    public func archiveChats(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        var completeFailureError: MessageBackup.FatalArchivingError?
        var partialErrors = [ArchiveMultiFrameResult.ArchiveFrameError]()

        func archiveThread(_ thread: TSThread, stop: inout Bool) {
            let result: ArchiveMultiFrameResult
            if let thread = thread as? TSContactThread {
                // Check address directly; isNoteToSelf uses global state.
                if thread.contactAddress.isEqualToAddress(context.recipientContext.localIdentifiers.aciAddress) {
                    result = self.archiveNoteToSelfThread(
                        thread,
                        stream: stream,
                        context: context,
                        tx: tx
                    )
                } else {
                    result = self.archiveContactThread(
                        thread,
                        stream: stream,
                        context: context,
                        tx: tx
                    )
                }
            } else if let thread = thread as? TSGroupThread, thread.isGroupV2Thread {
                result = self.archiveGroupV2Thread(
                    thread,
                    stream: stream,
                    context: context,
                    tx: tx
                )
            } else {
                completeFailureError = .fatalArchiveError(.unrecognizedThreadType)
                return
            }

            switch result {
            case .success:
                break
            case .completeFailure(let error):
                completeFailureError = error
                stop = true
            case .partialSuccess(let errors):
                partialErrors.append(contentsOf: errors)
            }
        }

        do {
            try threadStore.enumerateNonStoryThreads(tx: tx, block: archiveThread(_:stop:))
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
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackupChatArchiver.ArchiveMultiFrameResult {
        let chatId = context.assignChatId(to: MessageBackup.ChatThread.contact(thread).uniqueId)

        return archiveThread(
            thread,
            chatId: chatId,
            recipientId: context.recipientContext.localRecipientId,
            stream: stream,
            context: context,
            tx: tx
        )
    }

    private func archiveContactThread(
        _ thread: TSContactThread,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackupChatArchiver.ArchiveMultiFrameResult {
        let chatId = context.assignChatId(to: MessageBackup.ChatThread.contact(thread).uniqueId)

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

        return archiveThread(
            thread,
            chatId: chatId,
            recipientId: recipientId,
            stream: stream,
            context: context,
            tx: tx
        )
    }

    private func archiveGroupV2Thread(
        _ thread: TSGroupThread,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackupChatArchiver.ArchiveMultiFrameResult {
        let chatId = context.assignChatId(to: MessageBackup.ChatThread.groupV2(thread).uniqueId)

        let recipientAddress = MessageBackup.RecipientArchivingContext.Address.group(thread.groupId)
        guard let recipientId = context.recipientContext[recipientAddress] else {
            return .partialSuccess([.archiveFrameError(
                .referencedRecipientIdMissing(recipientAddress),
                thread.uniqueThreadIdentifier
            )])
        }

        return archiveThread(
            thread,
            chatId: chatId,
            recipientId: recipientId,
            stream: stream,
            context: context,
            tx: tx
        )
    }

    private func archiveThread<T: TSThread>(
        _ thread: T,
        chatId: ChatId,
        recipientId: MessageBackup.RecipientId,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackupChatArchiver.ArchiveMultiFrameResult {
        let threadAssociatedData = threadStore.fetchOrDefaultAssociatedData(for: thread, tx: tx)

        let thisThreadPinnedOrder: UInt32
        let pinnedThreadIds = pinnedThreadManager.pinnedThreadIds(tx: tx)
        if let pinnedThreadIndex: Int = pinnedThreadIds.firstIndex(of: thread.uniqueId) {
            // Add one so we don't start at 0.
            thisThreadPinnedOrder = UInt32(clamping: pinnedThreadIndex + 1)
        } else {
            // Hardcoded 0 for unpinned.
            thisThreadPinnedOrder = 0
        }

        let expirationTimerSeconds = dmConfigurationStore.durationSeconds(for: thread, tx: tx)

        let dontNotifyForMentionsIfMuted: Bool
        switch thread.mentionNotificationMode {
        case .default, .always:
            dontNotifyForMentionsIfMuted = false
        case .never:
            dontNotifyForMentionsIfMuted = true
        }

        let chat = BackupProto.Chat(
            id: chatId.value,
            recipientId: recipientId.value,
            archived: threadAssociatedData.isArchived,
            pinnedOrder: thisThreadPinnedOrder,
            expirationTimerMs: UInt64(expirationTimerSeconds * 1000),
            muteUntilMs: threadAssociatedData.mutedUntilTimestamp,
            markedUnread: threadAssociatedData.isMarkedUnread,
            dontNotifyForMentionsIfMuted: dontNotifyForMentionsIfMuted
        )

        let error = Self.writeFrameToStream(
            stream,
            objectId: thread.uniqueThreadIdentifier
        ) {
            var frame = BackupProto.Frame()
            frame.item = .chat(chat)
            return frame
        }
        if let error {
            return .partialSuccess([error])
        } else {
            return .success
        }
    }

    // MARK: - Restoring

    public func restore(
        _ chat: BackupProto.Chat,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        let thread: MessageBackup.ChatThread
        switch context.recipientContext[chat.typedRecipientId] {
        case .none:
            return .failure([.restoreFrameError(
                .invalidProtoData(.recipientIdNotFound(chat.typedRecipientId)),
                chat.chatId
            )])
        case .localAddress:
            let noteToSelfThread = threadStore.getOrCreateContactThread(
                with: context.recipientContext.localIdentifiers.aciAddress,
                tx: tx
            )
            thread = .contact(noteToSelfThread)
        case .group(let groupId):
            // We don't create the group thread here; that happened when parsing the Group Recipient.
            // Instead, just set metadata.
            guard
                let groupThread = threadStore.fetchGroupThread(groupId: groupId, tx: tx),
                groupThread.isGroupV2Thread
            else {
                return .failure([.restoreFrameError(
                    .referencedGroupThreadNotFound(groupId),
                    chat.chatId
                )])
            }
            thread = .groupV2(groupThread)
        case .contact(let address):
            let contactThread = threadStore.getOrCreateContactThread(with: address.asInteropAddress(), tx: tx)
            thread = .contact(contactThread)
        }

        context.mapChatId(chat.chatId, to: thread)

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
            let threadAssociatedData = threadStore.fetchOrDefaultAssociatedData(for: thread.thread, tx: tx)
            threadStore.updateAssociatedData(
                threadAssociatedData,
                isArchived: isArchived,
                isMarkedUnread: isMarkedUnread,
                mutedUntilTimestamp: mutedUntilTimestamp,
                updateStorageService: false,
                tx: tx
            )
        }

        if chat.pinnedOrder != 0 {
            let newPinnedThreadIds = context.pinnedThreadOrder(
                newPinnedThreadId: thread.uniqueId,
                newPinnedThreadIndex: chat.pinnedOrder
            )
            pinnedThreadManager.updatePinnedThreadIds(newPinnedThreadIds.map(\.value), updateStorageService: false, tx: tx)
        }

        if chat.expirationTimerMs != 0 {
            dmConfigurationStore.set(
                token: .init(isEnabled: true, durationSeconds: UInt32(chat.expirationTimerMs / 1000)),
                for: .thread(thread.thread),
                tx: tx
            )
        }

        if chat.dontNotifyForMentionsIfMuted {
            // We only need to set if its not the default.
            threadStore.update(
                thread: thread.thread,
                withMentionNotificationMode: .never,
                // Don't trigger a storage service update.
                wasLocallyInitiated: false,
                tx: tx
            )
        }

        return .success
    }
}
