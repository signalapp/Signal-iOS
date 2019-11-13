//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSReactionManager)
public class ReactionManager: NSObject {
    static var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    static var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    @objc(sendReactionForMessage:emoji:isRemoving:transaction:)
    class func sendReaction(for message: TSMessage, emoji: String, isRemoving: Bool, transaction: SDSAnyWriteTransaction) {
        guard FeatureFlags.reactionSend else {
            Logger.info("Not sending reaction, feature disabled")
            return
        }

        Logger.info("Sending reaction: \(emoji) isRemoving: \(isRemoving)")

        guard let localAddress = tsAccountManager.localAddress else {
            return owsFailDebug("missing local address")
        }

        let outgoingMessage = OWSOutgoingReactionMessage(
            thread: message.thread(transaction: transaction),
            message: message,
            emoji: emoji,
            isRemoving: isRemoving
        )

        let removedOrReplacedReaction = message.reaction(for: localAddress, transaction: transaction)

        if isRemoving {
            message.removeReaction(for: localAddress, transaction: transaction)
        } else {
            message.recordReaction(
                for: localAddress,
                emoji: emoji,
                sentAtTimestamp: outgoingMessage.timestamp,
                receivedAtTimestamp: outgoingMessage.timestamp,
                transaction: transaction
            )
        }

        // We intentionally don't send reactions durably since we don't want to clutter
        // the user's message history with failure information. Instead, if it fails in
        // sending to all recipients, we rollback the changes. For example, if you try
        // and react to a message you will immediately see the reaction appear on the
        // bubble. If we end up failing to send, the reaction will disappear from the
        // bubble without any further indication to the user.
        //
        // TODO: Retry this send 3 times back-to-back before failing, to help out
        // with group sends / flakey networks.
        SSKEnvironment.shared.messageSender.sendMessage(.promise, outgoingMessage.asPreparer)
            .catch(on: .global()) { error in
                Logger.error("Failed to send reaction with error: \(error.localizedDescription)")

                // Revert the changes we made.
                // TODO: determine if the message succeeded in sending to _anyone_
                // and if so, ignore this failure.
                databaseStorage.write { transaction in
                    if let removedOrReplacedReaction = removedOrReplacedReaction {
                        message.recordReaction(
                            for: removedOrReplacedReaction.reactor,
                            emoji: removedOrReplacedReaction.emoji,
                            sentAtTimestamp: removedOrReplacedReaction.sentAtTimestamp,
                            receivedAtTimestamp: removedOrReplacedReaction.receivedAtTimestamp,
                            transaction: transaction
                        )
                    } else if !isRemoving {
                        message.removeReaction(for: localAddress, transaction: transaction)
                    }
                }
            }
            .retainUntilComplete()
    }

    @objc
    class func processIncomingReaction(
        _ reaction: SSKProtoDataMessageReaction,
        threadId: String,
        reactor: SignalServiceAddress,
        timestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        guard FeatureFlags.reactionReceive else {
            Logger.info("Ignoring incoming reaction, feature disabled")
            return
        }

        guard let messageAuthor = reaction.authorAddress else {
            return owsFailDebug("reaction missing author address")
        }

        guard let message = TSMessage.findMessage(
            withTimestamp: reaction.timestamp,
            threadId: threadId,
            author: messageAuthor,
            transaction: transaction
        ) else {
            // This is potentially normal. For example, we could've deleted the message locally.
            Logger.info("Received reaction for a message that doesn't exist \(timestamp)")
            return
        }

        // If this is a reaction removal, we want to remove *any* reaction from this author
        // on this message, regardless of the specified emoji.
        if reaction.remove {
            message.removeReaction(for: reactor, transaction: transaction)
        } else {
            message.recordReaction(
                for: reactor,
                emoji: reaction.emoji,
                sentAtTimestamp: timestamp,
                receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                transaction: transaction
            )
        }
    }
}
