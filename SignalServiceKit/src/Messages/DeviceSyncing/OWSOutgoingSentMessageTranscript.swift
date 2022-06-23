//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

public extension OWSOutgoingSentMessageTranscript {
    @objc
    func prepareStorySyncMessageContent(sentBuilder: SSKProtoSyncMessageSentBuilder, transaction: SDSAnyReadTransaction) -> Bool {
        guard let outgoingStoryMessage = message as? OutgoingStoryMessage else { return false }

        // Only include the full story message proto if it's not a recipient update
        if !isRecipientUpdate {
            guard let storyMessageProto = outgoingStoryMessage.storyMessageProto(with: messageThread, transaction: transaction) else {
                owsFailDebug("Failed to build sync proto for outgoing story message with timestamp \(outgoingStoryMessage.timestamp)")
                return false
            }
            sentBuilder.setStoryMessage(storyMessageProto)
        }

        guard let storyMessage = StoryMessage.anyFetch(uniqueId: outgoingStoryMessage.storyMessageId, transaction: transaction) else {
            owsFailDebug("Missing story message for sync message with timestamp \(outgoingStoryMessage.timestamp)")
            return false
        }

        guard case .outgoing(let recipientStates) = storyMessage.manifest else {
            owsFailDebug("Unexpected type for story message sync with timestamp \(storyMessage.timestamp)")
            return false
        }

        for (uuid, state) in recipientStates {
            let builder = SSKProtoSyncMessageSentStoryMessageRecipient.builder()
            builder.setDestinationUuid(uuid.uuidString)
            builder.setDistributionListIds(state.contexts)
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
}
