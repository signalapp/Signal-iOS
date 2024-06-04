//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

enum DeleteForMeSyncMessage {
    enum Conversation {
        case localUser(TSContactThread)
        case contact(TSContactThread)
        case group(TSGroupThread)

        var thread: TSThread {
            switch self {
            case .localUser(let contactThread): return contactThread
            case .contact(let contactThread): return contactThread
            case .group(let groupThread): return groupThread
            }
        }

        var threadUniqueId: String {
            return thread.uniqueId
        }
    }

    struct AddressableMessage {
        enum Author: CustomStringConvertible {
            case localUser
            case otherUser(SignalRecipient)

            var description: String {
                switch self {
                case .localUser: return "localUser"
                case .otherUser(let recipient): return "\(recipient.address)"
                }
            }
        }

        let author: Author
        let sentTimestamp: UInt64
    }
}

/// Responsible for handling the actions contained in an incoming `DeleteForMe`
/// sync message.
///
/// - Note
/// This is contrasted with "delete for everyone" actions, which use a
/// ``TSOutgoingDeleteMessage`` to ask the recipients of a "target message" to
/// delete that message and replace it with a tombstone.
protocol DeleteForMeIncomingSyncMessageManager {
    typealias Conversation = DeleteForMeSyncMessage.Conversation
    typealias AddressableMessage = DeleteForMeSyncMessage.AddressableMessage

    func handleMessageDelete(
        conversation: Conversation,
        addressableMessage: AddressableMessage,
        tx: DBWriteTransaction
    )

    func handleConversationDelete(
        conversation: Conversation,
        mostRecentAddressableMessages: [AddressableMessage],
        isFullDelete: Bool,
        tx: DBWriteTransaction
    )

    func handleLocalOnlyConversationDelete(
        conversation: Conversation,
        tx: DBWriteTransaction
    )
}

final class DeleteForMeIncomingSyncMessageManagerImpl: DeleteForMeIncomingSyncMessageManager {
    private let addressableMessageFinder: DeleteForMeAddressableMessageFinder
    private let bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue
    private let interactionDeleteManager: any InteractionDeleteManager
    private let threadSoftDeleteManager: any ThreadSoftDeleteManager

    private let logger = PrefixedLogger(prefix: "[DFMSyncMsgMgr]")

    init(
        bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue,
        interactionDeleteManager: any InteractionDeleteManager,
        recipientDatabaseTable: any RecipientDatabaseTable,
        threadSoftDeleteManager: any ThreadSoftDeleteManager,
        threadStore: any ThreadStore,
        tsAccountManager: any TSAccountManager
    ) {
        self.addressableMessageFinder = DeleteForMeAddressableMessageFinderImpl(
            threadStore: threadStore,
            recipientDatabaseTable: recipientDatabaseTable,
            tsAccountManager: tsAccountManager
        )
        self.bulkDeleteInteractionJobQueue = bulkDeleteInteractionJobQueue
        self.interactionDeleteManager = interactionDeleteManager
        self.threadSoftDeleteManager = threadSoftDeleteManager
    }

    func handleMessageDelete(
        conversation: Conversation,
        addressableMessage: AddressableMessage,
        tx: any DBWriteTransaction
    ) {
        guard let message = addressableMessageFinder.findLocalMessage(
            conversation: conversation,
            addressableMessage: addressableMessage,
            tx: tx
        ) else {
            logger.warn("No message found for incoming message delete-sync: \(addressableMessage.author):\(addressableMessage.sentTimestamp).")
            return
        }

        interactionDeleteManager.delete(
            message,
            sideEffects: .custom(associatedCallDelete: .localDeleteOnly),
            tx: tx
        )
    }

    func handleConversationDelete(
        conversation: Conversation,
        mostRecentAddressableMessages: [AddressableMessage],
        isFullDelete: Bool,
        tx: any DBWriteTransaction
    ) {
        let potentialAnchorMessages: [TSMessage] = mostRecentAddressableMessages
            .compactMap { addressableMessage in
                return addressableMessageFinder.findLocalMessage(
                    conversation: conversation,
                    addressableMessage: addressableMessage,
                    tx: tx
                )
            }

        if potentialAnchorMessages.isEmpty {
            logger.warn("No anchor messages found for incoming thread delete-sync: \(conversation.threadUniqueId).")
            return
        }

        /// We want to find a single "anchor" message before which we'll delete
        /// all other interactions. By describing multiple potential anchors in
        /// the sync message we improve the odds that this device will find its
        /// copy of one of those anchors.
        ///
        /// If we have multiple anchor candidates, we want the one that shows as
        /// "most recent" on this device; since we order by database insertion,
        /// we want the candidate that was most-recently inserted.
        ///
        /// This also helps mitigate issues in which this device's insertion
        /// order differs from the other device. For example, if the other
        /// device deleted messages ordered `{A,B,C}`, but this device inserted
        /// them as `{B,A,C}`, we still want to ensure all three messages are
        /// deleted. By sending all three messages as anchor candidates, this
        /// device can choose to use `B` as its anchor where the other device
        /// presumably used `A` to achieve the same end result.
        ///
        /// It's not perfect, but it should be a decent approximation given we
        /// can't make guarantees.
        let localAnchorMessage: TSMessage = potentialAnchorMessages.max { lhs, rhs in
            return lhs.sqliteRowId! < rhs.sqliteRowId!
        }!

        /// This is potentially a heavy and long-running operation, if we're
        /// deleting a large number of interactions (e.g., deleted a very old
        /// thread with a lot of messages). Consequently, we'll enqueue it as a
        /// durable job (which will do batched deletions internally).
        bulkDeleteInteractionJobQueue.addJob(
            anchorMessageRowId: localAnchorMessage.sqliteRowId!,
            isFullThreadDelete: isFullDelete,
            threadUniqueId: conversation.threadUniqueId,
            tx: SDSDB.shimOnlyBridge(tx)
        )
    }

    func handleLocalOnlyConversationDelete(
        conversation: Conversation,
        tx: any DBWriteTransaction
    ) {
        if addressableMessageFinder.threadContainsAnyAddressableMessages(
            threadUniqueId: conversation.threadUniqueId,
            tx: tx
        ) {
            // This would be niche, but not impossibe given the right set of
            // conditions (e.g., devices offline at the wrong times, etc). We'll
            // err on the side of caution here, and not delete.
            logger.warn("Ignoring local-only conversation delete, conversation has addressable messages!")
            return
        }

        /// It's not likely there'll be many local-only messages, so we'll
        /// handle them synchronously. This also mitigates the concern of "what
        /// happens if a non-local message shows up in the thread while we're
        /// doing asynchronous delete", since we have no "anchor" message before
        /// which we know it's safe to delete.
        threadSoftDeleteManager.softDelete(
            thread: conversation.thread,
            associatedCallDeleteBehavior: .localDeleteOnly,
            tx: tx
        )
    }
}
