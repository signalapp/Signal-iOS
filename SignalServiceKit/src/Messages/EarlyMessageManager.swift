//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSEarlyMessageManager)
public class EarlyMessageManager: NSObject {
    private struct MessageIdentifier: Hashable {
        let timestamp: UInt64
        let author: SignalServiceAddress
    }

    private struct EarlyEnvelope {
        let envelope: SSKProtoEnvelope
        let plainTextData: Data?
        let wasReceivedByUD: Bool
    }

    private struct EarlyReceipt {
        let type: SSKProtoReceiptMessageType
        let sender: SignalServiceAddress
        let timestamp: UInt64
    }

    private static let serialQueue = DispatchQueue(label: "EarlyMessageManager")
    private static var pendingEnvelopes = [MessageIdentifier: [EarlyEnvelope]]()
    private static var pendingReceipts =  [MessageIdentifier: [EarlyReceipt]]()

    @objc
    public static func recordEarlyEnvelope(
        _ envelope: SSKProtoEnvelope,
        plainTextData: Data?,
        wasReceivedByUD: Bool,
        associatedMessageTimestamp: UInt64,
        associatedMessageAuthor: SignalServiceAddress
    ) {
        let identifier = MessageIdentifier(timestamp: associatedMessageTimestamp, author: associatedMessageAuthor)
        serialQueue.sync {
            var envelopes = pendingEnvelopes[identifier] ?? []
            envelopes.append(EarlyEnvelope(envelope: envelope, plainTextData: plainTextData, wasReceivedByUD: wasReceivedByUD))
            pendingEnvelopes[identifier] = envelopes
        }
    }

    @objc
    public static func recordEarlyReceiptForOutgoingMessage(
        type: SSKProtoReceiptMessageType,
        sender: SignalServiceAddress,
        timestamp: UInt64,
        associatedMessageTimestamp: UInt64
    ) {
        guard let localAddress = TSAccountManager.localAddress else {
            return owsFailDebug("missing local address")
        }

        recordEarlyReceipt(
            type: type,
            sender: sender,
            timestamp: timestamp,
            associatedMessageTimestamp: associatedMessageTimestamp,
            associatedMessageAuthor: localAddress
        )
    }

    @objc
    public static func recordEarlyReadReceiptFromLinkedDevice(
        timestamp: UInt64,
        associatedMessageTimestamp: UInt64,
        associatedMessageAuthor: SignalServiceAddress
    ) {
        guard let localAddress = TSAccountManager.localAddress else {
            return owsFailDebug("missing local address")
        }

        recordEarlyReceipt(
            type: .read,
            sender: localAddress,
            timestamp: timestamp,
            associatedMessageTimestamp: associatedMessageTimestamp,
            associatedMessageAuthor: associatedMessageAuthor
        )
    }

    private static func recordEarlyReceipt(
        type: SSKProtoReceiptMessageType,
        sender: SignalServiceAddress,
        timestamp: UInt64,
        associatedMessageTimestamp: UInt64,
        associatedMessageAuthor: SignalServiceAddress
    ) {
        let identifier = MessageIdentifier(timestamp: associatedMessageTimestamp, author: associatedMessageAuthor)
        serialQueue.sync {
            var receipts = pendingReceipts[identifier] ?? []
            receipts.append(EarlyReceipt(type: type, sender: sender, timestamp: timestamp))
            pendingReceipts[identifier] = receipts
        }
    }

    @objc
    public static func applyPendingMessages(for message: TSMessage, transaction: SDSAnyWriteTransaction) {
        var earlyReceipts: [EarlyReceipt]?
        var earlyEnvelopes: [EarlyEnvelope]?

        let identifier: MessageIdentifier
        if let message = message as? TSOutgoingMessage {
            guard let localAddress = TSAccountManager.localAddress else {
                return owsFailDebug("missing local address")
            }
            identifier = MessageIdentifier(timestamp: message.timestamp, author: localAddress)
        } else if let message = message as? TSIncomingMessage {
            identifier = MessageIdentifier(timestamp: message.timestamp, author: message.authorAddress)
        } else {
            // We only support early envelopes for incoming + outgoing message types, for now.
            return owsFailDebug("attempted to apply pending messages for unsupported message type \(message.interactionType())")
        }

        serialQueue.sync {
            earlyReceipts = pendingReceipts[identifier]
            pendingReceipts[identifier] = nil

            earlyEnvelopes = pendingEnvelopes[identifier]
            pendingEnvelopes[identifier] = nil
        }

        // Apply any early receipts for this message
        for earlyReceipt in earlyReceipts ?? [] {
            switch earlyReceipt.type {
            case .read:
                if let message = message as? TSOutgoingMessage {
                    message.update(
                        withReadRecipient: earlyReceipt.sender,
                        readTimestamp: earlyReceipt.timestamp,
                        transaction: transaction
                    )
                } else if let message = message as? TSIncomingMessage {
                    OWSReadReceiptManager.shared().markAsRead(
                        onLinkedDevice: message,
                        thread: message.thread(transaction: transaction),
                        readTimestamp: earlyReceipt.timestamp,
                        transaction: transaction
                    )
                } else {
                    owsFailDebug("Unexpected message type for early read receipt.")
                }
            case .delivery:
                if let message = message as? TSOutgoingMessage {
                    message.update(
                        withDeliveredRecipient: earlyReceipt.sender,
                        deliveryTimestamp: NSNumber(value: earlyReceipt.timestamp),
                        transaction: transaction
                    )
                } else {
                    owsFailDebug("Unexpected message type for early delivery receipt.")
                }
            }
        }

        // Re-process any early envelopes associated with this message
        for earlyEnvelope in earlyEnvelopes ?? [] {
            SSKEnvironment.shared.messageManager.processEnvelope(
                earlyEnvelope.envelope,
                plaintextData: earlyEnvelope.plainTextData,
                wasReceivedByUD: earlyEnvelope.wasReceivedByUD,
                transaction: transaction
            )
        }
    }
}
