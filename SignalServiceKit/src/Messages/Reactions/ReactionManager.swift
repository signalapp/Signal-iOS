//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc(OWSReactionManager)
public class ReactionManager: NSObject {
    public static let localUserReacted = Notification.Name("localUserReacted")
    public static let defaultEmojiSet = ["❤️", "👍", "👎", "😂", "😮", "😢"]

    private static let emojiSetKVS = SDSKeyValueStore(collection: "EmojiSetKVS")
    private static let emojiSetKey = "EmojiSetKey"

    /// Returns custom emoji set by the user, or `nil` if the user has never customized their emoji
    /// (including on linked devices).
    ///
    /// This is important because we shouldn't ever send the default set of reactions over storage service.
    public class func customEmojiSet(transaction: SDSAnyReadTransaction) -> [String]? {
        return emojiSetKVS.getObject(forKey: emojiSetKey, transaction: transaction) as? [String]
    }

    public class func setCustomEmojiSet(_ emojis: [String]?, transaction: SDSAnyWriteTransaction) {
        emojiSetKVS.setObject(emojis, key: emojiSetKey, transaction: transaction)
    }

    @discardableResult
    public class func localUserReacted(
        to messageUniqueId: String,
        emoji: String,
        isRemoving: Bool,
        isHighPriority: Bool = false,
        tx: SDSAnyWriteTransaction
    ) -> Promise<Void> {
        let outgoingMessage: TSOutgoingMessage
        do {
            outgoingMessage = try _localUserReacted(to: messageUniqueId, emoji: emoji, isRemoving: isRemoving, tx: tx)
        } catch {
            owsFailDebug("Error: \(error)")
            return Promise(error: error)
        }
        NotificationCenter.default.post(name: ReactionManager.localUserReacted, object: nil)
        let messagePreparer = outgoingMessage.asPreparer
        return Self.sskJobQueues.messageSenderJobQueue.add(
            .promise,
            message: messagePreparer,
            isHighPriority: isHighPriority,
            transaction: tx
        )
    }

    // This helper method DRYs up the logic shared by the above methods.
    private class func _localUserReacted(
        to messageUniqueId: String,
        emoji: String,
        isRemoving: Bool,
        tx: SDSAnyWriteTransaction
    ) throws -> OWSOutgoingReactionMessage {
        assert(emoji.isSingleEmoji)

        guard let message = TSMessage.anyFetchMessage(uniqueId: messageUniqueId, transaction: tx) else {
            throw OWSAssertionError("Can't find message for reaction.")
        }

        guard let thread = message.thread(tx: tx), thread.canSendReactionToThread else {
            throw OWSAssertionError("Can't send reaction to thread.")
        }

        Logger.info("Sending reaction, isRemoving: \(isRemoving)")

        guard let localAci = tsAccountManager.localIdentifiers(transaction: tx)?.aci else {
            throw OWSAssertionError("missing local address")
        }

        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore

        let outgoingMessage = OWSOutgoingReactionMessage(
            thread: thread,
            message: message,
            emoji: emoji,
            isRemoving: isRemoving,
            // Though we generally don't parse the expiration timer from reaction
            // messages, older desktop instances will read it from the "unsupported"
            // message resulting in the timer clearing. So we populate it to ensure
            // that does not happen.
            expiresInSeconds: dmConfigurationStore.durationSeconds(for: thread, tx: tx.asV2Read),
            transaction: tx
        )

        outgoingMessage.previousReaction = message.reaction(for: ServiceIdObjC(localAci), tx: tx)

        if isRemoving {
            message.removeReaction(for: ServiceIdObjC(localAci), tx: tx)
        } else {
            outgoingMessage.createdReaction = message.recordReaction(
                for: ServiceIdObjC(localAci),
                emoji: emoji,
                sentAtTimestamp: outgoingMessage.timestamp,
                receivedAtTimestamp: outgoingMessage.timestamp,
                tx: tx
            )

            // Always immediately mark outgoing reactions as read.
            outgoingMessage.createdReaction?.markAsRead(transaction: tx)
        }

        return outgoingMessage
    }

    @objc(OWSReactionProcessingResult)
    public enum ReactionProcessingResult: Int, Error {
        case associatedMessageMissing
        case invalidReaction
        case success
    }

    @objc
    public class func processIncomingReaction(
        _ reaction: SSKProtoDataMessageReaction,
        thread: TSThread,
        reactor: ServiceIdObjC,
        timestamp: UInt64,
        serverTimestamp: UInt64,
        expiresInSeconds: UInt32,
        sentTranscript: OWSIncomingSentMessageTranscript?,
        transaction: SDSAnyWriteTransaction
    ) -> ReactionProcessingResult {
        guard let emoji = reaction.emoji.strippedOrNil else {
            owsFailDebug("Received invalid emoji")
            return .invalidReaction
        }
        guard emoji.isSingleEmoji else {
            owsFailDebug("Received invalid emoji")
            return .invalidReaction
        }
        guard let messageAuthor = ServiceId(uuidString: reaction.authorUuid) else {
            owsFailDebug("reaction missing message author")
            return .invalidReaction
        }

        if var message = InteractionFinder.findMessage(
            withTimestamp: reaction.timestamp,
            threadId: thread.uniqueId,
            author: SignalServiceAddress(messageAuthor),
            transaction: transaction
        ) {
            if message.editState == .pastRevision {
                // Reaction targeted an old edit revision, fetch the latest
                // version to ensure the reaction shows up properly.
                if let latestEdit = EditMessageFinder.findMessage(
                    fromEdit: message,
                    transaction: transaction) {
                    message = latestEdit
                } else {
                    Logger.info("Ignoring reaction for missing edit target.")
                    return .invalidReaction
                }
            }

            guard !message.wasRemotelyDeleted else {
                Logger.info("Ignoring reaction for a message that was remotely deleted")
                return .invalidReaction
            }

            // If this is a reaction removal, we want to remove *any* reaction from this author
            // on this message, regardless of the specified emoji.
            if reaction.hasRemove, reaction.remove {
                message.removeReaction(for: reactor, tx: transaction)
            } else {
                let reaction = message.recordReaction(
                    for: reactor,
                    emoji: emoji,
                    sentAtTimestamp: timestamp,
                    receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                    tx: transaction
                )

                // If this is a reaction to a message we sent, notify the user.
                let localAci = tsAccountManager.localIdentifiers(transaction: transaction)?.aci
                if let reaction, let message = message as? TSOutgoingMessage, reactor.wrappedValue != localAci {
                    self.notificationsManager.notifyUser(
                        forReaction: reaction,
                        onOutgoingMessage: message,
                        thread: thread,
                        transaction: transaction
                    )
                }
            }

            return .success
        } else if let storyMessage = StoryFinder.story(
            timestamp: reaction.timestamp,
            author: SignalServiceAddress(messageAuthor),
            transaction: transaction
        ) {
            // Reaction to stories show up as normal messages, they
            // are not associated with standard interactions. As such
            // we need to insert an incoming/outgoing message as appropriate.

            func populateStoryContext(on builder: TSMessageBuilder) {
                builder.timestamp = timestamp
                builder.storyReactionEmoji = reaction.emoji
                builder.storyTimestamp = NSNumber(value: storyMessage.timestamp)

                if storyMessage.authorAddress.isSystemStoryAddress {
                    owsFailDebug("Should not be possible to show a reaction message for system story")
                }

                builder.storyAuthorAddress = storyMessage.authorAddress

                // Group story replies do not follow the thread DM timer, instead they
                // disappear automatically when their parent story disappears.
                builder.expiresInSeconds = thread.isGroupThread ? 0 : expiresInSeconds
            }

            let message: TSMessage

            let localAci = tsAccountManager.localIdentifiers(transaction: transaction)?.aci
            if reactor.wrappedValue == localAci {
                let builder = TSOutgoingMessageBuilder(thread: thread)
                populateStoryContext(on: builder)
                message = builder.build(transaction: transaction)
            } else {
                let builder = TSIncomingMessageBuilder(thread: thread)
                builder.authorAci = reactor
                builder.serverTimestamp = NSNumber(value: serverTimestamp)
                populateStoryContext(on: builder)
                message = builder.build()
            }

            message.anyInsert(transaction: transaction)

            if let incomingMessage = message as? TSIncomingMessage {
                notificationsManager.notifyUser(forIncomingMessage: incomingMessage, thread: thread, transaction: transaction)
            } else if let outgoingMessage = message as? TSOutgoingMessage {
                outgoingMessage.updateWithWasSentFromLinkedDevice(
                    withUDRecipients: sentTranscript?.udRecipients,
                    nonUdRecipients: sentTranscript?.nonUdRecipients,
                    isSentUpdate: false,
                    transaction: transaction
                )
            }

            return .success
        } else {
            // This is potentially normal. For example, we could've deleted the message locally.
            Logger.info("Received reaction for a message that doesn't exist \(timestamp)")
            return .associatedMessageMissing
        }
    }

    @objc
    public class func tryToCleanupOrphanedReaction(
        uniqueId: String,
        thresholdDate: Date,
        shouldPerformRemove: Bool,
        transaction: SDSAnyWriteTransaction
    ) -> Bool {
        guard let reaction = OWSReaction.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            // This could just be a race condition, but it should be very unlikely.
            Logger.warn("Could not load reaction: \(uniqueId)")
            return false
        }

        let creationDate = Date(millisecondsSince1970: reaction.sentAtTimestamp)
        guard !creationDate.isAfter(thresholdDate) else {
            Logger.info("Skipping orphan reaction due to age: \(creationDate.timeIntervalSinceNow)")
            return false
        }

        Logger.info("Removing orphan reaction: \(reaction.uniqueId)")

        // Sometimes we cleanup orphaned data as an audit and don't actually
        // perform the remove operation.
        if shouldPerformRemove { reaction.anyRemove(transaction: transaction) }

        return true
    }
}
