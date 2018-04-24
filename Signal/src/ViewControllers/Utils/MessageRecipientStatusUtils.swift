//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc enum MessageRecipientStatus: Int {
    case uploading
    case sending
    case sent
    case delivered
    case read
    case failed
    case skipped
}

// Our per-recipient status messages are "biased towards success"
// and reflect the most successful known state for that recipient.
//
// Our per-message status messages are "biased towards failure"
// and reflect the least successful known state for that message.
//
// Why?
//
// When showing the per-recipient status, we want to show the message
// as "read" even if delivery failed to another recipient of the same
// message.
//
// When showing the per-message status, we want to show the message
// as "failed" if delivery failed to any recipient, even if another 
// receipient has read the message.
// 
// Note also that for legacy reasons we have redundant and possibly
// conflicting state.  Examples:
//
// * We could have an entry in the recipientReadMap for a message
//   that has no entries in its recipientDeliveryMap.
// * We could have an entry in the recipientReadMap or recipientDeliveryMap
//   for a message whose status is "attempting out" or "unsent".
// * We could have a message whose wasDelivered property is false but
//   which has entries in its recipientDeliveryMap or recipientReadMap.
// * Etc.
//
// To resolve this ambiguity, we apply a "bias" towards success or
// failure.
class MessageRecipientStatusUtils: NSObject {
    // MARK: Initializers

    @available(*, unavailable, message:"do not instantiate this class.")
    private override init() {
    }

    // This method is per-recipient and "biased towards success".
    // See comments above.
    public class func recipientStatus(outgoingMessage: TSOutgoingMessage,
                                      recipientId: String,
                                      referenceView: UIView) -> MessageRecipientStatus {
        let (messageRecipientStatus, _, _) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                                     recipientId: recipientId,
                                                                                     referenceView: referenceView)
        return messageRecipientStatus
    }

    // This method is per-recipient and "biased towards success".
    // See comments above.
    public class func shortStatusMessage(outgoingMessage: TSOutgoingMessage,
                                    recipientId: String,
                                    referenceView: UIView) -> String {
        let (_, shortStatusMessage, _) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                 recipientId: recipientId,
                                                                 referenceView: referenceView)
        return shortStatusMessage
    }

    // This method is per-recipient and "biased towards success".
    // See comments above.
    public class func longStatusMessage(outgoingMessage: TSOutgoingMessage,
                                    recipientId: String,
                                    referenceView: UIView) -> String {
        let (_, _, longStatusMessage) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                 recipientId: recipientId,
                                                                 referenceView: referenceView)
        return longStatusMessage
    }

    // This method is per-recipient and "biased towards success".  
    // See comments above.
    public class func recipientStatusAndStatusMessage(outgoingMessage: TSOutgoingMessage,
                                                      recipientId: String,
                                                      referenceView: UIView) -> (status: MessageRecipientStatus, shortStatusMessage: String, longStatusMessage: String) {
        // Legacy messages don't have "recipient read" state or "per-recipient delivery" state,
        // so we fall back to `TSOutgoingMessageState` which is not per-recipient and therefore
        // might be misleading.

        guard let recipientState = outgoingMessage.recipientState(forRecipientId: recipientId) else {
            owsFail("\(self.logTag) no message status for recipient: \(recipientId).")
            let shortStatusMessage = NSLocalizedString("MESSAGE_STATUS_FAILED_SHORT", comment: "status message for failed messages")
            let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_FAILED", comment: "message footer for failed messages")
            return (status:.failed, shortStatusMessage:shortStatusMessage, longStatusMessage:longStatusMessage)
        }

        switch recipientState.state {
        case .failed:
            let shortStatusMessage = NSLocalizedString("MESSAGE_STATUS_FAILED_SHORT", comment: "status message for failed messages")
            let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_FAILED", comment: "message footer for failed messages")
            return (status:.failed, shortStatusMessage:shortStatusMessage, longStatusMessage:longStatusMessage)
        case .sending:
            if outgoingMessage.hasAttachments() {
                assert(outgoingMessage.messageState == .sending)

                let statusMessage = NSLocalizedString("MESSAGE_STATUS_UPLOADING",
                                                      comment: "message footer while attachment is uploading")
                return (status:.uploading, shortStatusMessage:statusMessage, longStatusMessage:statusMessage)
            } else {
                assert(outgoingMessage.messageState == .sending)

                let statusMessage = NSLocalizedString("MESSAGE_STATUS_SENDING",
                                                      comment: "message status while message is sending.")
                return (status:.sending, shortStatusMessage:statusMessage, longStatusMessage:statusMessage)
            }
        case .sent:
            if let readTimestamp = recipientState.readTimestamp {
                let timestampString = DateUtil.formatPastTimestampRelativeToNow(readTimestamp.uint64Value,
                                                                                isRTL: referenceView.isRTL())
                let shortStatusMessage = timestampString
                let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_READ", comment: "message footer for read messages").rtlSafeAppend(" ", referenceView: referenceView)
                    .rtlSafeAppend(timestampString, referenceView: referenceView)
                return (status:.read, shortStatusMessage:shortStatusMessage, longStatusMessage:longStatusMessage)
            }
            if let deliveryTimestamp = recipientState.deliveryTimestamp {
                let timestampString = DateUtil.formatPastTimestampRelativeToNow(deliveryTimestamp.uint64Value,
                                                                                isRTL: referenceView.isRTL())
                let shortStatusMessage = timestampString
                let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                                          comment: "message status for message delivered to their recipient.").rtlSafeAppend(" ", referenceView: referenceView)
                    .rtlSafeAppend(timestampString, referenceView: referenceView)
                return (status:.delivered, shortStatusMessage:shortStatusMessage, longStatusMessage:longStatusMessage)
            }
            let statusMessage =
                NSLocalizedString("MESSAGE_STATUS_SENT",
                                  comment: "message footer for sent messages")
            return (status:.sent, shortStatusMessage:statusMessage, longStatusMessage:statusMessage)
        case .skipped:
            let statusMessage = NSLocalizedString("MESSAGE_STATUS_RECIPIENT_SKIPPED",
                                                  comment: "message status if message delivery to a recipient is skipped. We skip delivering group messages to users who have left the group or deactivated their Signal account.")
            return (status:.skipped, shortStatusMessage:statusMessage, longStatusMessage:statusMessage)
        }
    }

    // This method is per-message and "biased towards failure".
    // See comments above.
    public class func statusMessage(outgoingMessage: TSOutgoingMessage,
                                    referenceView: UIView) -> String {

        switch outgoingMessage.messageState {
        case .failed:
            // Use the "long" version of this message here.
            return NSLocalizedString("MESSAGE_STATUS_FAILED", comment: "message footer for failed messages")
        case .sending:
            if outgoingMessage.hasAttachments() {
                return NSLocalizedString("MESSAGE_STATUS_UPLOADING",
                                         comment: "message footer while attachment is uploading")
            } else {
                return NSLocalizedString("MESSAGE_STATUS_SENDING",
                                         comment: "message status while message is sending.")
            }
        case .sent:
            if outgoingMessage.readRecipientIds().count > 0 {
                return NSLocalizedString("MESSAGE_STATUS_READ", comment: "message footer for read messages")
            }
            if outgoingMessage.deliveredRecipientIds().count > 0 {
                return NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                         comment: "message status for message delivered to their recipient.")
            }
            return NSLocalizedString("MESSAGE_STATUS_SENT",
                                     comment: "message footer for sent messages")
        default:
            owsFail("\(self.logTag) Message has unexpected status: \(outgoingMessage.messageState).")
            return NSLocalizedString("MESSAGE_STATUS_SENT",
                                     comment: "message footer for sent messages")
        }
    }

    // This method is per-message and "biased towards failure".
    // See comments above.
    public class func recipientStatus(outgoingMessage: TSOutgoingMessage) -> MessageRecipientStatus {
        switch outgoingMessage.messageState {
        case .failed:
            return .failed
        case .sending:
            if outgoingMessage.hasAttachments() {
                return .uploading
            } else {
                return .sending
            }
        case .sent:
            if outgoingMessage.readRecipientIds().count > 0 {
                return .read
            }
            if outgoingMessage.deliveredRecipientIds().count > 0 {
                return .delivered
            }

            return .sent
        default:
            owsFail("\(self.logTag) Message has unexpected status: \(outgoingMessage.messageState).")

            return .sent
        }
    }
}
