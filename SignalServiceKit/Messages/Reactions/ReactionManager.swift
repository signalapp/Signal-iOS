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
        to targetMessage: TSMessage,
        emoji: String,
        sticker: MessageStickerDataSource?,
        isRemoving: Bool,
        isHighPriority: Bool = false,
        tx: DBWriteTransaction,
    ) -> Promise<Void> {
        guard let targetMessageRowId = targetMessage.sqliteRowId else {
            return Promise(error: OWSAssertionError("Can't react to uninserted message"))
        }
        let outgoingMessage: OutgoingReactionMessage
        do {
            outgoingMessage = try _localUserReacted(
                to: targetMessage.uniqueId,
                emoji: emoji,
                isRemoving: isRemoving,
                sticker: sticker?.info,
                tx: tx
            )
        } catch {
            owsFailDebug("Error: \(error)")
            return Promise(error: error)
        }

        NotificationCenter.default.post(name: ReactionManager.localUserReacted, object: nil)
        let unpreparedMessage = UnpreparedOutgoingMessage.forOutgoingReactionMessage(
            outgoingMessage,
            targetMessage: targetMessage,
            targetMessageRowId: targetMessageRowId,
            reactionRowId: outgoingMessage.createdReaction?.id,
            stickerDataSource: sticker
        )
        let preparedMessage: PreparedOutgoingMessage
        do {
            preparedMessage = try unpreparedMessage.prepare(tx: tx)
        } catch {
            owsFailDebug("Error preparing reaction: \(error)")
            return Promise(error: error)
        }
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
        sticker: StickerInfo?,
        tx: DBWriteTransaction,
    ) throws -> OutgoingReactionMessage {
        assert(emoji.isSingleEmoji)

        guard let message = TSMessage.fetchMessageViaCache(uniqueId: messageUniqueId, transaction: tx) else {
            throw OWSAssertionError("Can't find message for reaction.")
        }

        guard let thread = message.thread(tx: tx), thread.canSendReactionToThread else {
            throw OWSAssertionError("Can't send reaction to thread.")
        }

        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aci else {
            throw OWSAssertionError("missing local address")
        }

        let timestamp = MessageTimestampGenerator.sharedInstance.generateTimestamp()

        let previousReaction = message.reaction(for: localAci, tx: tx)

        var createdReaction: OWSReaction?
        if isRemoving {
            message.removeReaction(for: localAci, tx: tx)
            createdReaction = nil
        } else {
            createdReaction = message.recordReaction(
                for: localAci,
                emoji: emoji,
                sticker: sticker,
                sentAtTimestamp: timestamp,
                receivedAtTimestamp: timestamp,
                tx: tx,
            )?.newValue

            // Always immediately mark outgoing reactions as read.
            createdReaction?.markAsRead(transaction: tx)

            // Refetch to ensure up to date
            createdReaction = message.reaction(for: localAci, tx: tx)
        }

        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmConfig = dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: tx)

        return OutgoingReactionMessage(
            timestamp: timestamp,
            emoji: emoji,
            isRemoving: isRemoving,
            inThread: thread,
            onMessage: message,
            newReaction: createdReaction,
            oldReaction: previousReaction,
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
        reactor: Aci,
        timestamp: UInt64,
        serverTimestamp: UInt64,
        expiresInSeconds: UInt32,
        expireTimerVersion: UInt32?,
        sentTranscript: OWSIncomingSentMessageTranscript?,
        transaction: DBWriteTransaction,
    ) -> ReactionProcessingResult {
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

            // If this is a reaction removal, we want to remove *any* reaction from this author
            // on this message, regardless of the specified emoji.
            if reaction.hasRemove, reaction.remove {
                message.removeReaction(for: reactor, tx: transaction)
            } else {
                let sticker: StickerInfo?
                let stickerPointer: SSKProtoAttachmentPointer?
                if
                    let stickerProto = reaction.sticker,
                    stickerProto.packID.isEmpty.negated,
                    stickerProto.packKey.isEmpty.negated,
                    stickerProto.data.cdnKey?.nilIfEmpty != nil
                {
                    sticker = StickerInfo(
                        packId: stickerProto.packID,
                        packKey: stickerProto.packKey,
                        stickerId: stickerProto.stickerID
                    )
                    stickerPointer = stickerProto.data
                } else {
                    sticker = nil
                    stickerPointer = nil
                }

                let recordedReactions = message.recordReaction(
                    for: reactor,
                    emoji: emoji,
                    sticker: sticker,
                    sentAtTimestamp: timestamp,
                    receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                    tx: transaction,
                )
                // Refetch to get the sqlite id
                let recordedReaction = message.reaction(for: reactor, tx: transaction)

                if
                    let recordedReaction,
                    let sticker,
                    let stickerPointer,
                    let reactionRowId = recordedReaction.id,
                    let messageRowId = message.sqliteRowId,
                    let threadRowId = thread.sqliteRowId
                {
                    let attachmentManager = DependenciesBridge.shared.attachmentManager
                    let attachmentId = try? attachmentManager.createAttachmentPointer(
                        from: OwnedAttachmentPointerProto(
                            proto: stickerPointer,
                            owner: .messageReactionSticker(.init(
                                messageRowId: messageRowId,
                                receivedAtTimestamp: message.receivedAtTimestamp,
                                threadRowId: threadRowId,
                                isPastEditRevision: message.isPastEditRevision(),
                                stickerPackId: sticker.packId,
                                stickerId: sticker.stickerId,
                                reactionRowId: reactionRowId,
                            )),
                        ),
                        tx: transaction,
                    )

                    if let attachmentId {
                        DependenciesBridge.shared.attachmentDownloadManager
                            .enqueueDownloadOfAttachment(
                                id: attachmentId,
                                priority: .default,
                                source: .transitTier,
                                tx: transaction
                            )
                    }
                }

                // If this is a reaction to a message we sent, notify the user.
                let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aci
                if
                    let recordedReaction,
                    recordedReactions?.oldValue?.sentAtTimestamp
                        != recordedReaction.sentAtTimestamp,
                    let message = message as? TSOutgoingMessage,
                    reactor != localAci
                {
                    SSKEnvironment.shared.notificationPresenterRef.notifyUser(
                        forReaction: recordedReaction,
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
                    builder.expireTimerVersion = expireTimerVersion.map(NSNumber.init(value:))
                }
            }

            let message: TSMessage

            let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aci
            let reactionStickerInfo: MessageSticker? = {
                guard
                    let stickerProto = reaction.sticker,
                    !stickerProto.packID.isEmpty,
                    !stickerProto.packKey.isEmpty
                else { return nil }
                return MessageSticker(
                    info: StickerInfo(
                        packId: stickerProto.packID,
                        packKey: stickerProto.packKey,
                        stickerId: stickerProto.stickerID
                    ),
                    emoji: nil
                )
            }()
            if reactor == localAci {
                let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread)
                populateStoryContext(on: builder)
                builder.messageSticker = reactionStickerInfo
                message = builder.build(transaction: transaction)
            } else {
                let builder: TSIncomingMessageBuilder = .withDefaultValues(
                    thread: thread,
                    authorAci: reactor,
                    serverTimestamp: serverTimestamp,
                )
                populateStoryContext(on: builder)
                builder.messageSticker = reactionStickerInfo
                message = builder.build()
            }

            message.anyInsert(transaction: transaction)

            if
                let stickerProto = reaction.sticker,
                let messageRowId = message.sqliteRowId,
                let threadRowId = thread.sqliteRowId
            {
                let attachmentManager = DependenciesBridge.shared.attachmentManager
                _ = try? attachmentManager.createAttachmentPointer(
                    from: OwnedAttachmentPointerProto(
                        proto: stickerProto.data,
                        owner: .messageSticker(.init(
                            messageRowId: messageRowId,
                            receivedAtTimestamp: message.receivedAtTimestamp,
                            threadRowId: threadRowId,
                            isPastEditRevision: message.isPastEditRevision(),
                            stickerPackId: stickerProto.packID,
                            stickerId: stickerProto.stickerID
                        ))
                    ),
                    tx: transaction
                )

                DependenciesBridge.shared.attachmentDownloadManager
                    .enqueueDownloadOfAttachmentsForMessage(
                        message,
                        priority: .default,
                        tx: transaction
                    )
            }

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

    @objc
    public class func tryToCleanupOrphanedReaction(
        uniqueId: String,
        thresholdDate: Date,
        shouldPerformRemove: Bool,
        transaction: DBWriteTransaction,
    ) -> Bool {
        guard let reaction = OWSReaction.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            // This could just be a race condition, but it should be very unlikely.
            Logger.warn("Could not load reaction: \(uniqueId)")
            return false
        }

        let creationDate = Date(millisecondsSince1970: reaction.sentAtTimestamp)
        guard creationDate <= thresholdDate else {
            Logger.info("Skipping orphan reaction due to age: \(-creationDate.timeIntervalSinceNow)")
            return false
        }

        Logger.info("Removing orphan reaction: \(reaction.uniqueId)")

        // Sometimes we cleanup orphaned data as an audit and don't actually
        // perform the remove operation.
        if shouldPerformRemove { reaction.anyRemove(transaction: transaction) }

        return true
    }
}
