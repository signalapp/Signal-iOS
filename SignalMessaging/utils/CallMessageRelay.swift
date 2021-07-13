//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CallMessageRelay: NSObject {
    private static let callMessagePayloadKey = "CallMessageRelayPayload"
    private static let pendingCallMessageStore = SDSKeyValueStore(collection: "PendingCallMessageStore")

    @objc
    public static func handleVoipPayload(_ payload: [AnyHashable: Any]) -> Bool {
        guard let payload = payload[callMessagePayloadKey] as? Bool, payload == true else { return false }

        // Process all the pending call messages from the NSE in 1 batch.
        // This should almost always be a batch of one.
        databaseStorage.asyncWrite { transaction in
            defer { pendingCallMessageStore.removeAll(transaction: transaction) }
            let pendingPayloads: [Payload]

            do {
                pendingPayloads = try pendingCallMessageStore.allCodableValues(transaction: transaction).sorted {
                    $0.envelope.timestamp < $1.envelope.timestamp
                }
            } catch {
                owsFailDebug("Failed to read pending call messages \(error)")
                return
            }

            Logger.info("Processing \(pendingPayloads.count) call messages relayed from the NSE.")
            owsAssertDebug(pendingPayloads.count == 1, "Unexpectedly processing multiple messages from the NSE at once")

            for payload in pendingPayloads {
                messageManager.processEnvelope(
                    payload.envelope,
                    plaintextData: payload.plaintextData,
                    wasReceivedByUD: payload.wasReceivedByUD,
                    serverDeliveryTimestamp: payload.serverDeliveryTimestamp,
                    shouldDiscardVisibleMessages: false,
                    transaction: transaction
                )
            }
        }

        return true
    }

    public static func enqueueCallMessageForMainApp(
        envelope: SSKProtoEnvelope,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) throws -> [String: Any] {
        let payload = Payload(
            envelope: envelope,
            plaintextData: plaintextData,
            wasReceivedByUD: wasReceivedByUD,
            serverDeliveryTimestamp: serverDeliveryTimestamp
        )

        try pendingCallMessageStore.setCodable(payload, key: "\(envelope.timestamp)", transaction: transaction)

        return [callMessagePayloadKey: true]
    }

    private struct Payload: Codable {
        let envelope: SSKProtoEnvelope
        let plaintextData: Data
        let wasReceivedByUD: Bool
        let serverDeliveryTimestamp: UInt64
    }
}
