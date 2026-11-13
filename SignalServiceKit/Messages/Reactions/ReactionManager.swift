//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

@objc(OWSReactionManager)
public class ReactionManager: NSObject {
    public static let localUserReacted = Notification.Name("localUserReacted")
    public static let defaultEmojiSet = ["❤️", "👍", "👎", "😂", "😮", "😢"]

    private static let emojiSetKVS = KeyValueStore(collection: "EmojiSetKVS")
    private static let emojiSetKey = "EmojiSetKey"

    /// Returns custom emoji set by the user, or `nil` if the user has never customized their emoji
    /// (including on linked devices).
    ///
    /// This is important because we shouldn't ever send the default set of reactions over storage service.
    public class func customEmojiSet(transaction: DBReadTransaction) -> [String]? {
        return emojiSetKVS.getStringArray(emojiSetKey, transaction: transaction)
    }

    public class func setCustomEmojiSet(_ emojis: [String]?, transaction: DBWriteTransaction) {
        emojiSetKVS.setStringArray(emojis, key: emojiSetKey, transaction: transaction)
    }

    @discardableResult
    public class func localUserReacted(
        to messageUniqueId: String,
        emoji: String,
        isRemoving: Bool,
        isHighPriority: Bool = false,
        tx: DBWriteTransaction,
    ) -> Promise<Void> {
        let outgoingMessage: OutgoingReactionMessage
        do {
            outgoingMessage = try _localUserReacted(to: messageUniqueId, emoji: emoji, isRemoving: isRemoving, tx: tx)
        } catch {
            owsFailDebug("Error: \(error)")
            return Promise(error: error)
        }
        NotificationCenter.default.post(name: ReactionManager.localUserReacted, object: nil)
        let preparedMessage = PreparedOutgoingMessage.preprepared(transientMessageWithoutAttachments: outgoingMessage)
        return SSKEnvironment.shared.messageSenderJobQueueRef.add(
            .promise,
            message: preparedMessage,
            isHighPriority: isHighPriority,
            transaction: tx,
        )
    }

    // This helper method DRYs up the logic shared by the above methods.
    private class func _localUserReacted(
        to messageUniqueId: String,
        emoji: String,
        isRemoving: Bool,
        tx: DBWriteTransaction,
    ) throws -> OutgoingReactionMessage {
        assert(emoji.isSingleEmoji)
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        guard let message = TSMessage.fetchMessageViaCache(uniqueId: messageUniqueId, transaction: tx) else {
            throw OWSAssertionError("Can't find message for reaction.")
        }

        guard let thread = message.thread(tx: tx), thread.canSendReactionToThread else {
            throw OWSAssertionError("Can't send reaction to thread.")
        }

        // If we're not registered, the message send will fail; bail early.
        let registeredState = try tsAccountManager.registeredState(tx: tx)
        let localRecipient = recipientFetcher.fetchOrCreate(serviceId: registeredState.localIdentifiers.aci, tx: tx)

        let timestamp = MessageTimestampGenerator.sharedInstance.generateTimestamp()

        let oldReaction: ReactionRecord?
        let newReaction: ReactionRecord?
        if isRemoving {
            oldReaction = message.removeReaction(forReactorId: localRecipient.id, tx: tx)
            newReaction = nil
        } else {
            let recordedReaction = message.recordReaction(
                forReactorId: localRecipient.id,
                inThread: thread,
                emoji: emoji,
                sentAtTimestamp: timestamp,
                // Always immediately mark outgoing reactions as read.
                markAsRead: true,
                tx: tx,
            )
            oldReaction = recordedReaction?.oldValue
            newReaction = recordedReaction?.newValue
        }

        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmConfig = dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: tx)

        return OutgoingReactionMessage(
            timestamp: timestamp,
            emoji: emoji,
            isRemoving: isRemoving,
            inThread: thread,
            onMessage: message,
            newReaction: newReaction,
            oldReaction: oldReaction,
            // Though we generally don't parse the expiration timer from reaction
            // messages, older desktop instances will read it from the "unsupported"
            // message resulting in the timer clearing. So we populate it to ensure
            // that does not happen.
            expiresInSeconds: dmConfig.durationSeconds,
            expireTimerVersion: dmConfig.timerVersion,
            tx: tx,
        )
    }

    @objc(OWSReactionProcessingResult)
    public enum ReactionProcessingResult: Int, Error {
        case associatedMessageMissing
        case invalidReaction
        case success
    }

    public class func processIncomingReaction(
        _ reaction: SSKProtoDataMessageReaction,
        thread: TSThread,
        reactor reactorAci: Aci,
        timestamp: UInt64,
        serverTimestamp: UInt64,
        expiresInSeconds: UInt32,
        expireTimerVersion: UInt32,
        sentTranscript: OWSIncomingSentMessageTranscript?,
        registeredState: RegisteredState,
        transaction: DBWriteTransaction,
    ) -> ReactionProcessingResult {
        guard SDS.fitsInInt64(reaction.timestamp) else {
            Logger.warn("Ignoring reaction with too-large target timestamp.")
            return .invalidReaction
        }
        guard let emoji = reaction.emoji.strippedOrNil else {
            owsFailDebug("Received invalid emoji")
            return .invalidReaction
        }
        guard emoji.isSingleEmoji else {
            owsFailDebug("Received invalid emoji")
            return .invalidReaction
        }
        guard
            let messageAuthor = Aci.parseFrom(
                serviceIdBinary: reaction.targetAuthorAciBinary,
                serviceIdString: reaction.targetAuthorAci,
            )
        else {
            owsFailDebug("reaction missing message author")
            return .invalidReaction
        }

        if
            var message = InteractionFinder.findMessage(
                withTimestamp: reaction.timestamp,
                threadId: thread.uniqueId,
                author: SignalServiceAddress(messageAuthor),
                transaction: transaction,
            )
        {
            if message.editState == .pastRevision {
                // Reaction targeted an old edit revision, fetch the latest
                // version to ensure the reaction shows up properly.
                if
                    let latestEdit = DependenciesBridge.shared.editMessageStore.findMessage(
                        fromEdit: message,
                        tx: transaction,
                    )
                {
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

            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            let reactor = recipientFetcher.fetchOrCreate(serviceId: reactorAci, tx: transaction)

            // If this is a reaction removal, we want to remove *any* reaction from this author
            // on this message, regardless of the specified emoji.
            if reaction.hasRemove, reaction.remove {
                message.removeReaction(forReactorId: reactor.id, tx: transaction)
            } else {
                let reaction = message.recordReaction(
                    forReactorId: reactor.id,
                    inThread: thread,
                    emoji: emoji,
                    sentAtTimestamp: timestamp,
                    markAsRead: registeredState.localIdentifiers.contains(serviceId: reactorAci),
                    tx: transaction,
                )

                // If this is a reaction to a message we sent, notify the user.
                if
                    let reaction,
                    reaction.oldValue?.sentTimestamp != reaction.newValue.sentTimestamp,
                    let message = message as? TSOutgoingMessage,
                    !registeredState.localIdentifiers.contains(serviceId: reactorAci)
                {
                    SSKEnvironment.shared.notificationPresenterRef.notifyUser(
                        forReaction: reaction.newValue,
                        onOutgoingMessage: message,
                        thread: thread,
                        transaction: transaction,
                    )
                }
            }

            return .success
        } else if
            let storyMessage = StoryFinder.story(
                timestamp: reaction.timestamp,
                author: messageAuthor,
                transaction: transaction,
            )
        {
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

                builder.storyAuthorAci = AciObjC(storyMessage.authorAci)

                // Group story replies do not follow the thread DM timer, instead they
                // disappear automatically when their parent story disappears.
                if thread.isGroupThread {
                    builder.expiresInSeconds = 0
                } else {
                    builder.expiresInSeconds = expiresInSeconds
                    builder.expireTimerVersion = NSNumber(value: expireTimerVersion)
                }
            }

            let message: TSMessage

            if registeredState.localIdentifiers.contains(serviceId: reactorAci) {
                let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread)
                populateStoryContext(on: builder)
                message = builder.build(transaction: transaction)
            } else {
                let builder: TSIncomingMessageBuilder = .withDefaultValues(
                    thread: thread,
                    authorAci: reactorAci,
                    serverTimestamp: serverTimestamp,
                )
                populateStoryContext(on: builder)
                message = builder.build()
            }

            message.anyInsert(transaction: transaction)

            if let incomingMessage = message as? TSIncomingMessage {
                SSKEnvironment.shared.notificationPresenterRef.notifyUser(forIncomingMessage: incomingMessage, thread: thread, transaction: transaction)
            } else if let outgoingMessage = message as? TSOutgoingMessage {
                outgoingMessage.updateRecipientsFromNonLocalDevice(
                    sentTranscript?.recipientStates ?? [:],
                    isSentUpdate: false,
                    transaction: transaction,
                )
            }

            return .success
        } else {
            // This is potentially normal. For example, we could've deleted the message locally.
            Logger.info("Received reaction for a message that doesn't exist \(timestamp)")
            return .associatedMessageMissing
        }
    }
}
