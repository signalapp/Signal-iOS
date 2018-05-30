//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc public enum MessageReceiptStatus: Int {
    case uploading
    case sending
    case sent
    case delivered
    case read
    case failed
    case skipped
}

@objc
public class MessageRecipientStatusUtils: NSObject {
    // MARK: Initializers

    @available(*, unavailable, message:"do not instantiate this class.")
    private override init() {
    }

    // This method is per-recipient.
    @objc
    public class func recipientStatus(outgoingMessage: TSOutgoingMessage,
            recipientState: TSOutgoingMessageRecipientState,
                                      referenceView: UIView) -> MessageReceiptStatus {
        let (messageReceiptStatus, _, _) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                             recipientState: recipientState,
                                                                                     referenceView: referenceView)
        return messageReceiptStatus
    }

    // This method is per-recipient.
    @objc
    public class func shortStatusMessage(outgoingMessage: TSOutgoingMessage,
        recipientState: TSOutgoingMessageRecipientState,
                                    referenceView: UIView) -> String {
        let (_, shortStatusMessage, _) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                         recipientState: recipientState,
                                                                 referenceView: referenceView)
        return shortStatusMessage
    }

    // This method is per-recipient.
    @objc
    public class func longStatusMessage(outgoingMessage: TSOutgoingMessage,
        recipientState: TSOutgoingMessageRecipientState,
                                    referenceView: UIView) -> String {
        let (_, _, longStatusMessage) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                        recipientState: recipientState,
                                                                 referenceView: referenceView)
        return longStatusMessage
    }

    // This method is per-recipient.
    class func recipientStatusAndStatusMessage(outgoingMessage: TSOutgoingMessage,
        recipientState: TSOutgoingMessageRecipientState,
                                                      referenceView: UIView) -> (status: MessageReceiptStatus, shortStatusMessage: String, longStatusMessage: String) {

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

    // This method is per-message.
    internal class func receiptStatusAndMessage(outgoingMessage: TSOutgoingMessage,
                                      referenceView: UIView) -> (status: MessageReceiptStatus, message: String) {

        switch outgoingMessage.messageState {
        case .failed:
            // Use the "long" version of this message here.
            return (.failed, NSLocalizedString("MESSAGE_STATUS_FAILED", comment: "message footer for failed messages"))
        case .sending:
            if outgoingMessage.hasAttachments() {
                return (.uploading, NSLocalizedString("MESSAGE_STATUS_UPLOADING",
                                         comment: "message footer while attachment is uploading"))
            } else {
                return (.sending, NSLocalizedString("MESSAGE_STATUS_SENDING",
                                         comment: "message status while message is sending."))
            }
        case .sent:
            if outgoingMessage.readRecipientIds().count > 0 {
                return (.read, NSLocalizedString("MESSAGE_STATUS_READ", comment: "message footer for read messages"))
            }
            if outgoingMessage.wasDeliveredToAnyRecipient {
                return (.delivered, NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                         comment: "message status for message delivered to their recipient."))
            }
            return (.sent, NSLocalizedString("MESSAGE_STATUS_SENT",
                                     comment: "message footer for sent messages"))
        default:
            owsFail("\(self.logTag) Message has unexpected status: \(outgoingMessage.messageState).")
            return (.sent, NSLocalizedString("MESSAGE_STATUS_SENT",
                                     comment: "message footer for sent messages"))
        }
    }

    // This method is per-message.
    @objc
    public class func receiptMessage(outgoingMessage: TSOutgoingMessage,
                                    referenceView: UIView) -> String {
        let (_, message ) = receiptStatusAndMessage(outgoingMessage: outgoingMessage,
                                                              referenceView: referenceView)
        return message
    }

    // This method is per-message.
    @objc
    public class func recipientStatus(outgoingMessage: TSOutgoingMessage, referenceView: UIView) -> MessageReceiptStatus {
        let (status, _ ) = receiptStatusAndMessage(outgoingMessage: outgoingMessage,
                                                              referenceView: referenceView)
        return status
    }
}
