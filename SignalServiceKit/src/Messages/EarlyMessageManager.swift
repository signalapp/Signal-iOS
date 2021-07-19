//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class EarlyMessageManager: NSObject {
    private struct MessageIdentifier: Hashable, Codable {
        let timestamp: UInt64
        let author: SignalServiceAddress

        var key: String {
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

    private static let maxEarlyEnvelopeSize: Int = 1024

    private var pendingEnvelopeStore = SDSKeyValueStore(collection: "EarlyEnvelopesStore")
    private var pendingReceiptStore =  SDSKeyValueStore(collection: "EarlyReceiptsStore")

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

        var envelopes: [EarlyEnvelope]
        do {
            envelopes = try pendingEnvelopeStore.getCodableValue(forKey: identifier.key, transaction: transaction) ?? []
        } catch {
            owsFailDebug("Failed to decode existing early envelopes for message \(identifier) with error \(error)")
            envelopes = []
        }

        envelopes.append(EarlyEnvelope(
            envelope: envelope,
            plainTextData: plainTextData,
            wasReceivedByUD: wasReceivedByUD,
            serverDeliveryTimestamp: serverDeliveryTimestamp
        ))

        do {
            try pendingEnvelopeStore.setCodable(envelopes, key: identifier.key, transaction: transaction)
        } catch {
            owsFailDebug("Failed to persist early envelope \(OWSMessageManager.description(for: envelope)) for message \(identifier) with error \(error)")
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
        var receipts: [EarlyReceipt]
        do {
            receipts = try pendingReceiptStore.getCodableValue(forKey: identifier.key, transaction: transaction) ?? []
        } catch {
            owsFailDebug("Failed to decode existing early receipts for message \(identifier) with error \(error)")
            receipts = []
        }

        receipts.append(earlyReceipt)

        do {
            try pendingReceiptStore.setCodable(receipts, key: identifier.key, transaction: transaction)
        } catch {
            owsFailDebug("Failed to persist early receipt for message \(identifier) with error \(error)")
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
            guard message.authorUUID != nil else {
                return owsFailDebug("Attempted to apply pending messages for message missing sender uuid with type \(message.interactionType()) from \(message.authorAddress)")
            }

            identifier = MessageIdentifier(timestamp: message.timestamp, author: message.authorAddress)
        } else {
            // We only support early envelopes for incoming + outgoing message types, for now.
            return owsFailDebug("attempted to apply pending messages for unsupported message type \(message.interactionType())")
        }

        let earlyReceipts: [EarlyReceipt]?
        do {
            earlyReceipts = try pendingReceiptStore.getCodableValue(forKey: identifier.key, transaction: transaction)
        } catch {
            owsFailDebug("Failed to decode early receipts for message \(identifier) with error \(error)")
            earlyReceipts = nil
        }

        pendingReceiptStore.removeValue(forKey: identifier.key, transaction: transaction)

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

        let earlyEnvelopes: [EarlyEnvelope]?
        do {
            earlyEnvelopes = try pendingEnvelopeStore.getCodableValue(forKey: identifier.key, transaction: transaction)
        } catch {
            owsFailDebug("Failed to decode early envelopes for message \(identifier) with error \(error)")
            earlyEnvelopes = nil
        }

        pendingEnvelopeStore.removeValue(forKey: identifier.key, transaction: transaction)

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
        databaseStorage.asyncWrite { transction in
            let oldestTimestampToKeep = Date.ows_millisecondTimestamp() - kWeekInMs

            let allEnvelopeKeys = self.pendingEnvelopeStore.allKeys(transaction: transction)
            let staleEnvelopeKeys = allEnvelopeKeys.filter {
                guard let timestampString = $0.split(separator: ".")[safe: 1],
                      let timestamp = UInt64(timestampString),
                      timestamp > oldestTimestampToKeep else {
                    return false
                }
                return true
            }
            self.pendingEnvelopeStore.removeValues(forKeys: staleEnvelopeKeys, transaction: transction)

            let allReceiptKeys = self.pendingReceiptStore.allKeys(transaction: transction)
            let staleReceiptKeys = allReceiptKeys.filter {
                guard let timestampString = $0.split(separator: ".")[safe: 1],
                      let timestamp = UInt64(timestampString),
                      timestamp > oldestTimestampToKeep else {
                    return false
                }
                return true
            }
            self.pendingReceiptStore.removeValues(forKeys: staleReceiptKeys, transaction: transction)
        }
    }
}
