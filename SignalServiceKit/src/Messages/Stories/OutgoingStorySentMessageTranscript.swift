//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class OutgoingStorySentMessageTranscript: OWSOutgoingSyncMessage {
    // Exposed to ObjC and made optional for MTLModel serialization

    @objc
    private var storyEncodedRecipientStates: Data?

    @objc
    private var storyMessageUniqueId: String?

    @objc
    private var isRecipientUpdate: NSNumber!

    public init(localThread: TSThread, timestamp: UInt64, recipientStates: [UUID: StoryRecipientState], transaction: SDSAnyReadTransaction) {
        // We need to store the encoded data rather than just the uniqueId
        // of the story message as the story message will have been deleted
        // by the time we're sending this transcript.
        self.storyEncodedRecipientStates = try? JSONEncoder().encode(recipientStates)
        self.isRecipientUpdate = NSNumber(value: true)
        super.init(timestamp: timestamp, thread: localThread, transaction: transaction)
    }

    public init(localThread: TSThread, storyMessage: StoryMessage, transaction: SDSAnyReadTransaction) {
        self.storyMessageUniqueId = storyMessage.uniqueId
        self.isRecipientUpdate = NSNumber(value: false)
        super.init(timestamp: storyMessage.timestamp, thread: localThread, transaction: transaction)
    }

    public override var isUrgent: Bool { false }

    private func storyMessage(transaction: SDSAnyReadTransaction) -> StoryMessage? {
        guard let storyMessageUniqueId = storyMessageUniqueId else { return nil }
        return StoryMessage.anyFetch(uniqueId: storyMessageUniqueId, transaction: transaction)
    }

    public override func syncMessageBuilder(transaction: SDSAnyReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let sentBuilder = SSKProtoSyncMessageSent.builder()
        sentBuilder.setTimestamp(timestamp)
        sentBuilder.setIsRecipientUpdate(isRecipientUpdate.boolValue)

        if let storyMessage = storyMessage(transaction: transaction) {
            if !isRecipientUpdate.boolValue {
                guard let storyMessageProto = storyMessageProto(for: storyMessage, transaction: transaction) else {
                    owsFailDebug("Failed to build sync proto for story message with timestamp \(storyMessage.timestamp)")
                    return nil
                }
                sentBuilder.setStoryMessage(storyMessageProto)
            }

            guard case .outgoing(let recipientStates) = storyMessage.manifest else {
                owsFailDebug("Unexpected type for story message sync with timestamp \(storyMessage.timestamp)")
                return nil
            }

            guard applyRecipientStates(recipientStates, sentBuilder: sentBuilder) else { return nil }
        } else if let storyEncodedRecipientStates = storyEncodedRecipientStates,
                  let recipientStates = try? JSONDecoder().decode(
                    [UUID: StoryRecipientState].self,
                    from: storyEncodedRecipientStates
                  ) {
            guard applyRecipientStates(recipientStates, sentBuilder: sentBuilder) else { return nil }
        } else {
            owsFailDebug("Missing recipient states")
            return nil
        }

        do {
            let sentProto = try sentBuilder.build()

            let builder = SSKProtoSyncMessage.builder()
            builder.setSent(sentProto)
            return builder
        } catch {
            owsFailDebug("failed to build proto \(error)")
            return nil
        }
    }

    private func applyRecipientStates(_ recipientStates: [UUID: StoryRecipientState], sentBuilder: SSKProtoSyncMessageSentBuilder) -> Bool {
        for (uuid, state) in recipientStates {
            let builder = SSKProtoSyncMessageSentStoryMessageRecipient.builder()
            builder.setDestinationUuid(uuid.uuidString)
            builder.setDistributionListIds(state.contexts.map { $0.uuidString })
            builder.setIsAllowedToReply(state.allowsReplies)
            do {
                sentBuilder.addStoryMessageRecipients(try builder.build())
            } catch {
                owsFailDebug("Failed to prepare proto for story recipient \(uuid.uuidString) \(error)")
                return false
            }
        }

        return true
    }

    private func storyMessageProto(for storyMessage: StoryMessage, transaction: SDSAnyReadTransaction) -> SSKProtoStoryMessage? {
        let builder = SSKProtoStoryMessage.builder()

        switch storyMessage.attachment {
        case .file(let attachmentId):
            guard let attachmentProto = TSAttachmentStream.buildProto(forAttachmentId: attachmentId, transaction: transaction) else {
                owsFailDebug("Missing attachment for outgoing story message")
                return nil
            }
            builder.setFileAttachment(attachmentProto)
        case .text(let attachment):
            guard let attachmentProto = try? attachment.buildProto(transaction: transaction) else {
                owsFailDebug("Missing attachment for outgoing story message")
                return nil
            }
            builder.setTextAttachment(attachmentProto)
        }

        builder.setAllowsReplies(true)

        do {
            if let groupId = storyMessage.groupId,
               let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction),
               let groupModel = groupThread.groupModel as? TSGroupModelV2 {
                builder.setGroup(try groupsV2.buildGroupContextV2Proto(groupModel: groupModel, changeActionsProtoData: nil))
            }

            return try builder.build()
        } catch {
            owsFailDebug("failed to build protobuf: \(error)")
            return nil
        }
    }

    // MARK: - MTLModel

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public required init(dictionary: [String: Any]) throws {
        try super.init(dictionary: dictionary)
    }
}
