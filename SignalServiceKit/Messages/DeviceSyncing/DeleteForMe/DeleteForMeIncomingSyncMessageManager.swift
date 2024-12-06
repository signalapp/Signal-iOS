//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// A namespace for types related to "delete for me" sync messages.
public enum DeleteForMeSyncMessage {
    public enum Incoming {
        public enum Conversation {
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

        /// Describes a message that can be "addressed" across clients.
        public struct AddressableMessage {
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

        /// Identifies an attachment within a message across clients, using a
        /// variety of identifying information about the attachment.
        public struct AttachmentIdentifier {
            /// A unique identifier for this attachment among others in the same
            /// message. Preferred if available.
            /// - SeeAlso ``AttachmentReference/knownIdInOwningMessage``
            let clientUuid: UUID?
            /// The SHA256 hash of the encrypted (IV | ciphertext | HMAC) blob
            /// for this attachment on the CDN.
            /// - SeeAlso ``Attachment/StreamInfo/digestSHA256Ciphertext``
            let encryptedDigest: Data?
            /// The SHA256 hash of the plaintext of the attachment.
            /// - SeeAlso ``Attachment/StreamInfo/sha256ContentHash``
            let plaintextHash: Data?
        }
    }
}

/// Responsible for handling the actions contained in an incoming `DeleteForMe`
/// sync message.
///
/// - Note
/// This is contrasted with "delete for everyone" actions, which use a
/// ``TSOutgoingDeleteMessage`` to ask the recipients of a "target message" to
/// delete that message and replace it with a tombstone.
public protocol DeleteForMeIncomingSyncMessageManager {
    typealias Conversation = DeleteForMeSyncMessage.Incoming.Conversation
    typealias AddressableMessage = DeleteForMeSyncMessage.Incoming.AddressableMessage
    typealias AttachmentIdentifier = DeleteForMeSyncMessage.Incoming.AttachmentIdentifier

    /// Delete the given message from the given conversation.
    func handleMessageDelete(
        conversation: Conversation,
        addressableMessage: AddressableMessage,
        tx: DBWriteTransaction
    )

    /// Delete the given attachment from the given message in the given
    /// conversation.
    func handleAttachmentDelete(
        conversation: Conversation,
        targetMessage: AddressableMessage,
        attachmentIdentifier: AttachmentIdentifier,
        tx: DBWriteTransaction
    )

    /// Delete the given conversation, using the given addressable messages as
    /// an "anchor" before which to delete.
    ///
    /// - Parameter mostRecentAddressableMessages
    /// A selection of the most recent addressable messages in the conversation
    /// according to the sender.
    /// - Parameter mostRecentNonExpiringAddressableMessages
    /// A selection of the most recent non-expiring addressable messages in the
    /// conversation according to the sender, in case all of the most recent
    /// messages have expired by the time we're handling this sync message.
    /// - Parameter isFullDelete
    /// Whether the sync message resulted from a "full thread deletion", which
    /// includes actions in addition to removing all messages such as removing
    /// from the chat list.
    func handleConversationDelete(
        conversation: Conversation,
        mostRecentAddressableMessages: [AddressableMessage],
        mostRecentNonExpiringAddressableMessages: [AddressableMessage],
        isFullDelete: Bool,
        tx: DBWriteTransaction
    )

    /// Delete the given conversation, which the sender believes contained only
    /// non-addressable (local-only) messages.
    func handleLocalOnlyConversationDelete(
        conversation: Conversation,
        tx: DBWriteTransaction
    )
}

final class DeleteForMeIncomingSyncMessageManagerImpl: DeleteForMeIncomingSyncMessageManager {
    private let addressableMessageFinder: any DeleteForMeAddressableMessageFinder
    private let attachmentManager: any AttachmentManager
    private let attachmentStore: any AttachmentStore
    private let bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue
    private let interactionDeleteManager: any InteractionDeleteManager
    private let threadSoftDeleteManager: any ThreadSoftDeleteManager

    private let logger = PrefixedLogger(prefix: "[DeleteForMe]")

    init(
        addressableMessageFinder: any DeleteForMeAddressableMessageFinder,
        attachmentManager: any AttachmentManager,
        attachmentStore: any AttachmentStore,
        bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue,
        interactionDeleteManager: any InteractionDeleteManager,
        threadSoftDeleteManager: any ThreadSoftDeleteManager
    ) {
        self.addressableMessageFinder = addressableMessageFinder
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
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
            threadUniqueId: conversation.threadUniqueId,
            addressableMessage: addressableMessage,
            tx: tx
        ) else {
            logger.warn("No message found for incoming message-delete sync: \(addressableMessage.author):\(addressableMessage.sentTimestamp) in \(conversation.threadUniqueId).")
            return
        }

        interactionDeleteManager.delete(
            message,
            sideEffects: .custom(associatedCallDelete: .localDeleteOnly),
            tx: tx
        )
    }

    func handleAttachmentDelete(
        conversation: Conversation,
        targetMessage: AddressableMessage,
        attachmentIdentifier: AttachmentIdentifier,
        tx: any DBWriteTransaction
    ) {
        let logger = logger.suffixed(with: "[\(targetMessage.author):\(targetMessage.sentTimestamp) in \(conversation.threadUniqueId)]")

        guard let targetMessage = addressableMessageFinder.findLocalMessage(
            threadUniqueId: conversation.threadUniqueId,
            addressableMessage: targetMessage,
            tx: tx
        ) else {
            logger.warn("Target message not found for incoming attachment-delete sync.")
            return
        }

        /// `DeleteForMe` syncing only applies to body media attachments, so
        /// we'll pull all of them for the target message to see which one
        /// matches the attachment identifer we were given.
        let targetAttachmentCandidates: [ReferencedAttachment] = attachmentStore.fetchReferencedAttachments(
            for: .messageBodyAttachment(messageRowId: targetMessage.sqliteRowId!),
            tx: tx
        )

        /// Look for a "match" among all our candidates, first by comparing the
        /// `clientUuid` (added recently for attachments going forward), then
        /// by the `encryptedDigest` (which should identify most legacy
        /// attachments) and finally by the `plaintextHash` (a last-ditch option
        /// for if somehow the encrypted digest is missing).
        let targetAttachment: ReferencedAttachment? = {
            if
                let clientUuid = attachmentIdentifier.clientUuid,
                let clientUuidMatch = targetAttachmentCandidates.first(where: { $0.reference.knownIdInOwningMessage == clientUuid })
            {
                return clientUuidMatch
            } else if
                let encryptedDigest = attachmentIdentifier.encryptedDigest,
                let encryptedDigestMatch = targetAttachmentCandidates.first(where: {
                    let attachmentDigest =
                        $0.attachment.asStream()?.encryptedFileSha256Digest
                        ?? $0.attachment.asTransitTierPointer()?.info.digestSHA256Ciphertext
                    return attachmentDigest == encryptedDigest
                })
            {
                return encryptedDigestMatch
            } else if
                let plaintextHash = attachmentIdentifier.plaintextHash,
                let plaintextHashMatch = targetAttachmentCandidates.first(where: { $0.attachment.asStream()?.sha256ContentHash == plaintextHash })
            {
                return plaintextHashMatch
            }

            return nil
        }()

        guard let targetAttachment else {
            logger.warn("Target attachment not found on target message for incoming attachment-delete sync.")
            return
        }

        do {
            try attachmentManager.removeAttachment(
                reference: targetAttachment.reference,
                tx: tx
            )
        } catch {
            logger.error("Failed to delete targe attachment!")
        }
    }

    func handleConversationDelete(
        conversation: Conversation,
        mostRecentAddressableMessages: [AddressableMessage],
        mostRecentNonExpiringAddressableMessages: [AddressableMessage],
        isFullDelete: Bool,
        tx: any DBWriteTransaction
    ) {
        let potentialAnchorMessages: [TSMessage] = (mostRecentAddressableMessages + mostRecentNonExpiringAddressableMessages)
            .compactMap { addressableMessage in
                return addressableMessageFinder.findLocalMessage(
                    threadUniqueId: conversation.threadUniqueId,
                    addressableMessage: addressableMessage,
                    tx: tx
                )
            }

        if potentialAnchorMessages.isEmpty {
            logger.warn("No anchor messages found for incoming thread-delete sync: \(conversation.threadUniqueId).")
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
            threads: [conversation.thread],
            sendDeleteForMeSyncMessage: false,
            tx: tx
        )
    }
}
