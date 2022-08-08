//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public class OutgoingStoryMessage: TSOutgoingMessage {
    @objc
    public private(set) var storyMessageId: String!
    @objc
    public private(set) var storyAllowsReplies: NSNumber!
    @objc
    public private(set) var isPrivateStorySend: NSNumber!

    public init(thread: TSThread, storyMessage: StoryMessage, transaction: SDSAnyReadTransaction) {
        self.storyMessageId = storyMessage.uniqueId
        self.storyAllowsReplies = NSNumber(value: (thread as? TSPrivateStoryThread)?.allowsReplies ?? true)
        self.isPrivateStorySend = NSNumber(value: thread is TSPrivateStoryThread)
        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.timestamp = storyMessage.timestamp
        super.init(outgoingMessageWithBuilder: builder, transaction: transaction)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    public class func createUnsentMessage(
        attachment: TSAttachmentStream,
        thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) -> OutgoingStoryMessage {
        let storyManifest: StoryManifest = .outgoing(
            recipientStates: thread.recipientAddresses(with: transaction)
                .lazy
                .compactMap { $0.uuid }
                .dictionaryMappingToValues { _ in
                    if let privateStoryThread = thread as? TSPrivateStoryThread {
                        return .init(allowsReplies: privateStoryThread.allowsReplies, contexts: [privateStoryThread.uniqueId])
                    } else {
                        return .init(allowsReplies: true, contexts: [])
                    }
                }
        )
        let storyMessage = StoryMessage(
            timestamp: Date.ows_millisecondTimestamp(),
            authorUuid: tsAccountManager.localUuid!,
            groupId: (thread as? TSGroupThread)?.groupId,
            manifest: storyManifest,
            attachment: .file(attachmentId: attachment.uniqueId)
        )
        storyMessage.anyInsert(transaction: transaction)

        thread.updateWithLastSentStoryTimestamp(NSNumber(value: storyMessage.timestamp), transaction: transaction)

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

        guard let storyMessage = StoryMessage.anyFetch(uniqueId: storyMessageId, transaction: transaction),
                case .outgoing(var recipientStates) = storyMessage.manifest else {
            throw OWSAssertionError("Missing existing story message")
        }

        let recipientAddresses = Set(privateStoryThread.recipientAddresses(with: transaction))

        for address in recipientAddresses {
            guard let uuid = address.uuid else { continue }
            if var recipient = recipientStates[uuid] {
                recipient.contexts.append(privateStoryThread.uniqueId)
                recipient.allowsReplies = recipient.allowsReplies || privateStoryThread.allowsReplies
                recipientStates[uuid] = recipient
            } else {
                recipientStates[uuid] = .init(allowsReplies: privateStoryThread.allowsReplies, contexts: [privateStoryThread.uniqueId])
            }
        }

        storyMessage.updateRecipientStates(recipientStates, transaction: transaction)

        privateStoryThread.updateWithLastSentStoryTimestamp(NSNumber(value: storyMessage.timestamp), transaction: transaction)

        let outgoingMessage = OutgoingStoryMessage(thread: privateStoryThread, storyMessage: storyMessage, transaction: transaction)
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
        if let profileKey = profileManager.profileKeyData(for: tsAccountManager.localAddress!, transaction: transaction) {
            builder.setProfileKey(profileKey)
        }

        switch storyMessage.attachment {
        case .file(let attachmentId):
            guard let attachmentProto = TSAttachmentStream.buildProto(forAttachmentId: attachmentId, transaction: transaction) else {
                owsFailDebug("Missing attachment for outgoing story message")
                return nil
            }
            builder.setFileAttachment(attachmentProto)
        case .text(let attachment):
            // TODO: Sending text attachments
            break
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
}
