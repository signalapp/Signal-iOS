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

class MessageRecipientStatusUtils: NSObject {
    // MARK: Initializers

    @available(*, unavailable, message:"do not instantiate this class.")
    private override init() {
    }

    public class func recipientStatus(outgoingMessage: TSOutgoingMessage,
                                      recipientId: String,
                                      referenceView: UIView) -> MessageRecipientStatus {
        let (messageRecipientStatus, _) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                                     recipientId: recipientId,
                                                                                     referenceView: referenceView)
        return messageRecipientStatus
    }

    public class func statusMessage(outgoingMessage: TSOutgoingMessage,
                                      recipientId: String,
                                      referenceView: UIView) -> String {
        let (_, statusMessage) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                                     recipientId: recipientId,
                                                                                     referenceView: referenceView)
        return statusMessage
    }

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

    public class func statusMessage(outgoingMessage: TSOutgoingMessage,
                                    referenceView: UIView) -> String {

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

        if outgoingMessage.messageState == .unsent {
            return NSLocalizedString("MESSAGE_STATUS_FAILED", comment:"message footer for failed messages")
        } else if outgoingMessage.messageState == .sentToService {
            return NSLocalizedString("MESSAGE_STATUS_SENT",
                                  comment:"message footer for sent messages")
        } else if outgoingMessage.hasAttachments() {
            assert(outgoingMessage.messageState == .attemptingOut)

            return NSLocalizedString("MESSAGE_STATUS_UPLOADING",
                                                  comment:"message footer while attachment is uploading")
        } else {
            assert(outgoingMessage.messageState == .attemptingOut)

            return NSLocalizedString("MESSAGE_STATUS_SENDING",
                                                  comment:"message status while message is sending.")
        }
    }

    public class func recipientStatus(outgoingMessage: TSOutgoingMessage) -> MessageRecipientStatus {
        let recipientReadMap = outgoingMessage.recipientReadMap
        if recipientReadMap.count > 0 {
            assert(outgoingMessage.messageState == .sentToService)
            return .read
        }

        let recipientDeliveryMap = outgoingMessage.recipientDeliveryMap
        if recipientDeliveryMap.count > 0 {
            return .delivered
        }

        if outgoingMessage.wasDelivered {
            return .delivered
        }

        if outgoingMessage.messageState == .unsent {
            return .failed
        } else if outgoingMessage.messageState == .sentToService {
            return .sent
        } else if outgoingMessage.hasAttachments() {
            assert(outgoingMessage.messageState == .attemptingOut)
            return .uploading
        } else {
            assert(outgoingMessage.messageState == .attemptingOut)
            return .sending
        }
    }
}
