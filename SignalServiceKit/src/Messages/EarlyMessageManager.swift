//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class EarlyMessageManager: NSObject {
    private struct MessageIdentifier: Hashable {
        let timestamp: UInt64
        let author: SignalServiceAddress
    }

    private struct EarlyEnvelope {
        let envelope: SSKProtoEnvelope
        let plainTextData: Data?
        let wasReceivedByUD: Bool
        let serverDeliveryTimestamp: UInt64
    }

    private enum EarlyReceipt {
        case outgoingMessageRead(sender: SignalServiceAddress, timestamp: UInt64)
        case outgoingMessageDelivered(sender: SignalServiceAddress, timestamp: UInt64)
        case messageReadOnLinkedDevice(timestamp: UInt64)

        init(receiptType: SSKProtoReceiptMessageType, sender: SignalServiceAddress, timestamp: UInt64) {
            switch receiptType {
            case .delivery: self = .outgoingMessageDelivered(sender: sender, timestamp: timestamp)
            case .read: self = .outgoingMessageRead(sender: sender, timestamp: timestamp)
            }
        }
    }

    private static let maxQueuedPerMessage = 100
    private static let maxQueuedMessages = 100
    private static let maxEarlyEnvelopeSize = 1024

    private let serialQueue = DispatchQueue(label: "EarlyMessageManager")
    private var pendingEnvelopes = OrderedDictionary<MessageIdentifier, [EarlyEnvelope]>()
    private var pendingReceipts =  OrderedDictionary<MessageIdentifier, [EarlyReceipt]>()

    public override init() {
        super.init()

        SwiftSingletons.register(self)

        // Listen for memory warnings to evacuate the caches
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc
    func didReceiveMemoryWarning() {
        Logger.error("Dropping all early messages due to memory warning.")
        serialQueue.sync {
            pendingEnvelopes = OrderedDictionary()
            pendingReceipts = OrderedDictionary()
        }
    }

    @objc
    public func recordEarlyEnvelope(
        _ envelope: SSKProtoEnvelope,
        plainTextData: Data?,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        associatedMessageTimestamp: UInt64,
        associatedMessageAuthor: SignalServiceAddress
    ) {
        guard plainTextData?.count ?? 0 <= Self.maxEarlyEnvelopeSize else {
            return owsFailDebug("unexpectedly tried to record an excessively large early envelope")
        }

        let identifier = MessageIdentifier(timestamp: associatedMessageTimestamp, author: associatedMessageAuthor)
        serialQueue.sync {
            var envelopes = pendingEnvelopes[identifier] ?? []

            while envelopes.count >= Self.maxQueuedPerMessage, let droppedEarlyEnvelope = envelopes.first {
                envelopes.remove(at: 0)
                owsFailDebug("Dropping early envelope \(droppedEarlyEnvelope.envelope.timestamp) for message \(identifier) due to excessive early envelopes.")
            }

            envelopes.append(EarlyEnvelope(
                envelope: envelope,
                plainTextData: plainTextData,
                wasReceivedByUD: wasReceivedByUD,
                serverDeliveryTimestamp: serverDeliveryTimestamp
            ))
            pendingEnvelopes[identifier] = envelopes

            while pendingEnvelopes.count >= Self.maxQueuedMessages, let droppedEarlyIdentifier = pendingEnvelopes.orderedKeys.first {
                pendingEnvelopes.remove(key: droppedEarlyIdentifier)
                owsFailDebug("Dropping all early envelopes for message \(droppedEarlyIdentifier) due to excessive early messages.")
            }
        }
    }

    @objc
    public func recordEarlyReceiptForOutgoingMessage(
        type: SSKProtoReceiptMessageType,
        sender: SignalServiceAddress,
        timestamp: UInt64,
        associatedMessageTimestamp: UInt64
    ) {
        guard let localAddress = TSAccountManager.localAddress else {
            return owsFailDebug("missing local address")
        }

        recordEarlyReceipt(
            .init(receiptType: type, sender: sender, timestamp: timestamp),
            associatedMessageTimestamp: associatedMessageTimestamp,
            associatedMessageAuthor: localAddress
        )
    }

    @objc
    public func recordEarlyReadReceiptFromLinkedDevice(
        timestamp: UInt64,
        associatedMessageTimestamp: UInt64,
        associatedMessageAuthor: SignalServiceAddress
    ) {
        recordEarlyReceipt(
            .messageReadOnLinkedDevice(timestamp: timestamp),
            associatedMessageTimestamp: associatedMessageTimestamp,
            associatedMessageAuthor: associatedMessageAuthor
        )
    }

    private func recordEarlyReceipt(
        _ earlyReceipt: EarlyReceipt,
        associatedMessageTimestamp: UInt64,
        associatedMessageAuthor: SignalServiceAddress
    ) {
        let identifier = MessageIdentifier(timestamp: associatedMessageTimestamp, author: associatedMessageAuthor)
        serialQueue.sync {
            var receipts = pendingReceipts[identifier] ?? []

            while receipts.count >= Self.maxQueuedPerMessage, let droppedEarlyReceipt = receipts.first {
                receipts.remove(at: 0)
                owsFailDebug("Dropping early receipt \(droppedEarlyReceipt) for message \(identifier) due to excessive early receipts.")
            }

            receipts.append(earlyReceipt)
            pendingReceipts[identifier] = receipts

            while pendingReceipts.count >= Self.maxQueuedMessages, let droppedEarlyIdentifier = pendingReceipts.orderedKeys.first {
                pendingReceipts.remove(key: droppedEarlyIdentifier)
                owsFailDebug("Dropping all early envelopes for message \(droppedEarlyIdentifier) due to excessive early messages.")
            }
        }
    }

    @objc
    public func applyPendingMessages(for message: TSMessage, transaction: SDSAnyWriteTransaction) {
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
            switch earlyReceipt {
            case .outgoingMessageRead(let sender, let timestamp):
                guard let message = message as? TSOutgoingMessage else {
                    owsFailDebug("Unexpected message type for early read receipt for outgoing message.")
                    continue
                }
                message.update(
                    withReadRecipient: sender,
                    readTimestamp: timestamp,
                    transaction: transaction
                )
            case .outgoingMessageDelivered(let sender, let timestamp):
                guard let message = message as? TSOutgoingMessage else {
                    owsFailDebug("Unexpected message type for early delivery receipt for outgoing message.")
                    continue
                }
                message.update(
                    withDeliveredRecipient: sender,
                    deliveryTimestamp: NSNumber(value: timestamp),
                    transaction: transaction
                )
            case .messageReadOnLinkedDevice(let timestamp):
                OWSReadReceiptManager.shared().markAsRead(
                    onLinkedDevice: message,
                    thread: message.thread(transaction: transaction),
                    readTimestamp: timestamp,
                    transaction: transaction
                )
            }
        }

        // Re-process any early envelopes associated with this message
        for earlyEnvelope in earlyEnvelopes ?? [] {
            SSKEnvironment.shared.messageManager.processEnvelope(
                earlyEnvelope.envelope,
                plaintextData: earlyEnvelope.plainTextData,
                wasReceivedByUD: earlyEnvelope.wasReceivedByUD,
                serverDeliveryTimestamp: earlyEnvelope.serverDeliveryTimestamp,
                transaction: transaction
            )
        }
    }
}

extension OrderedDictionary {
    subscript(_ key: KeyType) -> ValueType? {
        set {
            if hasValue(forKey: key) { remove(key: key) }
            guard let newValue = newValue else { return }
            append(key: key, value: newValue)
        }
        get { value(forKey: key) }
    }
}
