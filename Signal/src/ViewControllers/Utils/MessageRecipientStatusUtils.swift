//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc
public enum MessageReceiptStatus: Int {
    case uploading
    case sending
    case sent
    case delivered
    case read
    case viewed
    case failed
    case skipped
    case pending
}

@objc
public class MessageRecipientStatusUtils: NSObject {
    // MARK: Initializers

    @available(*, unavailable, message: "do not instantiate this class.")
    private override init() {
    }

    // This method is per-recipient.
    @objc
    public class func recipientStatus(
        outgoingMessage: TSOutgoingMessage,
        recipientState: TSOutgoingMessageRecipientState
    ) -> MessageReceiptStatus {
        let (messageReceiptStatus, _, _) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                             recipientState: recipientState)
        return messageReceiptStatus
    }

    // This method is per-recipient.
    @objc
    public class func shortStatusMessage(
        outgoingMessage: TSOutgoingMessage,
        recipientState: TSOutgoingMessageRecipientState
    ) -> String {
        let (_, shortStatusMessage, _) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                         recipientState: recipientState)
        return shortStatusMessage
    }

    // This method is per-recipient.
    @objc
    public class func longStatusMessage(
        outgoingMessage: TSOutgoingMessage,
        recipientState: TSOutgoingMessageRecipientState
    ) -> String {
        let (_, _, longStatusMessage) = recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage,
                                                                        recipientState: recipientState)
        return longStatusMessage
    }

    // This method is per-recipient.
    class func recipientStatusAndStatusMessage(
        outgoingMessage: TSOutgoingMessage,
        recipientState: TSOutgoingMessageRecipientState
    ) -> (status: MessageReceiptStatus, shortStatusMessage: String, longStatusMessage: String) {

        switch recipientState.state {
        case .failed:
            let shortStatusMessage = NSLocalizedString("MESSAGE_STATUS_FAILED_SHORT", comment: "status message for failed messages")
            let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_FAILED", comment: "status message for failed messages")
            return (status: .failed, shortStatusMessage: shortStatusMessage, longStatusMessage: longStatusMessage)
        case .pending:
            let shortStatusMessage = NSLocalizedString("MESSAGE_STATUS_PENDING_SHORT", comment: "Label indicating that a message send was paused.")
            let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_PENDING", comment: "Label indicating that a message send was paused.")
            return (status: .pending, shortStatusMessage: shortStatusMessage, longStatusMessage: longStatusMessage)
        case .sending:
            if outgoingMessage.hasAttachments() {
                assert(outgoingMessage.messageState == .sending)

                let statusMessage = NSLocalizedString("MESSAGE_STATUS_UPLOADING",
                                                      comment: "status message while attachment is uploading")
                return (status: .uploading, shortStatusMessage: statusMessage, longStatusMessage: statusMessage)
            } else {
                assert(outgoingMessage.messageState == .sending)

                let statusMessage = NSLocalizedString("MESSAGE_STATUS_SENDING",
                                                      comment: "message status while message is sending.")
                return (status: .sending, shortStatusMessage: statusMessage, longStatusMessage: statusMessage)
            }
        case .sent:
            if let viewedTimestamp = recipientState.viewedTimestamp {
                let timestampString = DateUtil.formatPastTimestampRelativeToNow(viewedTimestamp.uint64Value)
                let shortStatusMessage = timestampString
                let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_VIEWED", comment: "status message for viewed messages") + " " + timestampString
                return (status: .viewed, shortStatusMessage: shortStatusMessage, longStatusMessage: longStatusMessage)
            }
            if let readTimestamp = recipientState.readTimestamp {
                let timestampString = DateUtil.formatPastTimestampRelativeToNow(readTimestamp.uint64Value)
                let shortStatusMessage = timestampString
                let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_READ", comment: "status message for read messages") + " " + timestampString
                return (status: .read, shortStatusMessage: shortStatusMessage, longStatusMessage: longStatusMessage)
            }
            if let deliveryTimestamp = recipientState.deliveryTimestamp {
                let timestampString = DateUtil.formatPastTimestampRelativeToNow(deliveryTimestamp.uint64Value)
                let shortStatusMessage = timestampString
                let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                                          comment: "message status for message delivered to their recipient.") + " " + timestampString
                return (status: .delivered, shortStatusMessage: shortStatusMessage, longStatusMessage: longStatusMessage)
            }

            let timestampString = DateUtil.formatPastTimestampRelativeToNow(outgoingMessage.timestamp)
            let shortStatusMessage = timestampString
            let longStatusMessage = NSLocalizedString("MESSAGE_STATUS_SENT",
                                                      comment: "status message for sent messages") + " " + timestampString
            return (status: .sent, shortStatusMessage: shortStatusMessage, longStatusMessage: longStatusMessage)
        case .skipped:
            let statusMessage = NSLocalizedString("MESSAGE_STATUS_RECIPIENT_SKIPPED",
                                                  comment: "message status if message delivery to a recipient is skipped. We skip delivering group messages to users who have left the group or unregistered their Signal account.")
            return (status: .skipped, shortStatusMessage: statusMessage, longStatusMessage: statusMessage)
        }
    }

    // This method is per-message.
    internal class func receiptStatusAndMessage(outgoingMessage: TSOutgoingMessage) -> (status: MessageReceiptStatus, message: String) {

        switch outgoingMessage.messageState {
        case .failed:
            // Use the "long" version of this message here.
            return (.failed, NSLocalizedString("MESSAGE_STATUS_FAILED", comment: "status message for failed messages"))
        case .pending:
            return (.pending, NSLocalizedString("MESSAGE_STATUS_PENDING", comment: "Label indicating that a message send was paused."))
        case .sending:
            if outgoingMessage.hasAttachments() {
                return (.uploading, NSLocalizedString("MESSAGE_STATUS_UPLOADING",
                                         comment: "status message while attachment is uploading"))
            } else {
                return (.sending, NSLocalizedString("MESSAGE_STATUS_SENDING",
                                         comment: "message status while message is sending."))
            }
        case .sent:
            if outgoingMessage.viewedRecipientAddresses().count > 0 {
                return (.viewed, NSLocalizedString("MESSAGE_STATUS_VIEWED", comment: "status message for viewed messages"))
            }
            if outgoingMessage.readRecipientAddresses().count > 0 {
                return (.read, NSLocalizedString("MESSAGE_STATUS_READ", comment: "status message for read messages"))
            }
            if outgoingMessage.wasDeliveredToAnyRecipient {
                return (.delivered, NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                         comment: "message status for message delivered to their recipient."))
            }
            return (.sent, NSLocalizedString("MESSAGE_STATUS_SENT",
                                     comment: "status message for sent messages"))
        default:
            owsFailDebug("Message has unexpected status: \(outgoingMessage.messageState).")
            return (.sent, NSLocalizedString("MESSAGE_STATUS_SENT",
                                     comment: "status message for sent messages"))
        }
    }

    // This method is per-message.
    @objc
    public class func receiptMessage(outgoingMessage: TSOutgoingMessage) -> String {
        let (_, message ) = receiptStatusAndMessage(outgoingMessage: outgoingMessage)
        return message
    }

    // This method is per-message.
    @objc
    public class func recipientStatus(outgoingMessage: TSOutgoingMessage) -> MessageReceiptStatus {
        let (status, _ ) = receiptStatusAndMessage(outgoingMessage: outgoingMessage)
        return status
    }

    @objc
    public class func description(forMessageReceiptStatus value: MessageReceiptStatus) -> String {
        switch value {
        case .read:
            return "read"
        case .viewed:
            return "viewed"
        case .uploading:
            return "uploading"
        case .delivered:
            return "delivered"
        case .sent:
            return "sent"
        case .sending:
            return "sending"
        case .failed:
            return "failed"
        case .skipped:
            return "skipped"
        case .pending:
            return "pending"
        }
    }
}
