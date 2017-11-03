//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

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
        let (messageRecipientStatus, _) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                                     recipientId: recipientId,
                                                                                     referenceView: referenceView)
        return messageRecipientStatus
    }

    // This method is per-recipient and "biased towards success".
    // See comments above.
    public class func statusMessage(outgoingMessage: TSOutgoingMessage,
                                      recipientId: String,
                                      referenceView: UIView) -> String {
        let (_, statusMessage) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                                     recipientId: recipientId,
                                                                                     referenceView: referenceView)
        return statusMessage
    }

    // This method is per-recipient and "biased towards success".  
    // See comments above.
    public class func recipientStatusAndStatusMessage(outgoingMessage: TSOutgoingMessage,
                                                      recipientId: String,
                                                      referenceView: UIView) -> (MessageRecipientStatus, String) {
        // Legacy messages don't have "recipient read" state or "per-recipient delivery" state,
        // so we fall back to `TSOutgoingMessageState` which is not per-recipient and therefore
        // might be misleading.

        let recipientReadMap = outgoingMessage.recipientReadMap
        if let readTimestamp = recipientReadMap[recipientId] {
            assert(outgoingMessage.messageState == .sentToService)
            let statusMessage = NSLocalizedString("MESSAGE_STATUS_READ", comment:"message footer for read messages").rtlSafeAppend(" ", referenceView:referenceView)
                .rtlSafeAppend(
                    DateUtil.formatPastTimestampRelativeToNow(readTimestamp.uint64Value), referenceView:referenceView)
            return (.read, statusMessage)
        }

        let recipientDeliveryMap = outgoingMessage.recipientDeliveryMap
        if let deliveryTimestamp = recipientDeliveryMap[recipientId] {
            assert(outgoingMessage.messageState == .sentToService)
            let statusMessage = NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                                  comment:"message status for message delivered to their recipient.").rtlSafeAppend(" ", referenceView:referenceView)
                .rtlSafeAppend(
                    DateUtil.formatPastTimestampRelativeToNow(deliveryTimestamp.uint64Value), referenceView:referenceView)
            return (.delivered, statusMessage)
        }

        if outgoingMessage.wasDelivered {
            let statusMessage = NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                                  comment:"message status for message delivered to their recipient.")
            return (.delivered, statusMessage)
        }

        if outgoingMessage.messageState == .unsent {
            let statusMessage = NSLocalizedString("MESSAGE_STATUS_FAILED", comment:"message footer for failed messages")
            return (.failed, statusMessage)
        } else if outgoingMessage.messageState == .sentToService ||
            outgoingMessage.wasSent(toRecipient:recipientId) {
            let statusMessage =
                NSLocalizedString("MESSAGE_STATUS_SENT",
                                  comment:"message footer for sent messages")
            return (.sent, statusMessage)
        } else if outgoingMessage.hasAttachments() {
            assert(outgoingMessage.messageState == .attemptingOut)

            let statusMessage = NSLocalizedString("MESSAGE_STATUS_UPLOADING",
                                                  comment:"message footer while attachment is uploading")
            return (.uploading, statusMessage)
        } else {
            assert(outgoingMessage.messageState == .attemptingOut)

            let statusMessage = NSLocalizedString("MESSAGE_STATUS_SENDING",
                                                  comment:"message status while message is sending.")
            return (.sending, statusMessage)
        }
    }

    // This method is per-message and "biased towards failure".
    // See comments above.
    public class func statusMessage(outgoingMessage: TSOutgoingMessage,
                                    referenceView: UIView) -> String {

        if outgoingMessage.messageState == .unsent {
            return NSLocalizedString("MESSAGE_STATUS_FAILED", comment:"message footer for failed messages")
        } else if outgoingMessage.messageState == .attemptingOut {
            if outgoingMessage.hasAttachments() {
                assert(outgoingMessage.messageState == .attemptingOut)

                return NSLocalizedString("MESSAGE_STATUS_UPLOADING",
                                         comment:"message footer while attachment is uploading")
            } else {
                assert(outgoingMessage.messageState == .attemptingOut)

                return NSLocalizedString("MESSAGE_STATUS_SENDING",
                                         comment:"message status while message is sending.")
            }
        }

        let recipientReadMap = outgoingMessage.recipientReadMap
        if recipientReadMap.count > 0 {
            assert(outgoingMessage.messageState == .sentToService)
            return NSLocalizedString("MESSAGE_STATUS_READ", comment:"message footer for read messages")
        }

        let recipientDeliveryMap = outgoingMessage.recipientDeliveryMap
        if recipientDeliveryMap.count > 0 {
            assert(outgoingMessage.messageState == .sentToService)
            return NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                                  comment:"message status for message delivered to their recipient.")
        }

        if outgoingMessage.wasDelivered {
            return NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                                  comment:"message status for message delivered to their recipient.")
        }

        return NSLocalizedString("MESSAGE_STATUS_SENT",
                                 comment:"message footer for sent messages")
    }

    // This method is per-message and "biased towards failure".
    // See comments above.
    public class func recipientStatus(outgoingMessage: TSOutgoingMessage) -> MessageRecipientStatus {
        if outgoingMessage.messageState == .unsent {
            return .failed
        } else if outgoingMessage.messageState == .attemptingOut {
            if outgoingMessage.hasAttachments() {
                assert(outgoingMessage.messageState == .attemptingOut)
                return .uploading
            } else {
                assert(outgoingMessage.messageState == .attemptingOut)
                return .sending
            }
        }

        assert(outgoingMessage.messageState == .sentToService)

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
    }
}
