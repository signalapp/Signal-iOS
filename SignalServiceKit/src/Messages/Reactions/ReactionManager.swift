//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSReactionManager)
public class ReactionManager: NSObject {

    // MARK: - Dependencies

    private static var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    private static var tsAccountManager: TSAccountManager {
        return .shared()
    }

    private static var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    // MARK: -

    public static let emojiSet = ["❤️", "👍", "👎", "😂", "😮", "😢"]

    public class func localUserReactedWithDurableSend(to message: TSMessage,
                                                      emoji: String,
                                                      isRemoving: Bool,
                                                      transaction: SDSAnyWriteTransaction) {
        let outgoingMessage: TSOutgoingMessage
        do {
            outgoingMessage = try _localUserReacted(to: message, emoji: emoji, isRemoving: isRemoving, transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            return
        }
        let messagePreparer = outgoingMessage.asPreparer
        SSKEnvironment.shared.messageSenderJobQueue.add(message: messagePreparer, transaction: transaction)
    }

    public class func localUserReactedWithNonDurableSend(to message: TSMessage,
                                                         emoji: String,
                                                         isRemoving: Bool,
                                                         transaction: SDSAnyWriteTransaction) -> Promise<Void> {

        let outgoingMessage: TSOutgoingMessage
        do {
            outgoingMessage = try _localUserReacted(to: message, emoji: emoji, isRemoving: isRemoving, transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            return Promise(error: error)
        }

        let messagePreparer = outgoingMessage.asPreparer
        messagePreparer.insertMessage(linkPreviewDraft: nil, transaction: transaction)

        let (promise, resolver) = Promise<Void>.pending()
        transaction.addAsyncCompletionOffMain {
            self.messageSender.sendMessage(messagePreparer,
                                           success: {
                                            resolver.fulfill(())
            },
                                           failure: { (error: Error) in
                                            resolver.reject(error)
            })
        }
        return promise
    }

    // This helper method DRYs up the logic shared by the above methods.
    private class func _localUserReacted(to message: TSMessage,
                                         emoji: String,
                                         isRemoving: Bool,
                                         transaction: SDSAnyWriteTransaction) throws -> OWSOutgoingReactionMessage {
        assert(emoji.isSingleEmoji)

        let thread = message.thread(transaction: transaction)
        guard thread.canSendToThread else {
            throw OWSAssertionError("Cannot send to thread.")
        }

        Logger.info("Sending reaction: \(emoji) isRemoving: \(isRemoving)")

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
            expiresInSeconds: expiresInSeconds
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
    class func processIncomingReaction(
        _ reaction: SSKProtoDataMessageReaction,
        threadId: String,
        reactor: SignalServiceAddress,
        timestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) -> ReactionProcessingResult {
        guard reaction.emoji.isSingleEmoji else {
            owsFailDebug("Received invalid emoji")
            return .invalidReaction
        }

        guard let messageAuthor = reaction.authorAddress else {
            owsFailDebug("reaction missing author address")
            return .invalidReaction
        }

        guard let message = InteractionFinder.findMessage(
            withTimestamp: reaction.timestamp,
            threadId: threadId,
            author: messageAuthor,
            transaction: transaction
        ) else {
            // This is potentially normal. For example, we could've deleted the message locally.
            Logger.info("Received reaction for a message that doesn't exist \(timestamp)")
            return .associatedMessageMissing
        }

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
                emoji: reaction.emoji,
                sentAtTimestamp: timestamp,
                receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                transaction: transaction
            )

            // If this is a reaction to a message we sent, notify the user.
            if let reaction = reaction, let message = message as? TSOutgoingMessage, !reactor.isLocalAddress {
                guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
                    owsFailDebug("Failed to lookup thread for reaction notification.")
                    return .success
                }

                SSKEnvironment.shared.notificationsManager.notifyUser(for: reaction, on: message, thread: thread, transaction: transaction)
            }
        }

        return .success
    }
}
