//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class EarlyMessageManager: NSObject {
    private struct MessageIdentifier: Hashable, Codable {
        let timestamp: UInt64
        let author: SignalServiceAddress

        var rawValue: String {
            guard let authorUuid = author.uuidString else {
                owsFail("Unexpectedly missing author uuid \(author)")
            }
            return "\(authorUuid).\(timestamp)"
        }
    }

    private struct EarlyEnvelope: Codable {
        let envelope: SSKProtoEnvelope
        let plainTextData: Data?
        let wasReceivedByUD: Bool
        let serverDeliveryTimestamp: UInt64
    }

    private enum EarlyReceipt: Codable {
        private enum CodingKeys: String, CodingKey {
            case type, sender, timestamp
        }
        private enum EncodedType: String, Codable {
            case outgoingMessageRead
            case outgoingMessageDelivered
            case outgoingMessageViewed
            case messageReadOnLinkedDevice
            case messageViewedOnLinkedDevice
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let type = try container.decode(EncodedType.self, forKey: .type)
            let sender = try container.decodeIfPresent(SignalServiceAddress.self, forKey: .sender)
            let timestamp = try container.decode(UInt64.self, forKey: .timestamp)

            switch type {
            case .outgoingMessageRead:
                guard let sender = sender else {
                    throw OWSAssertionError("Missing sender")
                }
                self = .outgoingMessageRead(sender: sender, timestamp: timestamp)
            case .outgoingMessageDelivered:
                guard let sender = sender else {
                    throw OWSAssertionError("Missing sender")
                }
                self = .outgoingMessageDelivered(sender: sender, timestamp: timestamp)
            case .outgoingMessageViewed:
                guard let sender = sender else {
                    throw OWSAssertionError("Missing sender")
                }
                self = .outgoingMessageViewed(sender: sender, timestamp: timestamp)
            case .messageReadOnLinkedDevice:
                self = .messageReadOnLinkedDevice(timestamp: timestamp)
            case .messageViewedOnLinkedDevice:
                self = .messageViewedOnLinkedDevice(timestamp: timestamp)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .outgoingMessageRead(let sender, let timestamp):
                try container.encode(EncodedType.outgoingMessageRead, forKey: .type)
                try container.encode(sender, forKey: .sender)
                try container.encode(timestamp, forKey: .timestamp)
            case .outgoingMessageDelivered(let sender, let timestamp):
                try container.encode(EncodedType.outgoingMessageDelivered, forKey: .type)
                try container.encode(sender, forKey: .sender)
                try container.encode(timestamp, forKey: .timestamp)
            case .outgoingMessageViewed(let sender, let timestamp):
                try container.encode(EncodedType.outgoingMessageViewed, forKey: .type)
                try container.encode(sender, forKey: .sender)
                try container.encode(timestamp, forKey: .timestamp)
            case .messageReadOnLinkedDevice(let timestamp):
                try container.encode(EncodedType.messageReadOnLinkedDevice, forKey: .type)
                try container.encode(timestamp, forKey: .timestamp)
            case .messageViewedOnLinkedDevice(let timestamp):
                try container.encode(EncodedType.messageViewedOnLinkedDevice, forKey: .type)
                try container.encode(timestamp, forKey: .timestamp)
            }
        }

        case outgoingMessageRead(sender: SignalServiceAddress, timestamp: UInt64)
        case outgoingMessageDelivered(sender: SignalServiceAddress, timestamp: UInt64)
        case outgoingMessageViewed(sender: SignalServiceAddress, timestamp: UInt64)
        case messageReadOnLinkedDevice(timestamp: UInt64)
        case messageViewedOnLinkedDevice(timestamp: UInt64)

        var timestamp: UInt64 {
            switch self {
            case .outgoingMessageRead(_, let timestamp):
                return timestamp
            case .outgoingMessageDelivered(_, let timestamp):
                return timestamp
            case .outgoingMessageViewed(_, let timestamp):
                return timestamp
            case .messageReadOnLinkedDevice(let timestamp):
                return timestamp
            case .messageViewedOnLinkedDevice(let timestamp):
                return timestamp
            }
        }

        init(receiptType: SSKProtoReceiptMessageType, sender: SignalServiceAddress, timestamp: UInt64) {
            switch receiptType {
            case .delivery: self = .outgoingMessageDelivered(sender: sender, timestamp: timestamp)
            case .read: self = .outgoingMessageRead(sender: sender, timestamp: timestamp)
            case .viewed: self = .outgoingMessageViewed(sender: sender, timestamp: timestamp)
            }
        }
    }

    private static let maxQueuedPerMessage: Int = 100
    private static let maxQueuedMessages: Int = 100
    private static let maxEarlyEnvelopeSize: Int = 1024

    private var pendingEnvelopeStore = SDSOrderedKeyValueStore<[EarlyEnvelope]>(collection: "EarlyEnvelopesStore")
    private var pendingReceiptStore =  SDSOrderedKeyValueStore<[EarlyReceipt]>(collection: "EarlyReceiptsStore")

    public override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.cleanupStaleMessages()
        }
    }

    @objc
    public func recordEarlyEnvelope(
        _ envelope: SSKProtoEnvelope,
        plainTextData: Data?,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        associatedMessageTimestamp: UInt64,
        associatedMessageAuthor: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) {
        guard plainTextData?.count ?? 0 <= Self.maxEarlyEnvelopeSize else {
            return owsFailDebug("unexpectedly tried to record an excessively large early envelope")
        }

        let identifier = MessageIdentifier(timestamp: associatedMessageTimestamp, author: associatedMessageAuthor)

        Logger.info("Recording early envelope \(OWSMessageManager.description(for: envelope)) for message \(identifier)")

        var envelopes = pendingEnvelopeStore.fetch(key: identifier.rawValue, transaction: transaction) ?? []

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
        pendingEnvelopeStore.appendByReplacingIfNeeded(key: identifier.rawValue, value: envelopes, transaction: transaction)

        while pendingEnvelopeStore.count(transaction: transaction) >= Self.maxQueuedMessages,
              let droppedEarlyIdentifier = pendingEnvelopeStore.firstKey(transaction: transaction) {
            pendingEnvelopeStore.remove(key: droppedEarlyIdentifier, transaction: transaction)
            owsFailDebug("Dropping all early envelopes for message \(droppedEarlyIdentifier) due to excessive early messages.")
        }
    }

    @objc
    public func recordEarlyReceiptForOutgoingMessage(
        type: SSKProtoReceiptMessageType,
        sender: SignalServiceAddress,
        timestamp: UInt64,
        associatedMessageTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        guard let localAddress = TSAccountManager.localAddress else {
            return owsFailDebug("missing local address")
        }

        let identifier = MessageIdentifier(timestamp: associatedMessageTimestamp, author: localAddress)

        Logger.info("Recording early \(type) receipt for outgoing message \(identifier)")

        recordEarlyReceipt(
            .init(receiptType: type, sender: sender, timestamp: timestamp),
            identifier: identifier,
            transaction: transaction
        )
    }

    @objc
    public func recordEarlyReadReceiptFromLinkedDevice(
        timestamp: UInt64,
        associatedMessageTimestamp: UInt64,
        associatedMessageAuthor: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) {
        let identifier = MessageIdentifier(timestamp: associatedMessageTimestamp, author: associatedMessageAuthor)

        Logger.info("Recording early read receipt from linked device for message \(identifier)")

        recordEarlyReceipt(
            .messageReadOnLinkedDevice(timestamp: timestamp),
            identifier: identifier,
            transaction: transaction
        )
    }

    @objc
    public func recordEarlyViewedReceiptFromLinkedDevice(
        timestamp: UInt64,
        associatedMessageTimestamp: UInt64,
        associatedMessageAuthor: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) {
        let identifier = MessageIdentifier(timestamp: associatedMessageTimestamp, author: associatedMessageAuthor)

        Logger.info("Recording early viewed receipt from linked device for message \(identifier)")

        recordEarlyReceipt(
            .messageViewedOnLinkedDevice(timestamp: timestamp),
            identifier: identifier,
            transaction: transaction
        )
    }

    private func recordEarlyReceipt(
        _ earlyReceipt: EarlyReceipt,
        identifier: MessageIdentifier,
        transaction: SDSAnyWriteTransaction
    ) {
        var receipts = pendingReceiptStore.fetch(key: identifier.rawValue, transaction: transaction) ?? []

        while receipts.count >= Self.maxQueuedPerMessage, let droppedEarlyReceipt = receipts.first {
            receipts.remove(at: 0)
            owsFailDebug("Dropping early receipt \(droppedEarlyReceipt) for message \(identifier) due to excessive early receipts.")
        }

        receipts.append(earlyReceipt)
        pendingReceiptStore.appendByReplacingIfNeeded(key: identifier.rawValue, value: receipts, transaction: transaction)

        while pendingReceiptStore.count(transaction: transaction) >= Self.maxQueuedMessages,
              let droppedEarlyIdentifier = pendingReceiptStore.firstKey(transaction: transaction) {
            pendingReceiptStore.remove(key: droppedEarlyIdentifier, transaction: transaction)
            owsFailDebug("Dropping all early envelopes for message \(droppedEarlyIdentifier) due to excessive early messages.")
        }
    }

    @objc
    public func applyPendingMessages(for message: TSMessage, transaction: SDSAnyWriteTransaction) {
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

        let earlyReceipts = pendingReceiptStore.remove(key: identifier.rawValue, transaction: transaction)

        // Apply any early receipts for this message
        for earlyReceipt in earlyReceipts ?? [] {
            switch earlyReceipt {
            case .outgoingMessageRead(let sender, let timestamp):
                Logger.info("Applying early read receipt from \(sender) for outgoing message \(identifier)")

                guard let message = message as? TSOutgoingMessage else {
                    owsFailDebug("Unexpected message type for early read receipt for outgoing message.")
                    continue
                }
                message.update(
                    withReadRecipient: sender,
                    readTimestamp: timestamp,
                    transaction: transaction
                )
            case .outgoingMessageViewed(let sender, let timestamp):
                Logger.info("Applying early viewed receipt from \(sender) for outgoing message \(identifier)")

                guard let message = message as? TSOutgoingMessage else {
                    owsFailDebug("Unexpected message type for early read receipt for outgoing message.")
                    continue
                }
                message.update(
                    withViewedRecipient: sender,
                    viewedTimestamp: timestamp,
                    transaction: transaction
                )
            case .outgoingMessageDelivered(let sender, let timestamp):
                Logger.info("Applying early delivery receipt from \(sender) for outgoing message \(identifier)")

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
                Logger.info("Applying early read receipt from linked device for message \(identifier)")

                OWSReceiptManager.shared.markAsRead(
                    onLinkedDevice: message,
                    thread: message.thread(transaction: transaction),
                    readTimestamp: timestamp,
                    transaction: transaction
                )
            case .messageViewedOnLinkedDevice(let timestamp):
                Logger.info("Applying early viewed receipt from linked device for message \(identifier)")

                OWSReceiptManager.shared.markAsViewed(
                    onLinkedDevice: message,
                    thread: message.thread(transaction: transaction),
                    viewedTimestamp: timestamp,
                    transaction: transaction
                )
            }
        }

        let earlyEnvelopes = pendingEnvelopeStore.remove(key: identifier.rawValue, transaction: transaction)

        // Re-process any early envelopes associated with this message
        for earlyEnvelope in earlyEnvelopes ?? [] {
            Logger.info("Reprocessing early envelope \(OWSMessageManager.description(for: earlyEnvelope.envelope)) for message \(identifier)")

            Self.messageManager.processEnvelope(
                earlyEnvelope.envelope,
                plaintextData: earlyEnvelope.plainTextData,
                wasReceivedByUD: earlyEnvelope.wasReceivedByUD,
                serverDeliveryTimestamp: earlyEnvelope.serverDeliveryTimestamp,
                transaction: transaction
            )
        }
    }

    private func cleanupStaleMessages() {
        databaseStorage.write { transction in
            let oldestTimestampToKeep = Date.ows_millisecondTimestamp() - kWeekInMs

            let pendingEnvelopes = pendingEnvelopeStore.orderedKeysAndValues(transaction: transction)
            for (key, envelopes) in pendingEnvelopes {
                let filteredEnvelopes = envelopes.filter { $0.envelope.timestamp > oldestTimestampToKeep }
                if filteredEnvelopes.isEmpty {
                    pendingEnvelopeStore.remove(key: key, transaction: transction)
                } else if filteredEnvelopes.count < envelopes.count {
                    pendingEnvelopeStore.replace(key: key, value: filteredEnvelopes, transaction: transction)
                }
            }

            let pendingReceipts = pendingReceiptStore.orderedKeysAndValues(transaction: transction)
            for (key, receipts) in pendingReceipts {
                let filteredReceipts = receipts.filter { $0.timestamp > oldestTimestampToKeep }
                if filteredReceipts.isEmpty {
                    pendingReceiptStore.remove(key: key, transaction: transction)
                } else if filteredReceipts.count < receipts.count {
                    pendingReceiptStore.replace(key: key, value: filteredReceipts, transaction: transction)
                }
            }
        }
    }
}

extension SDSOrderedKeyValueStore {
    fileprivate func appendByReplacingIfNeeded(key: String, value: ValueType, transaction: SDSAnyWriteTransaction) {
        remove(key: key, transaction: transaction)
        append(key: key, value: value, transaction: transaction)
    }
}
