//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

final public class OutgoingStorySentMessageTranscript: OWSOutgoingSyncMessage {
    // Exposed to ObjC and made optional for MTLModel serialization

    @objc
    private var storyEncodedRecipientStates: Data?

    @objc
    private var storyMessageUniqueId: String?

    @objc
    private var isRecipientUpdate: NSNumber!

    public init(localThread: TSContactThread, timestamp: UInt64, recipientStates: [ServiceId: StoryRecipientState], transaction: DBReadTransaction) {
        // We need to store the encoded data rather than just the uniqueId
        // of the story message as the story message will have been deleted
        // by the time we're sending this transcript.
        self.storyEncodedRecipientStates = Self.encodeRecipientStates(recipientStates)
        self.isRecipientUpdate = NSNumber(value: true)
        super.init(timestamp: timestamp, localThread: localThread, transaction: transaction)
    }

    public init(localThread: TSContactThread, storyMessage: StoryMessage, transaction: DBReadTransaction) {
        self.storyMessageUniqueId = storyMessage.uniqueId
        self.isRecipientUpdate = NSNumber(value: false)
        super.init(timestamp: storyMessage.timestamp, localThread: localThread, transaction: transaction)
    }

    private static func encodeRecipientStates(_ recipientStates: [ServiceId: StoryRecipientState]) -> Data? {
        return try? JSONEncoder().encode(recipientStates.mapKeys(injectiveTransform: { $0.codableUppercaseString }))
    }

    private static func decodeRecipientStates(_ encodedRecipientStates: Data?) -> [ServiceId: StoryRecipientState]? {
        guard let encodedRecipientStates else {
            return nil
        }
        return (try? JSONDecoder().decode(
            [ServiceIdUppercaseString: StoryRecipientState].self, from: encodedRecipientStates
        ))?.mapKeys(injectiveTransform: { $0.wrappedValue })
    }

    public override var isUrgent: Bool { false }

    private func storyMessage(transaction: DBReadTransaction) -> StoryMessage? {
        guard let storyMessageUniqueId = storyMessageUniqueId else { return nil }
        return StoryMessage.anyFetch(uniqueId: storyMessageUniqueId, transaction: transaction)
    }

    public override func syncMessageBuilder(transaction: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
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

            applyRecipientStates(recipientStates, sentBuilder: sentBuilder)
        } else if let recipientStates = Self.decodeRecipientStates(storyEncodedRecipientStates) {
            applyRecipientStates(recipientStates, sentBuilder: sentBuilder)
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

    private func applyRecipientStates(_ recipientStates: [ServiceId: StoryRecipientState], sentBuilder: SSKProtoSyncMessageSentBuilder) {
        for (serviceId, state) in recipientStates {
            let builder = SSKProtoSyncMessageSentStoryMessageRecipient.builder()
            builder.setDestinationServiceID(serviceId.serviceIdString)
            builder.setDistributionListIds(state.contexts.map { $0.uuidString })
            builder.setIsAllowedToReply(state.allowsReplies)
            sentBuilder.addStoryMessageRecipients(builder.buildInfallibly())
        }
    }

    private func storyMessageProto(for storyMessage: StoryMessage, transaction: DBReadTransaction) -> SSKProtoStoryMessage? {
        let builder = SSKProtoStoryMessage.builder()

        switch storyMessage.attachment {
        case .media:
            guard
                let storyMessageRowId = storyMessage.id,
                let attachment = DependenciesBridge.shared.attachmentStore.fetchFirstReferencedAttachment(
                    for: .storyMessageMedia(storyMessageRowId: storyMessageRowId),
                    tx: transaction
                ),
                let pointer = attachment.attachment.asTransitTierPointer(),
                case let .digestSHA256Ciphertext(digestSHA256Ciphertext) = pointer.info.integrityCheck
            else {
                owsFailDebug("Missing attachment for outgoing story message")
                return nil
            }
            let attachmentProto = DependenciesBridge.shared.attachmentManager.buildProtoForSending(
                from: attachment.reference,
                pointer: pointer,
                digestSHA256Ciphertext: digestSHA256Ciphertext
            )
            builder.setFileAttachment(attachmentProto)
            if let storyMediaCaption = attachment.reference.storyMediaCaption {
                builder.setBodyRanges(storyMediaCaption.toProtoBodyRanges())
            }
        case .text(let attachment):
            guard let attachmentProto = try? attachment.buildProto(
                parentStoryMessage: storyMessage,
                bodyRangeHandler: builder.setBodyRanges(_:),
                transaction: transaction
            ) else {
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
                builder.setGroup(try GroupsV2Protos.buildGroupContextProto(groupModel: groupModel, groupChangeProtoData: nil))
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
