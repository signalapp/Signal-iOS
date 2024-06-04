//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

extension DeleteForMeSyncMessage {
    public enum Outgoing {
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

public protocol DeleteForMeOutgoingSyncMessageManager {
    typealias Outgoing = DeleteForMeSyncMessage.Outgoing

    func send(
        deletedInteractions: [TSInteraction],
        thread: TSThread,
        tx: any DBWriteTransaction
    )

    func send(
        threadDeletionContexts: [Outgoing.ThreadDeletionContext],
        tx: any DBWriteTransaction
    )

    func buildThreadDeletionContext(
        thread: TSThread,
        isFullDelete: Bool,
        tx: any DBReadTransaction
    ) -> Outgoing.ThreadDeletionContext?
}

extension DeleteForMeOutgoingSyncMessageManager {
    /// Is sending a `DeleteForMe` sync message enabled at all?
    func isSendingEnabled() -> Bool {
        // [DeleteForMe] TODO: We can remove this 90d after release.
        return FeatureFlags.shouldSendDeleteForMeSyncMessages
            || RemoteConfig.shouldSendDeleteForMeSyncMessages
    }
}

final class DeleteForMeOutgoingSyncMessageManagerImpl: DeleteForMeOutgoingSyncMessageManager {
    private let addressableMessageFinder: any DeleteForMeAddressableMessageFinder
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let threadStore: any ThreadStore
    private let tsAccountManager: any TSAccountManager

    private let logger = PrefixedLogger(prefix: "[DeleteForMe]")

    init(
        addressableMessageFinder: any DeleteForMeAddressableMessageFinder,
        messageSenderJobQueue: MessageSenderJobQueue,
        recipientDatabaseTable: any RecipientDatabaseTable,
        threadStore: any ThreadStore,
        tsAccountManager: any TSAccountManager
    ) {
        self.addressableMessageFinder = addressableMessageFinder
        self.messageSenderJobQueue = messageSenderJobQueue
        self.recipientDatabaseTable = recipientDatabaseTable
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

        if addressableMessages.isEmpty { return }

        /// The sync message supports sending individual-message deletes across
        /// multiple conversations in one message, but we don't have any UX
        /// affordances that'd let you do so in practice.
        let messageDeletes = Outgoing.MessageDeletes(
            conversationIdentifier: conversationIdentifier,
            addressableMessages: addressableMessages
        )

        sendSyncMessage(
            contents: DeleteForMeOutgoingSyncMessage.Contents(
                messageDeletes: [messageDeletes],
                conversationDeletes: [],
                localOnlyConversationDelete: []
            ),
            tx: tx
        )
    }

    func send(
        threadDeletionContexts: [Outgoing.ThreadDeletionContext],
        tx: any DBWriteTransaction
    ) {
        var conversationDeletes = [Outgoing.ConversationDelete]()
        var localOnlyConversationDeletes = [Outgoing.LocalOnlyConversationDelete]()

        for context in threadDeletionContexts {
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
                conversationDeletes: conversationDeletes,
                localOnlyConversationDelete: localOnlyConversationDeletes
            ),
            tx: tx
        )
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
            let contactAci = recipientDatabaseTable.fetchServiceId(contactThread: contactThread, tx: tx) as? Aci
        {
            // [DeleteForMe] What if the service ID is a PNI? Will we always have the E164 then?
            return .threadAci(aci: contactAci.serviceIdUppercaseString)
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
        guard isSendingEnabled() else {
            logger.warn("Skipping delete-for-me sync message, feature not enabled!")
            return
        }

        guard let localThread = threadStore.getOrCreateLocalThread(tx: tx) else {
            logger.error("Missing local thread!")
            return
        }

        logger.info("Sending sync message: \(contents.messageDeletes.count) message deletes; \(contents.conversationDeletes) conversation deletes; \(contents.localOnlyConversationDelete) local-only conversation deletes.")

        let sdsTx: SDSAnyWriteTransaction = SDSDB.shimOnlyBridge(tx)

        guard let syncMessage = DeleteForMeOutgoingSyncMessage(
            contents: contents,
            thread: localThread,
            tx: sdsTx
        ) else {
            logger.error("Failed to build outgoing sync message!")
            return
        }

        messageSenderJobQueue.add(
            message: .preprepared(transientMessageWithoutAttachments: syncMessage),
            transaction: sdsTx
        )
    }
}
