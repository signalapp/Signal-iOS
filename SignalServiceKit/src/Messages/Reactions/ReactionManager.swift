//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
        to message: TSMessage,
        emoji: String,
        isRemoving: Bool,
        isHighPriority: Bool = false,
        transaction: SDSAnyWriteTransaction
    ) -> Promise<Void> {
        let outgoingMessage: TSOutgoingMessage
        do {
            outgoingMessage = try _localUserReacted(to: message, emoji: emoji, isRemoving: isRemoving, transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            return Promise(error: error)
        }
        NotificationCenter.default.post(name: ReactionManager.localUserReacted, object: nil)
        let messagePreparer = outgoingMessage.asPreparer
        return Self.messageSenderJobQueue.add(
            .promise,
            message: messagePreparer,
            isHighPriority: isHighPriority,
            transaction: transaction
        )
    }

    // This helper method DRYs up the logic shared by the above methods.
    private class func _localUserReacted(to message: TSMessage,
                                         emoji: String,
                                         isRemoving: Bool,
                                         transaction: SDSAnyWriteTransaction) throws -> OWSOutgoingReactionMessage {
        assert(emoji.isSingleEmoji)

        let thread = message.thread(transaction: transaction)
        guard thread.canSendReactionToThread else {
            throw OWSAssertionError("Cannot send to thread.")
        }

        if DebugFlags.internalLogging {
            Logger.info("Sending reaction: \(emoji) isRemoving: \(isRemoving), message.timestamp: \(message.timestamp)")
        } else {
            Logger.info("Sending reaction, isRemoving: \(isRemoving)")
        }

        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSAssertionError("missing local address")
        }

        // Though we generally don't parse the expiration timer from
        // reaction messages, older desktop instances will read it
        // from the "unsupported" message resulting in the timer
        // clearing. So we populate it to ensure that does not happen.
        let expiresInSeconds: UInt32
        if let configuration = OWSDisappearingMessagesConfiguration.anyFetch(
            uniqueId: message.uniqueThreadId,
            transaction: transaction
        ), configuration.isEnabled {
            expiresInSeconds = configuration.durationSeconds
        } else {
            expiresInSeconds = 0
        }

        let outgoingMessage = OWSOutgoingReactionMessage(
            thread: message.thread(transaction: transaction),
            message: message,
            emoji: emoji,
            isRemoving: isRemoving,
            expiresInSeconds: expiresInSeconds,
            transaction: transaction
        )

        outgoingMessage.previousReaction = message.reaction(for: localAddress, transaction: transaction)

        if isRemoving {
            message.removeReaction(for: localAddress, transaction: transaction)
        } else {
            outgoingMessage.createdReaction = message.recordReaction(
                for: localAddress,
                emoji: emoji,
                sentAtTimestamp: outgoingMessage.timestamp,
                receivedAtTimestamp: outgoingMessage.timestamp,
                transaction: transaction
            )

            // Always immediately mark outgoing reactions as read.
            outgoingMessage.createdReaction?.markAsRead(transaction: transaction)
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
        reactor: SignalServiceAddress,
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

        guard let messageAuthor = reaction.authorAddress else {
            owsFailDebug("reaction missing author address")
            return .invalidReaction
        }

        if let message = InteractionFinder.findMessage(
            withTimestamp: reaction.timestamp,
            threadId: thread.uniqueId,
            author: messageAuthor,
            transaction: transaction
        ) {
            guard !message.wasRemotelyDeleted else {
                Logger.info("Ignoring reaction for a message that was remotely deleted")
                return .invalidReaction
            }

            // If this is a reaction removal, we want to remove *any* reaction from this author
            // on this message, regardless of the specified emoji.
            if reaction.hasRemove, reaction.remove {
                message.removeReaction(for: reactor, transaction: transaction)
            } else {
                let reaction = message.recordReaction(
                    for: reactor,
                    emoji: emoji,
                    sentAtTimestamp: timestamp,
                    receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                    transaction: transaction
                )

                // If this is a reaction to a message we sent, notify the user.
                if let reaction = reaction, let message = message as? TSOutgoingMessage, !reactor.isLocalAddress {
                    self.notificationsManager?.notifyUser(forReaction: reaction,
                                                          onOutgoingMessage: message,
                                                          thread: thread,
                                                          transaction: transaction)
                }
            }

            return .success
        } else if let storyMessage = StoryFinder.story(
            timestamp: reaction.timestamp,
            author: messageAuthor,
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

            if reactor.isLocalAddress {
                let builder = TSOutgoingMessageBuilder(thread: thread)
                populateStoryContext(on: builder)
                message = builder.build(transaction: transaction)
            } else {
                let builder = TSIncomingMessageBuilder(thread: thread)
                builder.authorAddress = reactor
                builder.serverTimestamp = NSNumber(value: serverTimestamp)
                populateStoryContext(on: builder)
                message = builder.build()
            }

            message.anyInsert(transaction: transaction)

            if let incomingMessage = message as? TSIncomingMessage {
                notificationsManager?.notifyUser(forIncomingMessage: incomingMessage, thread: thread, transaction: transaction)
            } else if let outgoingMessage = message as? TSOutgoingMessage {
                outgoingMessage.updateWithWasSentFromLinkedDevice(
                    withUDRecipientAddresses: sentTranscript?.udRecipientAddresses,
                    nonUdRecipientAddresses: sentTranscript?.nonUdRecipientAddresses,
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
