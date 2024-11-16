//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class CallMessagePushPayload: CustomStringConvertible {
    private static let identifierKey = "CallMessageRelayPayload"
    public let identifier: String

    fileprivate init() {
        identifier = UUID().uuidString
    }

    public init?(_ payloadDict: [AnyHashable: Any]) {
        guard let payloadId = payloadDict[Self.identifierKey] as? String else { return nil }
        identifier = payloadId
    }

    public var payloadDict: [String: String] {
        [Self.identifierKey: identifier]
    }

    public var description: String {
        "\(type(of: self)): \(identifier.suffix(6))"
    }
}

public class CallMessageRelay {
    private static let pendingCallMessageStore = KeyValueStore(collection: "PendingCallMessageStore")

    public static func handleVoipPayload(_ payload: CallMessagePushPayload) {
        Logger.info("Handling incoming VoIP payload: \(payload)")
        defer { Logger.info("Finished handling incoming VoIP payload: \(payload)") }
        // Process all the pending call messages from the NSE in 1 batch.
        // This should almost always be a batch of one.
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            defer { pendingCallMessageStore.removeAll(transaction: transaction.asV2Write) }
            let pendingPayloads: [Payload]

            do {
                pendingPayloads = try pendingCallMessageStore.allCodableValues(transaction: transaction.asV2Read).sorted {
                    $0.envelope.timestamp < $1.envelope.timestamp
                }
            } catch {
                owsFailDebug("Failed to read pending call messages \(error)")
                return
            }

            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
                owsFailDebug("Can't process VoIP payload when not registered.")
                return
            }

            Logger.info("Processing \(pendingPayloads.count) call messages relayed from the NSE.")

            for payload in pendingPayloads {
                // Pretend we are just receiving the message now.
                // This ensures that if we process a very old ring message, it will correctly be considered "expired".
                // "This should never happen" in normal operation, but in practice we have seen it happen,
                // e.g. when there's a crash processing the queued ring message.
                let delaySecondsSinceDelivery = -(payload.enqueueTimestamp?.timeIntervalSinceNow ?? 0)
                let adjustedDeliveryTimestamp =
                    payload.serverDeliveryTimestamp + UInt64(1000 * max(0, delaySecondsSinceDelivery))

                SSKEnvironment.shared.messageReceiverRef.processEnvelope(
                    payload.envelope,
                    plaintextData: payload.plaintextData,
                    wasReceivedByUD: payload.wasReceivedByUD,
                    serverDeliveryTimestamp: adjustedDeliveryTimestamp,
                    shouldDiscardVisibleMessages: false,
                    localIdentifiers: localIdentifiers,
                    tx: transaction
                )
            }
        }
    }

    public static func enqueueCallMessageForMainApp(
        envelope: SSKProtoEnvelope,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) throws -> CallMessagePushPayload {
        let payload = Payload(
            envelope: envelope,
            plaintextData: plaintextData,
            wasReceivedByUD: wasReceivedByUD,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            enqueueTimestamp: Date()
        )

        try pendingCallMessageStore.setCodable(payload, key: "\(envelope.timestamp)", transaction: transaction.asV2Write)
        return CallMessagePushPayload()
    }

    private struct Payload: Codable {
        let envelope: SSKProtoEnvelope
        let plaintextData: Data
        let wasReceivedByUD: Bool
        let serverDeliveryTimestamp: UInt64
        let enqueueTimestamp: Date?
    }
}
