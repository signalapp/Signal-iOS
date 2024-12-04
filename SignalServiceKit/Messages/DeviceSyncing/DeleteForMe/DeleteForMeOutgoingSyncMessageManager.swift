//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension DeleteForMeSyncMessage {
    public enum Outgoing {
        /// For the time being, the outgoing and incoming representations of
        /// attachment identifiers are equivalent.
        /// - SeeAlso ``DeleteForMeSyncMessage/Incoming/AttachmentIdentifier``
        public typealias AttachmentIdentifier = Incoming.AttachmentIdentifier

        /// Wraps data necessary send a `DeleteForMe` sync message about a
        /// thread deletion.
        ///
        /// This is intentionally a reference type to facilitate its use as a
        /// kind of "builder".
        public class ThreadDeletionContext {
            private enum Constants {
                /// The max number of addressable messages to collect, per
                /// category thereof.
                static let maxAddressableMessages = 5
            }

            private let threadUniqueId: String
            private let localIdentifiers: LocalIdentifiers
            private var lastAddedMessageRowId: Int64 = .max

            fileprivate let conversationIdentifier: ConversationIdentifier
            fileprivate let isFullDelete: Bool

            fileprivate var areAnyMostRecentMessagesExpiring: Bool = false
            fileprivate var mostRecentAddressableMessages: [AddressableMessage] = []
            fileprivate var mostRecentNonExpiringAddressableMessages: [AddressableMessage] = []

            init(
                conversationIdentifier: ConversationIdentifier,
                isFullDelete: Bool,
                threadUniqueId: String,
                localIdentifiers: LocalIdentifiers
            ) {
                self.conversationIdentifier = conversationIdentifier
                self.isFullDelete = isFullDelete

                self.threadUniqueId = threadUniqueId
                self.localIdentifiers = localIdentifiers
            }

            /// Register the given message as having been deleted from the
            /// thread this context describes.
            ///
            /// - Important
            /// All messages passed to this method must belong to the thread
            /// this context describes.
            ///
            /// - Important
            /// Messages must be passed to this method in chat order for the
            /// thread; i.e., descending by SQL row ID.
            func registerMessageDeletedFromThread(_ message: TSMessage) {
                do {
                    let messageRowId = message.sqliteRowId!
                    owsPrecondition(messageRowId < lastAddedMessageRowId)
                    lastAddedMessageRowId = messageRowId

                    owsPrecondition(message.uniqueThreadId == threadUniqueId)
                }

                guard let addressableMessage: AddressableMessage = .addressing(
                    message: message,
                    localIdentifiers: localIdentifiers
                ) else { return }

                let isMessageExpiring = message.expiresAt > 0

                if mostRecentAddressableMessages.count < Constants.maxAddressableMessages {
                    mostRecentAddressableMessages.append(addressableMessage)
                    areAnyMostRecentMessagesExpiring = areAnyMostRecentMessagesExpiring || isMessageExpiring
                }

                if
                    mostRecentNonExpiringAddressableMessages.count < Constants.maxAddressableMessages,
                    !isMessageExpiring
                {
                    mostRecentNonExpiringAddressableMessages.append(addressableMessage)
                }
            }
        }
    }
}

/// Responsible for sending `DeleteForMe` sync messages related to deletions
/// originating on this device.
public protocol DeleteForMeOutgoingSyncMessageManager {
    typealias Outgoing = DeleteForMeSyncMessage.Outgoing

    /// Send a sync message for the given deleted messages.
    /// - Important
    /// All the given messages must belong to the given thread.
    func send(
        deletedMessages: [TSMessage],
        thread: TSThread,
        localIdentifiers: LocalIdentifiers,
        tx: any DBWriteTransaction
    )

    /// Send a sync message that the attachments with the given identifiers were
    /// deleted from their respective messages.
    /// - Important
    /// All the given messages must belong to the given thread.
    func send(
        deletedAttachmentIdentifiers: [TSMessage: [Outgoing.AttachmentIdentifier]],
        thread: TSThread,
        localIdentifiers: LocalIdentifiers,
        tx: any DBWriteTransaction
    )

    /// Send a sync message for the given thread deletion contexts.
    func send(
        threadDeletionContexts: [Outgoing.ThreadDeletionContext],
        tx: any DBWriteTransaction
    )

    /// Get a deletion context for the given thread. This context should be
    /// requested by callers before a thread is deleted, and subsequently
    /// populated with the messages deleted from the thread during its deletion.
    ///
    /// - Important
    /// The returned context is only valid within the transaction in which it
    /// was created.
    ///
    /// - SeeAlso ``Outgoing/ThreadDeletionContext/registerMessageDeletedFromThread``
    func makeThreadDeletionContext(
        thread: TSThread,
        isFullDelete: Bool,
        localIdentifiers: LocalIdentifiers,
        tx: any DBReadTransaction
    ) -> Outgoing.ThreadDeletionContext?
}

public extension DeleteForMeOutgoingSyncMessageManager {
    /// Send a sync message that the given attachments were deleted from their
    /// respective messages.
    /// - Important
    /// All the given messages must belong to the given thread.
    func send(
        deletedAttachments: [TSMessage: [ReferencedAttachment]],
        thread: TSThread,
        localIdentifiers: LocalIdentifiers,
        tx: any DBWriteTransaction
    ) {
        var deletedAttachmentIdentifiers = [TSMessage: [Outgoing.AttachmentIdentifier]]()

        for (message, attachments) in deletedAttachments {
            let attachmentIdentifiers: [Outgoing.AttachmentIdentifier] = attachments.map { attachment in
                return Outgoing.AttachmentIdentifier(
                    clientUuid: attachment.reference.knownIdInOwningMessage,
                    encryptedDigest: attachment.attachment.asStream()?.encryptedFileSha256Digest,
                    plaintextHash: attachment.attachment.asStream()?.sha256ContentHash
                )
            }

            deletedAttachmentIdentifiers[message] = attachmentIdentifiers
        }

        send(
            deletedAttachmentIdentifiers: deletedAttachmentIdentifiers,
            thread: thread,
            localIdentifiers: localIdentifiers,
            tx: tx
        )
    }
}

// MARK: -

final class DeleteForMeOutgoingSyncMessageManagerImpl: DeleteForMeOutgoingSyncMessageManager {
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let syncMessageSender: any Shims.SyncMessageSender
    private let threadStore: any ThreadStore

    private let logger = PrefixedLogger(prefix: "[DeleteForMe]")

    init(
        recipientDatabaseTable: any RecipientDatabaseTable,
        syncMessageSender: any Shims.SyncMessageSender,
        threadStore: any ThreadStore
    ) {
        self.recipientDatabaseTable = recipientDatabaseTable
        self.syncMessageSender = syncMessageSender
        self.threadStore = threadStore
    }

    func send(
        deletedMessages: [TSMessage],
        thread: TSThread,
        localIdentifiers: LocalIdentifiers,
        tx: any DBWriteTransaction
    ) {
        guard let conversationIdentifier = conversationIdentifier(thread: thread, tx: tx) else {
            return
        }

        let addressableMessages = deletedMessages.compactMap { message -> Outgoing.AddressableMessage? in
            return .addressing(message: message, localIdentifiers: localIdentifiers)
        }

        if addressableMessages.isEmpty { return }

        for addressableMessageBatch in Batcher().batch(addressableMessages: addressableMessages) {
            /// The sync message supports sending individual-message deletes
            /// across multiple conversations in one message, but we don't have
            /// any UX affordances that'd let you do so in practice.
            let messageDeletes = Outgoing.MessageDeletes(
                conversationIdentifier: conversationIdentifier,
                addressableMessages: addressableMessageBatch
            )

            sendSyncMessage(
                contents: DeleteForMeOutgoingSyncMessage.Contents(
                    messageDeletes: [messageDeletes],
                    attachmentDeletes: [],
                    conversationDeletes: [],
                    localOnlyConversationDelete: []
                ),
                tx: tx
            )
        }
    }

    func send(
        deletedAttachmentIdentifiers: [TSMessage: [Outgoing.AttachmentIdentifier]],
        thread: TSThread,
        localIdentifiers: LocalIdentifiers,
        tx: any DBWriteTransaction
    ) {
        guard let conversationIdentifier = conversationIdentifier(thread: thread, tx: tx) else {
            return
        }

        let attachmentDeletes: [Outgoing.AttachmentDelete] = deletedAttachmentIdentifiers
            .compactMap { (message, attachmentIdentifiers) -> [Outgoing.AttachmentDelete]? in
                guard let targetMessage: Outgoing.AddressableMessage = .addressing(
                    message: message,
                    localIdentifiers: localIdentifiers
                ) else {
                    // We failed to convert the deleted-from message into an
                    // addressable message. This should never happen!
                    return nil
                }

                return attachmentIdentifiers.map { attachmentIdentifier -> Outgoing.AttachmentDelete in
                    return Outgoing.AttachmentDelete(
                        conversationIdentifier: conversationIdentifier,
                        targetMessage: targetMessage,
                        clientUuid: attachmentIdentifier.clientUuid,
                        encryptedDigest: attachmentIdentifier.encryptedDigest,
                        plaintextHash: attachmentIdentifier.plaintextHash
                    )
                }
            }
            .flatMap { $0 }

        for attachmentBatch in Batcher().batch(attachmentDeletes: attachmentDeletes) {
            sendSyncMessage(
                contents: DeleteForMeOutgoingSyncMessage.Contents(
                    messageDeletes: [],
                    attachmentDeletes: attachmentBatch,
                    conversationDeletes: [],
                    localOnlyConversationDelete: []
                ),
                tx: tx
            )
        }
    }

    func send(
        threadDeletionContexts: [Outgoing.ThreadDeletionContext],
        tx: any DBWriteTransaction
    ) {
        for deletionContextBatch in Batcher().batch(threadDeletionContexts: threadDeletionContexts) {
            var conversationDeletes = [Outgoing.ConversationDelete]()
            var localOnlyConversationDeletes = [Outgoing.LocalOnlyConversationDelete]()

            for context in deletionContextBatch {
                if context.mostRecentAddressableMessages.isEmpty {
                    localOnlyConversationDeletes.append(Outgoing.LocalOnlyConversationDelete(
                        conversationIdentifier: context.conversationIdentifier
                    ))
                } else {
                    conversationDeletes.append(Outgoing.ConversationDelete(
                        conversationIdentifier: context.conversationIdentifier,
                        mostRecentAddressableMessages: context.mostRecentAddressableMessages,
                        mostRecentNonExpiringAddressableMessages: { () -> [Outgoing.AddressableMessage] in
                            if context.areAnyMostRecentMessagesExpiring {
                                return context.mostRecentNonExpiringAddressableMessages
                            }

                            return []
                        }(),
                        isFullDelete: context.isFullDelete
                    ))
                }
            }

            sendSyncMessage(
                contents: DeleteForMeOutgoingSyncMessage.Contents(
                    messageDeletes: [],
                    attachmentDeletes: [],
                    conversationDeletes: conversationDeletes,
                    localOnlyConversationDelete: localOnlyConversationDeletes
                ),
                tx: tx
            )
        }
    }

    func makeThreadDeletionContext(
        thread: TSThread,
        isFullDelete: Bool,
        localIdentifiers: LocalIdentifiers,
        tx: any DBReadTransaction
    ) -> Outgoing.ThreadDeletionContext? {
        guard let conversationIdentifier = conversationIdentifier(thread: thread, tx: tx) else {
            return nil
        }

        return Outgoing.ThreadDeletionContext(
            conversationIdentifier: conversationIdentifier,
            isFullDelete: isFullDelete,
            threadUniqueId: thread.uniqueId,
            localIdentifiers: localIdentifiers
        )
    }

    // MARK: -

    private func conversationIdentifier(
        thread: TSThread,
        tx: any DBReadTransaction
    ) -> Outgoing.ConversationIdentifier? {
        if
            let contactThread = thread as? TSContactThread,
            let contactServiceId = recipientDatabaseTable.fetchServiceId(contactThread: contactThread, tx: tx)
        {
            return .threadServiceId(serviceId: contactServiceId.serviceIdUppercaseString)
        } else if
            let contactThread = thread as? TSContactThread,
            let contactE164 = contactThread.contactPhoneNumber
        {
            return .threadE164(e164: contactE164)
        } else if let groupThread = thread as? TSGroupThread {
            return .threadGroupId(groupId: groupThread.groupId)
        }

        logger.warn("No conversation identifier for thread of type: \(type(of: thread)).")
        return nil
    }

    private func sendSyncMessage(
        contents: DeleteForMeOutgoingSyncMessage.Contents,
        tx: any DBWriteTransaction
    ) {
        guard let localThread = threadStore.getOrCreateLocalThread(tx: tx) else {
            logger.error("Missing local thread!")
            return
        }

        logger.info("Sending sync message: \(contents.messageDeletes.count) message deletes; \(contents.conversationDeletes.count) conversation deletes; \(contents.localOnlyConversationDelete.count) local-only conversation deletes.")

        syncMessageSender.sendSyncMessage(
            contents: contents,
            localThread: localThread,
            tx: tx
        )
    }
}

// MARK: - Batching

private extension DeleteForMeOutgoingSyncMessageManagerImpl {
    struct Batcher {
        /// The max number of deletes to include in a single sync message.
        /// Derived from envelope-math to estimate the max number that can fit
        /// into a single sync message, from an allowed-proto-size perspective,
        /// with wide margins.
        private enum MaxSyncMessageSizeConstants {
            static let maxInteractionsPerSyncMessage: Int = 500
            static let maxAttachmentsPerSyncMessage: Int = 500
            static let maxThreadContextsPerSyncMessage: Int = 100
        }

        func batch(addressableMessages: [Outgoing.AddressableMessage]) -> [[Outgoing.AddressableMessage]] {
            return batch(
                addressableMessages,
                maxBatchSize: MaxSyncMessageSizeConstants.maxInteractionsPerSyncMessage
            )
        }

        func batch(attachmentDeletes: [Outgoing.AttachmentDelete]) -> [[Outgoing.AttachmentDelete]] {
            return batch(
                attachmentDeletes,
                maxBatchSize: MaxSyncMessageSizeConstants.maxAttachmentsPerSyncMessage
            )
        }

        func batch(threadDeletionContexts: [Outgoing.ThreadDeletionContext]) -> [[Outgoing.ThreadDeletionContext]] {
            return batch(
                threadDeletionContexts,
                maxBatchSize: MaxSyncMessageSizeConstants.maxThreadContextsPerSyncMessage
            )
        }

        private func batch<T>(
            _ items: any Sequence<T>,
            maxBatchSize: Int
        ) -> [[T]] {
            var batches = [[T]]()

            var currentBatch = [T]()
            for item in items {
                if currentBatch.count < maxBatchSize {
                    currentBatch.append(item)
                } else {
                    batches.append(currentBatch)
                    currentBatch = [item]
                }
            }
            batches.append(currentBatch)

            return batches
        }
    }
}

// MARK: - Shims

extension DeleteForMeOutgoingSyncMessageManagerImpl {
    enum Shims {
        typealias SyncMessageSender = _DeleteForMeOutgoingSyncMessageManagerImpl_SyncMessageSender_Shim
    }

    enum Wrappers {
        typealias SyncMessageSender = _DeleteForMeOutgoingSyncMessageManagerImpl_SyncMessageSender_Wrapper
    }
}

protocol _DeleteForMeOutgoingSyncMessageManagerImpl_SyncMessageSender_Shim {
    func sendSyncMessage(
        contents: DeleteForMeOutgoingSyncMessage.Contents,
        localThread: TSContactThread,
        tx: any DBWriteTransaction
    )
}

final class _DeleteForMeOutgoingSyncMessageManagerImpl_SyncMessageSender_Wrapper: _DeleteForMeOutgoingSyncMessageManagerImpl_SyncMessageSender_Shim {
    private let messageSenderJobQueue: MessageSenderJobQueue

    init(_ messageSenderJobQueue: MessageSenderJobQueue) {
        self.messageSenderJobQueue = messageSenderJobQueue
    }

    func sendSyncMessage(
        contents: DeleteForMeOutgoingSyncMessage.Contents,
        localThread: TSContactThread,
        tx: any DBWriteTransaction
    ) {
        let sdsTx = SDSDB.shimOnlyBridge(tx)

        guard let syncMessage = DeleteForMeOutgoingSyncMessage(
            contents: contents,
            thread: localThread,
            tx: sdsTx
        ) else { return }

        messageSenderJobQueue.add(
            message: .preprepared(transientMessageWithoutAttachments: syncMessage),
            transaction: sdsTx
        )
    }
}

// MARK: - Mock

#if TESTABLE_BUILD

open class MockDeleteForMeOutgoingSyncMessageManager: DeleteForMeOutgoingSyncMessageManager {
    var sendMessagesMock: ((
        _ messages: [TSMessage]
    ) -> Void)!
    public func send(deletedMessages: [TSMessage], thread: TSThread, localIdentifiers: LocalIdentifiers, tx: any DBWriteTransaction) {
        sendMessagesMock(deletedMessages)
    }

    var sendAttachmentsMock: ((
        _ attachmentIdentifiers: [TSMessage: [Outgoing.AttachmentIdentifier]]
    ) -> Void)!
    public func send(deletedAttachmentIdentifiers: [TSMessage: [Outgoing.AttachmentIdentifier]], thread: TSThread, localIdentifiers: LocalIdentifiers, tx: any DBWriteTransaction) {
        sendAttachmentsMock(deletedAttachmentIdentifiers)
    }

    var sendDeletionContextMock: ((
        _ threadContexts: [Outgoing.ThreadDeletionContext]
    ) -> Void)!
    public func send(threadDeletionContexts: [Outgoing.ThreadDeletionContext], tx: any DBWriteTransaction) {
        sendDeletionContextMock(threadDeletionContexts)
    }

    public func makeThreadDeletionContext(thread: TSThread, isFullDelete: Bool, localIdentifiers: LocalIdentifiers, tx: any DBReadTransaction) -> Outgoing.ThreadDeletionContext? {
        let conversationIdentifier: Outgoing.ConversationIdentifier = if let contactThread = thread as? TSContactThread {
            .threadServiceId(serviceId: contactThread.contactUUID!)
        } else if let groupThread = thread as? TSGroupThread {
            .threadGroupId(groupId: groupThread.groupId)
        } else {
            owsFail("Invalid thread!")
        }

        return Outgoing.ThreadDeletionContext(
            conversationIdentifier: conversationIdentifier,
            isFullDelete: isFullDelete,
            threadUniqueId: thread.uniqueId,
            localIdentifiers: localIdentifiers
        )
    }
}

#endif
