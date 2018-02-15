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

        let recipientReadMap = outgoingMessage.recipientReadMap
        if let readTimestamp = recipientReadMap[recipientId] {
            assert(outgoingMessage.messageState == .sentToService)
            let timestampString = DateUtil.formatPastTimestampRelativeToNow(readTimestamp.uint64Value,
                                                                               isRTL:referenceView.isRTL())
            let shortStatusMessage = timestampString
            let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_READ", comment:"message footer for read messages").rtlSafeAppend(" ", referenceView:referenceView)
                .rtlSafeAppend(timestampString, referenceView:referenceView)
            return (status:.read, shortStatusMessage:shortStatusMessage, longStatusMessage:longStatusMessage)
        }

        let recipientDeliveryMap = outgoingMessage.recipientDeliveryMap
        if let deliveryTimestamp = recipientDeliveryMap[recipientId] {
            assert(outgoingMessage.messageState == .sentToService)
            let timestampString = DateUtil.formatPastTimestampRelativeToNow(deliveryTimestamp.uint64Value,
                                                                            isRTL:referenceView.isRTL())
            let shortStatusMessage = timestampString
            let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                                  comment:"message status for message delivered to their recipient.").rtlSafeAppend(" ", referenceView:referenceView)
                .rtlSafeAppend(timestampString, referenceView:referenceView)
            return (status:.delivered, shortStatusMessage:shortStatusMessage, longStatusMessage:longStatusMessage)
        }

        if outgoingMessage.wasDelivered {
            let statusMessage = NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                                  comment:"message status for message delivered to their recipient.")
            return (status:.delivered, shortStatusMessage:statusMessage, longStatusMessage:statusMessage)
        }

        if outgoingMessage.messageState == .unsent {
            let shortStatusMessage = NSLocalizedString("MESSAGE_STATUS_FAILED_SHORT", comment:"status message for failed messages")
            let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_FAILED", comment:"message footer for failed messages")
            return (status:.failed, shortStatusMessage:shortStatusMessage, longStatusMessage:longStatusMessage)
        } else if outgoingMessage.messageState == .sentToService ||
            outgoingMessage.wasSent(toRecipient:recipientId) {
            let statusMessage =
                NSLocalizedString("MESSAGE_STATUS_SENT",
                                  comment:"message footer for sent messages")
            return (status:.sent, shortStatusMessage:statusMessage, longStatusMessage:statusMessage)
        } else if outgoingMessage.hasAttachments() {
            assert(outgoingMessage.messageState == .attemptingOut)

            let statusMessage = NSLocalizedString("MESSAGE_STATUS_UPLOADING",
                                                  comment:"message footer while attachment is uploading")
            return (status:.uploading, shortStatusMessage:statusMessage, longStatusMessage:statusMessage)
        } else {
            assert(outgoingMessage.messageState == .attemptingOut)

            let statusMessage = NSLocalizedString("MESSAGE_STATUS_SENDING",
                                                  comment:"message status while message is sending.")
            return (status:.sending, shortStatusMessage:statusMessage, longStatusMessage:statusMessage)
        }
    }

    // This method is per-message and "biased towards failure".
    // See comments above.
    public class func statusMessage(outgoingMessage: TSOutgoingMessage,
                                    referenceView: UIView) -> String {

        switch outgoingMessage.messageState {
        case .unsent:
            // Use the "long" version of this message here.
            return NSLocalizedString("MESSAGE_STATUS_FAILED", comment:"message footer for failed messages")
        case .attemptingOut:
            if outgoingMessage.hasAttachments() {
                return NSLocalizedString("MESSAGE_STATUS_UPLOADING",
                                         comment:"message footer while attachment is uploading")
            } else {
                return NSLocalizedString("MESSAGE_STATUS_SENDING",
                                         comment:"message status while message is sending.")
            }
        case .sentToService:
            let recipientReadMap = outgoingMessage.recipientReadMap
            if recipientReadMap.count > 0 {
                return NSLocalizedString("MESSAGE_STATUS_READ", comment:"message footer for read messages")
            }

            let recipientDeliveryMap = outgoingMessage.recipientDeliveryMap
            if recipientDeliveryMap.count > 0 {
                return NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                         comment:"message status for message delivered to their recipient.")
            }

            if outgoingMessage.wasDelivered {
                return NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                         comment:"message status for message delivered to their recipient.")
            }

            return NSLocalizedString("MESSAGE_STATUS_SENT",
                                     comment:"message footer for sent messages")
        default:
            owsFail("Message has unexpected status: \(outgoingMessage.messageState).")
            return NSLocalizedString("MESSAGE_STATUS_SENT",
                                     comment:"message footer for sent messages")
        }
    }

    // This method is per-message and "biased towards failure".
    // See comments above.
    public class func recipientStatus(outgoingMessage: TSOutgoingMessage) -> MessageRecipientStatus {
        switch outgoingMessage.messageState {
        case .unsent:
            return .failed
        case .attemptingOut:
            if outgoingMessage.hasAttachments() {
                return .uploading
            } else {
                return .sending
            }
        case .sentToService:
            let recipientReadMap = outgoingMessage.recipientReadMap
            if recipientReadMap.count > 0 {
                return .read
            }

            let recipientDeliveryMap = outgoingMessage.recipientDeliveryMap
            if recipientDeliveryMap.count > 0 {
                return .delivered
            }

            if outgoingMessage.wasDelivered {
                return .delivered
            }

            return .sent
        default:
            owsFail("Message has unexpected status: \(outgoingMessage.messageState).")

            return .sent
        }
    }
}
