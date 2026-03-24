//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc(OWSOutgoingReactionMessage)
final class OutgoingReactionMessage: TransientOutgoingMessage {

    let messageUniqueId: String
    let emoji: String
    let isRemoving: Bool
    let createdReaction: OWSReaction?
    let previousReaction: OWSReaction?

    init(
        timestamp: UInt64,
        emoji: String,
        isRemoving: Bool,
        inThread thread: TSThread,
        onMessage message: TSMessage,
        newReaction: OWSReaction?,
        oldReaction: OWSReaction?,
        expiresInSeconds: UInt32,
        expireTimerVersion: UInt32,
        tx: DBReadTransaction,
    ) {
        owsAssertDebug(thread.uniqueId == message.uniqueThreadId)
        owsAssertDebug(emoji.isSingleEmoji)

        self.messageUniqueId = message.uniqueId
        self.emoji = emoji
        self.isRemoving = isRemoving
        self.createdReaction = newReaction
        self.previousReaction = oldReaction

        let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread)
        messageBuilder.timestamp = timestamp
        messageBuilder.expiresInSeconds = expiresInSeconds
        messageBuilder.expireTimerVersion = NSNumber(value: expireTimerVersion)
        super.init(
            outgoingMessageWith: messageBuilder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let createdReaction {
            coder.encode(createdReaction, forKey: "createdReaction")
        }
        coder.encode(self.emoji, forKey: "emoji")
        coder.encode(NSNumber(value: self.isRemoving), forKey: "isRemoving")
        coder.encode(self.messageUniqueId, forKey: "messageUniqueId")
        if let previousReaction {
            coder.encode(previousReaction, forKey: "previousReaction")
        }
    }

    required init?(coder: NSCoder) {
        self.createdReaction = coder.decodeObject(of: OWSReaction.self, forKey: "createdReaction")
        guard let emoji = coder.decodeObject(of: NSString.self, forKey: "emoji") as String? else {
            return nil
        }
        self.emoji = emoji
        guard let isRemoving = coder.decodeObject(of: NSNumber.self, forKey: "isRemoving") else {
            return nil
        }
        self.isRemoving = isRemoving.boolValue
        guard let messageUniqueId = coder.decodeObject(of: NSString.self, forKey: "messageUniqueId") as String? else {
            return nil
        }
        self.messageUniqueId = messageUniqueId
        self.previousReaction = coder.decodeObject(of: OWSReaction.self, forKey: "previousReaction")
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.createdReaction)
        hasher.combine(self.emoji)
        hasher.combine(self.isRemoving)
        hasher.combine(self.messageUniqueId)
        hasher.combine(self.previousReaction)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.createdReaction == object.createdReaction else { return false }
        guard self.emoji == object.emoji else { return false }
        guard self.isRemoving == object.isRemoving else { return false }
        guard self.messageUniqueId == object.messageUniqueId else { return false }
        guard self.previousReaction == object.previousReaction else { return false }
        return true
    }

    override func dataMessageBuilder(with thread: TSThread, transaction tx: DBReadTransaction) -> SSKProtoDataMessageBuilder? {
        guard let reactionProto = self.buildDataMessageReactionProto(tx: tx) else {
            return nil
        }

        let builder = super.dataMessageBuilder(with: thread, transaction: tx)
        builder?.setTimestamp(self.timestamp)
        builder?.setReaction(reactionProto)
        builder?.setRequiredProtocolVersion(UInt32(SSKProtoDataMessageProtocolVersion.reactions.rawValue))
        return builder
    }

    override var relatedUniqueIds: Set<String> {
        return super.relatedUniqueIds.union([self.messageUniqueId])
    }

    private func buildDataMessageReactionProto(tx: DBReadTransaction) -> SSKProtoDataMessageReaction? {
        guard let message = TSMessage.fetchMessageViaCache(uniqueId: messageUniqueId, transaction: tx) else {
            owsFailDebug("Missing message for reaction.")
            return nil
        }

        let reactionBuilder = SSKProtoDataMessageReaction.builder(emoji: emoji, timestamp: message.timestamp)
        reactionBuilder.setRemove(isRemoving)

        let messageAuthor: Aci?
        switch message {
        case is TSOutgoingMessage:
            messageAuthor = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aci
        case let message as TSIncomingMessage:
            messageAuthor = message.authorAddress.aci
        default:
            messageAuthor = nil
        }
        guard let messageAuthor else {
            owsFailDebug("Missing author for reaction.")
            return nil
        }
        reactionBuilder.setTargetAuthorAciBinary(messageAuthor.serviceIdBinary)

        do {
            return try reactionBuilder.build()
        } catch {
            owsFailDebug("Couldn't build protobuf: \(error)")
            return nil
        }
    }

    override func updateWithAllSendingRecipientsMarkedAsFailed(
        error: (any Error)? = nil,
        transaction tx: DBWriteTransaction,
    ) {
        super.updateWithAllSendingRecipientsMarkedAsFailed(error: error, transaction: tx)

        revertLocalStateIfFailedForEveryone(tx: tx)
    }

    private func revertLocalStateIfFailedForEveryone(tx: DBWriteTransaction) {
        // Do nothing if we successfully delivered to anyone. Only cleanup
        // local state if we fail to deliver to anyone.
        guard sentRecipientAddresses().isEmpty else {
            Logger.warn("Failed to send reaction to some recipients")
            return
        }

        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aci else {
            owsFailDebug("Missing localAci.")
            return
        }
        guard let message = TSMessage.fetchMessageViaCache(uniqueId: messageUniqueId, transaction: tx) else {
            owsFailDebug("Missing message.")
            return
        }

        Logger.error("Failed to send reaction to all recipients.")

        let currentReaction = message.reaction(for: localAci, tx: tx)

        guard currentReaction?.uniqueId == self.createdReaction?.uniqueId else {
            Logger.info("Keeping latest reaction because it's different than the failed message.")
            return
        }

        if let previousReaction {
            message.recordReaction(
                for: localAci,
                emoji: previousReaction.emoji,
                sentAtTimestamp: previousReaction.sentAtTimestamp,
                sortOrder: previousReaction.sortOrder,
                tx: tx,
            )
        } else {
            message.removeReaction(for: localAci, tx: tx)
        }
    }
}
