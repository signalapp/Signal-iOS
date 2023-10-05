//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public class OutgoingStoryMessage: TSOutgoingMessage {
    @objc
    public private(set) var storyMessageId: String!
    @objc
    public private(set) var storyAllowsReplies: NSNumber!
    @objc
    public private(set) var isPrivateStorySend: NSNumber!
    @objc
    public private(set) var skipSyncTranscript: NSNumber!

    @objc
    public init(
        thread: TSThread,
        storyMessage: StoryMessage,
        skipSyncTranscript: Bool = false,
        transaction: SDSAnyReadTransaction
    ) {
        self.storyMessageId = storyMessage.uniqueId
        self.storyAllowsReplies = NSNumber(value: (thread as? TSPrivateStoryThread)?.allowsReplies ?? true)
        self.isPrivateStorySend = NSNumber(value: thread is TSPrivateStoryThread)
        self.skipSyncTranscript = NSNumber(value: skipSyncTranscript)
        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.timestamp = storyMessage.timestamp
        builder.attachmentIds = storyMessage.allAttachmentIds
        super.init(outgoingMessageWithBuilder: builder, transaction: transaction)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    @objc
    public override var isUrgent: Bool { false }

    public override var isStorySend: Bool { true }

    public override func shouldSyncTranscript() -> Bool { !skipSyncTranscript.boolValue }

    public override func buildTranscriptSyncMessage(
        localThread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) -> OWSOutgoingSyncMessage? {
        guard let storyMessage = StoryMessage.anyFetch(uniqueId: storyMessageId, transaction: transaction) else {
            owsFailDebug("Missing story message")
            return nil
        }

        return OutgoingStorySentMessageTranscript(
            localThread: localThread,
            storyMessage: storyMessage,
            transaction: transaction
        )
    }

    public class func createUnsentMessage(
        attachment: StoryMessageAttachment,
        thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) throws -> OutgoingStoryMessage {
        let storyManifest: StoryManifest = .outgoing(
            recipientStates: try thread.recipientAddresses(with: transaction)
                .lazy
                .compactMap { $0.serviceId }
                .dictionaryMappingToValues { _ in
                    if let privateStoryThread = thread as? TSPrivateStoryThread {
                        guard let threadUuid = UUID(uuidString: privateStoryThread.uniqueId) else {
                            throw OWSAssertionError("Invalid uniqueId for thread \(privateStoryThread.uniqueId)")
                        }
                        return .init(allowsReplies: privateStoryThread.allowsReplies, contexts: [threadUuid])
                    } else {
                        return .init(allowsReplies: true, contexts: [])
                    }
                }
        )
        let storyMessage = StoryMessage(
            timestamp: Date.ows_millisecondTimestamp(),
            authorAci: DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aci,
            groupId: (thread as? TSGroupThread)?.groupId,
            manifest: storyManifest,
            attachment: attachment,
            replyCount: 0
        )
        storyMessage.anyInsert(transaction: transaction)

        thread.updateWithLastSentStoryTimestamp(NSNumber(value: storyMessage.timestamp), transaction: transaction)

        // If story sending for a group was implicitly enabled, explicitly enable it
        if let groupThread = thread as? TSGroupThread, !groupThread.isStorySendExplicitlyEnabled {
            groupThread.updateWithStorySendEnabled(true, transaction: transaction)
        }

        let outgoingMessage = OutgoingStoryMessage(thread: thread, storyMessage: storyMessage, transaction: transaction)
        return outgoingMessage
    }

    public class func createUnsentMessage(
        thread: TSThread,
        storyMessageId: String,
        transaction: SDSAnyWriteTransaction
    ) throws -> OutgoingStoryMessage {
        guard let privateStoryThread = thread as? TSPrivateStoryThread else {
            throw OWSAssertionError("Only private stories should share an existing story message context")
        }

        guard let threadUuid = UUID(uuidString: privateStoryThread.uniqueId) else {
            throw OWSAssertionError("Invalid uniqueId for thread \(privateStoryThread.uniqueId)")
        }

        guard let storyMessage = StoryMessage.anyFetch(uniqueId: storyMessageId, transaction: transaction),
                case .outgoing(var recipientStates) = storyMessage.manifest else {
            throw OWSAssertionError("Missing existing story message")
        }

        let recipientAddresses = Set(privateStoryThread.recipientAddresses(with: transaction))

        for address in recipientAddresses {
            guard let serviceId = address.serviceId else { continue }
            if var recipient = recipientStates[serviceId] {
                recipient.contexts.append(threadUuid)
                recipient.allowsReplies = recipient.allowsReplies || privateStoryThread.allowsReplies
                recipientStates[serviceId] = recipient
            } else {
                recipientStates[serviceId] = .init(allowsReplies: privateStoryThread.allowsReplies, contexts: [threadUuid])
            }
        }

        storyMessage.updateRecipientStates(recipientStates, transaction: transaction)

        privateStoryThread.updateWithLastSentStoryTimestamp(NSNumber(value: storyMessage.timestamp), transaction: transaction)

        // We skip the sync transcript for this message, since it's for
        // an already existing StoryMessage that has been sync'd to our
        // linked devices by another message.
        let outgoingMessage = OutgoingStoryMessage(
            thread: privateStoryThread,
            storyMessage: storyMessage,
            skipSyncTranscript: true,
            transaction: transaction
        )
        return outgoingMessage
    }

    @objc
    public override var shouldBeSaved: Bool { false }
    override var contentHint: SealedSenderContentHint { .implicit }

    public override func contentBuilder(
        thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) -> SSKProtoContentBuilder? {
        guard let storyMessage = storyMessageProto(with: thread, transaction: transaction) else {
            owsFailDebug("Missing story message proto")
            return nil
        }
        let builder = SSKProtoContent.builder()
        builder.setStoryMessage(storyMessage)
        return builder
    }

    @objc
    public func storyMessageProto(with thread: TSThread, transaction: SDSAnyReadTransaction) -> SSKProtoStoryMessage? {
        guard let storyMessageId = storyMessageId,
              let storyMessage = StoryMessage.anyFetch(uniqueId: storyMessageId, transaction: transaction) else {
            Logger.warn("Missing story message for outgoing story.")
            return nil
        }

        let builder = SSKProtoStoryMessage.builder()
        if let profileKey = profileManager.profileKeyData(
            for: DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aciAddress,
            transaction: transaction
        ) {
            builder.setProfileKey(profileKey)
        }

        switch storyMessage.attachment {
        case .file(let file):
            guard let attachmentProto = TSAttachmentStream.buildProto(forAttachmentId: file.attachmentId, transaction: transaction) else {
                owsFailDebug("Missing attachment for outgoing story message")
                return nil
            }
            builder.setFileAttachment(attachmentProto)
            builder.setBodyRanges(file.captionProtoBodyRanges())
        case .text(let attachment):
            guard let attachmentProto = try? attachment.buildProto(
                bodyRangeHandler: builder.setBodyRanges(_:),
                transaction: transaction
            ) else {
                owsFailDebug("Missing attachment for outgoing story message")
                return nil
            }
            builder.setTextAttachment(attachmentProto)
        }

        builder.setAllowsReplies((thread as? TSPrivateStoryThread)?.allowsReplies ?? true)

        do {
            if let groupThread = thread as? TSGroupThread, let groupModel = groupThread.groupModel as? TSGroupModelV2 {
                builder.setGroup(try groupsV2.buildGroupContextV2Proto(groupModel: groupModel, changeActionsProtoData: nil))
            }

            return try builder.build()
        } catch {
            owsFailDebug("failed to build protobuf: \(error)")
            return nil
        }
    }

    public override func anyUpdateOutgoingMessage(transaction: SDSAnyWriteTransaction, block: (TSOutgoingMessage) -> Void) {
        super.anyUpdateOutgoingMessage(transaction: transaction, block: block)

        guard
            let storyMessageId = storyMessageId,
            let storyMessage = StoryMessage.anyFetch(
                uniqueId: storyMessageId,
                transaction: transaction
            )
        else {
            owsFailDebug("Missing story message for outgoing story message")
            return
        }

        storyMessage.updateRecipientStatesWithOutgoingMessageStates(recipientAddressStates, transaction: transaction)
    }

    /// When sending to private stories, each private story list may have overlap in recipients. We want to
    /// dedupe sends such that we only send one copy of a given story to each recipient even though they
    /// are represented in multiple targeted lists.
    ///
    /// Additionally, each private story has different levels of permissions. Some may allow replies & reactions
    /// while others do not. Since we convey to the recipient if this is allowed in the sent proto, it's important that
    /// we send to a recipient only from the thread with the most privilege (or randomly select one with equal privilege)
    public static func dedupePrivateStoryRecipients(for messages: [OutgoingStoryMessage], transaction: SDSAnyWriteTransaction) {
        // Bucket outgoing messages per recipient and story. We may be sending multiple stories if the user selected multiple attachments.
        let messagesPerRecipientPerStory = messages.reduce(into: [String: [SignalServiceAddress: [OutgoingStoryMessage]]]()) { result, message in
            guard message.isPrivateStorySend.boolValue else { return }
            var messagesByRecipient = result[message.storyMessageId] ?? [:]
            for address in message.recipientAddresses() {
                var messages = messagesByRecipient[address] ?? []
                // Always prioritize sending to stories that allow replies,
                // we'll later select the first message from this list as
                // the one to actually send to for a given recipient.
                if message.storyAllowsReplies.boolValue {
                    messages.insert(message, at: 0)
                } else {
                    messages.append(message)
                }
                messagesByRecipient[address] = messages
            }
            result[message.storyMessageId] = messagesByRecipient
        }

        for messagesPerRecipient in messagesPerRecipientPerStory.values {
            for (address, messages) in messagesPerRecipient {
                // For every message after the first for a given recipient, mark the
                // recipient as skipped so we don't send them any additional copies.
                for message in messages.dropFirst() {
                    message.update(withSkippedRecipient: address, transaction: transaction)
                }
            }
        }
    }
}
