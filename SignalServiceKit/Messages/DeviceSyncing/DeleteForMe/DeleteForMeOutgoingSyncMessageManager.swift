//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

extension DeleteForMeSyncMessage {
    public enum Outgoing {
        /// For the time being, the outgoing and incoming representations of
        /// attachment identifiers are equivalent.
        /// - SeeAlso ``DeleteForMeSyncMessage/Incoming/AttachmentIdentifier``
        public typealias AttachmentIdentifier = Incoming.AttachmentIdentifier

        /// Wraps data necessary send a `DeleteForMe` sync message about a
        /// thread deletion.
        public struct ThreadDeletionContext {
            fileprivate enum DeletionType {
                case conversation(ConversationDelete)
                case localOnlyConversation(LocalOnlyConversationDelete)
            }

            fileprivate let wrapped: DeletionType

            fileprivate init(_ conversation: ConversationDelete) {
                wrapped = .conversation(conversation)
            }

            fileprivate init(_ localOnly: LocalOnlyConversationDelete) {
                wrapped = .localOnlyConversation(localOnly)
            }
        }
    }
}

/// Responsible for sending `DeleteForMe` sync messages related to deletions
/// originating on this device.
public protocol DeleteForMeOutgoingSyncMessageManager {
    typealias Outgoing = DeleteForMeSyncMessage.Outgoing

    /// Send a sync message for the given deleted interactions.
    /// - Important
    /// All the given interactions must belong to the given thread.
    func send(
        deletedInteractions: [TSInteraction],
        thread: TSThread,
        tx: any DBWriteTransaction
    )

    /// Send a sync message that the attachments with the given identifiers were
    /// deleted from their respective messages.
    /// - Important
    /// All the given messages must belong to the given thread.
    func send(
        deletedAttachmentIdentifiers: [TSMessage: [Outgoing.AttachmentIdentifier]],
        thread: TSThread,
        tx: any DBWriteTransaction
    )

    /// Send a sync message for the given thread deletion contexts.
    func send(
        threadDeletionContexts: [Outgoing.ThreadDeletionContext],
        tx: any DBWriteTransaction
    )

    /// Build a deletion context for the given thread.
    ///
    /// This must be done before the thread is deleted, since it will look up
    /// the interactions the thread contains.
    func buildThreadDeletionContext(
        thread: TSThread,
        isFullDelete: Bool,
        tx: any DBReadTransaction
    ) -> Outgoing.ThreadDeletionContext?
}

public extension DeleteForMeOutgoingSyncMessageManager {
    /// Send a sync message that the given attachments were deleted from their
    /// respective messages.
    /// - Important
    /// All the given messages must belong to the given thread.
    func send(
        deletedAttachments: [TSMessage: [ReferencedTSResource]],
        thread: TSThread,
        tx: any DBWriteTransaction
    ) {
        var deletedAttachmentIdentifiers = [TSMessage: [Outgoing.AttachmentIdentifier]]()

        for (message, attachments) in deletedAttachments {
            let attachmentIdentifiers: [Outgoing.AttachmentIdentifier] = attachments.map { attachment in
                return Outgoing.AttachmentIdentifier(
                    clientUuid: attachment.reference.knownIdInOwningMessage(message),
                    encryptedDigest: attachment.attachment.encryptedResourceSha256Digest,
                    plaintextHash: attachment.attachment.knownPlaintextResourceSha256Hash
                )
            }

            deletedAttachmentIdentifiers[message] = attachmentIdentifiers
        }

        send(
            deletedAttachmentIdentifiers: deletedAttachmentIdentifiers,
            thread: thread,
            tx: tx
        )
    }
}

// MARK: -

final class DeleteForMeOutgoingSyncMessageManagerImpl: DeleteForMeOutgoingSyncMessageManager {
    private let addressableMessageFinder: any DeleteForMeAddressableMessageFinder
    private let deleteForMeSyncMessageSettingsStore: any DeleteForMeSyncMessageSettingsStore
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let syncMessageSender: any Shims.SyncMessageSender
    private let threadStore: any ThreadStore
    private let tsAccountManager: any TSAccountManager

    private let logger = PrefixedLogger(prefix: "[DeleteForMe]")

    init(
        addressableMessageFinder: any DeleteForMeAddressableMessageFinder,
        deleteForMeSyncMessageSettingsStore: any DeleteForMeSyncMessageSettingsStore,
        recipientDatabaseTable: any RecipientDatabaseTable,
        syncMessageSender: any Shims.SyncMessageSender,
        threadStore: any ThreadStore,
        tsAccountManager: any TSAccountManager
    ) {
        self.addressableMessageFinder = addressableMessageFinder
        self.deleteForMeSyncMessageSettingsStore = deleteForMeSyncMessageSettingsStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.syncMessageSender = syncMessageSender
        self.threadStore = threadStore
        self.tsAccountManager = tsAccountManager
    }

    func send(
        deletedInteractions: [TSInteraction],
        thread: TSThread,
        tx: any DBWriteTransaction
    ) {
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            logger.error("Skipping individual-message delete sync: not registered!")
            return
        }

        guard let conversationIdentifier = conversationIdentifier(thread: thread, tx: tx) else {
            return
        }

        let addressableMessages = deletedInteractions.compactMap { interaction -> Outgoing.AddressableMessage? in
            return addressableMessage(interaction: interaction, localIdentifiers: localIdentifiers)
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
        tx: any DBWriteTransaction
    ) {
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            logger.error("Skipping individual-attachments delete sync: not registered!")
            return
        }

        guard let conversationIdentifier = conversationIdentifier(thread: thread, tx: tx) else {
            return
        }

        let attachmentDeletes: [Outgoing.AttachmentDelete] = deletedAttachmentIdentifiers
            .compactMap { (message, attachmentIdentifiers) -> [Outgoing.AttachmentDelete]? in
                guard let targetMessage = addressableMessage(
                    interaction: message,
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
                switch context.wrapped {
                case .conversation(let conversation):
                    conversationDeletes.append(conversation)
                case .localOnlyConversation(let localOnly):
                    localOnlyConversationDeletes.append(localOnly)
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

    func buildThreadDeletionContext(
        thread: TSThread,
        isFullDelete: Bool,
        tx: any DBReadTransaction
    ) -> Outgoing.ThreadDeletionContext? {
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            logger.error("Skipping deletion context creation: not registered!")
            return nil
        }

        guard let conversationIdentifier = conversationIdentifier(thread: thread, tx: tx) else {
            return nil
        }

        let mostRecentAddressableMessages: [Outgoing.AddressableMessage] = addressableMessageFinder
            .findMostRecentAddressableMessages(
                threadUniqueId: thread.uniqueId,
                maxCount: 5,
                localIdentifiers: localIdentifiers,
                tx: tx
            )

        if mostRecentAddressableMessages.isEmpty {
            return Outgoing.ThreadDeletionContext(Outgoing.LocalOnlyConversationDelete(
                conversationIdentifier: conversationIdentifier
            ))
        } else {
            return Outgoing.ThreadDeletionContext(Outgoing.ConversationDelete(
                conversationIdentifier: conversationIdentifier,
                mostRecentAddressableMessages: mostRecentAddressableMessages,
                isFullDelete: isFullDelete
            ))
        }
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

    private func addressableMessage(
        interaction: TSInteraction,
        localIdentifiers: LocalIdentifiers
    ) -> Outgoing.AddressableMessage? {
        if let incomingMessage = interaction as? TSIncomingMessage {
            return Outgoing.AddressableMessage(incomingMessage: incomingMessage)
        } else if let outgoingMessage = interaction as? TSOutgoingMessage {
            return Outgoing.AddressableMessage(
                outgoingMessage: outgoingMessage,
                localIdentifiers: localIdentifiers
            )
        }

        return nil
    }

    private func sendSyncMessage(
        contents: DeleteForMeOutgoingSyncMessage.Contents,
        tx: any DBWriteTransaction
    ) {
        guard deleteForMeSyncMessageSettingsStore.isSendingEnabled(tx: tx) else {
            logger.warn("Skipping delete-for-me sync message, feature not enabled!")
            return
        }

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
    var sendInteractionMock: ((
        _ interactions: [TSInteraction]
    ) -> Void)!
    public func send(deletedInteractions: [TSInteraction], thread: TSThread, tx: any DBWriteTransaction) {
        sendInteractionMock(deletedInteractions)
    }

    var sendAttachmentsMock: ((
        _ attachmentIdentifiers: [TSMessage: [Outgoing.AttachmentIdentifier]]
    ) -> Void)!
    public func send(deletedAttachmentIdentifiers: [TSMessage: [Outgoing.AttachmentIdentifier]], thread: TSThread, tx: any DBWriteTransaction) {
        sendAttachmentsMock(deletedAttachmentIdentifiers)
    }

    var sendDeletionContextMock: ((
        _ threadContexts: [Outgoing.ThreadDeletionContext]
    ) -> Void)!
    public func send(threadDeletionContexts: [Outgoing.ThreadDeletionContext], tx: any DBWriteTransaction) {
        sendDeletionContextMock(threadDeletionContexts)
    }

    public func buildThreadDeletionContext(thread: TSThread, isFullDelete: Bool, tx: any DBReadTransaction) -> Outgoing.ThreadDeletionContext? {
        let conversationIdentifier: Outgoing.ConversationIdentifier = if let contactThread = thread as? TSContactThread {
            .threadServiceId(serviceId: contactThread.contactUUID!)
        } else if let groupThread = thread as? TSGroupThread {
            .threadGroupId(groupId: groupThread.groupId)
        } else {
            owsFail("Invalid thread!")
        }

        return Outgoing.ThreadDeletionContext(Outgoing.LocalOnlyConversationDelete(conversationIdentifier: conversationIdentifier))
    }
}

#endif
