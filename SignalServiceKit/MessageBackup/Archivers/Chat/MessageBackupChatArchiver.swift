//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol MessageBackupChatArchiver: MessageBackupProtoArchiver {

    typealias ChatId = MessageBackup.ChatId

    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<ChatId>

    /// Archive all ``TSThread``s (they map to ``BackupProtoChat``).
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

    /// Restore a single ``BackupProtoChat`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if all frames were read without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ chat: BackupProtoChat,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult
}

public class MessageBackupChatArchiverImpl: MessageBackupChatArchiver {

    private let dmConfigurationStore: DisappearingMessagesConfigurationStore
    private let threadStore: ThreadStore

    public init(
        dmConfigurationStore: DisappearingMessagesConfigurationStore,
        threadStore: ThreadStore
    ) {
        self.dmConfigurationStore = dmConfigurationStore
        self.threadStore = threadStore
    }

    // MARK: - Archiving

    public func archiveChats(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        var completeFailureError: Error?
        var partialErrors = [ArchiveMultiFrameResult.Error]()

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
                owsFailDebug("Got invalid thread when iterating!")
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
            owsFailDebug("Unable to enumerate all threads!")
            return .completeFailure(error)
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

        guard let recipientId = context.recipientContext[.localAddress] else {
            return .partialSuccess([.init(
                objectId: chatId,
                error: .referencedIdMissing(.recipient(.localAddress))
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
            return .partialSuccess([.init(
                objectId: chatId,
                error: .contactThreadMissingAddress
            )])
        }

        guard let recipientId = context.recipientContext[recipientAddress] else {
            return .partialSuccess([.init(
                objectId: chatId,
                error: .referencedIdMissing(.recipient(recipientAddress))
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
            return .partialSuccess([.init(
                objectId: chatId,
                error: .referencedIdMissing(.recipient(recipientAddress))
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

        // TODO: actually use the pinned thread order.
        let thisThreadPinnedOrder: UInt32
        let isThreadPinned = false
        if isThreadPinned {
            context.pinnedThreadOrder += 1
            thisThreadPinnedOrder = context.pinnedThreadOrder
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

        let chatBuilder = BackupProtoChat.builder(
            id: chatId.value,
            recipientID: recipientId.value,
            archived: threadAssociatedData.isArchived,
            pinnedOrder: thisThreadPinnedOrder,
            expirationTimerMs: UInt64(expirationTimerSeconds * 1000),
            muteUntilMs: threadAssociatedData.mutedUntilTimestamp,
            markedUnread: threadAssociatedData.isMarkedUnread,
            dontNotifyForMentionsIfMuted: dontNotifyForMentionsIfMuted
        )

        let error = Self.writeFrameToStream(stream) { frameBuilder in
            let chatProto = try chatBuilder.build()
            frameBuilder.setChat(chatProto)
            return try frameBuilder.build()
        }
        if let error {
            return .partialSuccess([.init(objectId: chatId, error: error)])
        } else {
            return .success
        }
    }

    // MARK: - Restoring

    public func restore(
        _ chat: BackupProtoChat,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        let thread: MessageBackup.ChatThread
        switch context.recipientContext[chat.recipientId] {
        case .none:
            return .failure(
                chat.chatId,
                [.identifierNotFound(.recipient(chat.recipientId))]
            )
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
                return .failure(
                    chat.chatId,
                    [.referencedDatabaseObjectNotFound(.groupThread(groupId: groupId))]
                )
            }
            thread = .groupV2(groupThread)
        case .contact(let address):
            let contactThread = threadStore.getOrCreateContactThread(with: address.asInteropAddress(), tx: tx)
            thread = .contact(contactThread)
        }

        context[chat.chatId] = thread.uniqueId

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
        // TODO: recover pinned chat ordering
        if chat.pinnedOrder != 0 {
            do {
                // TODO: reimplement thread pinning.
                // try threadFetcher.pinThread(thread, tx: tx)
            } catch {
                // TODO: how could this fail, and what should we do? Ignore for now.
            }
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
