//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CallMessageRelay: NSObject {
    private static let callMessagePayloadKey = "CallMessageRelayPayload"

    @objc
    public static func handleVoipPayload(_ payload: [AnyHashable: Any]) -> Bool {
        guard let payloadData = payload[callMessagePayloadKey] as? Data else { return false }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: payloadData)
            databaseStorage.asyncWrite { transaction in
                messageManager.processEnvelope(
                    payload.envelope,
                    plaintextData: payload.plaintextData,
                    wasReceivedByUD: payload.wasReceivedByUD,
                    serverDeliveryTimestamp: payload.serverDeliveryTimestamp,
                    transaction: transaction
                )
            }
        } catch {
            owsFailDebug("Failed to decode relay voip payload \(error)")
        }

        return true
    }

    public static func voipPayload(
        envelope: SSKProtoEnvelope,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64
    ) throws -> [AnyHashable: Any] {
        let payload = Payload(
            envelope: envelope,
            plaintextData: plaintextData,
            wasReceivedByUD: wasReceivedByUD,
            serverDeliveryTimestamp: serverDeliveryTimestamp
        )

        return [callMessagePayloadKey: try JSONEncoder().encode(payload)]
    }

    private struct Payload: Codable {
        let envelope: SSKProtoEnvelope
        let plaintextData: Data
        let wasReceivedByUD: Bool
        let serverDeliveryTimestamp: UInt64
    }
}
