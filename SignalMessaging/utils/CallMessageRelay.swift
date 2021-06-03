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
            messageProcessor.processEncryptedEnvelopeData(
                payload.encryptedEnvelopeData,
                serverDeliveryTimestamp: payload.serverDeliveryTimestamp
            ) { error in
                if let error = error {
                    owsFailDebug("Failed to process relayed call message \(error)")
                }
            }
        } catch {
            owsFailDebug("Failed to decode relay voip payload \(error)")
        }

        return true
    }

    public static func voipPayload(
        envelope: SSKProtoEnvelope,
        serverDeliveryTimestamp: UInt64
    ) throws -> [AnyHashable: Any] {
        let payload = Payload(
            encryptedEnvelopeData: try envelope.serializedData(),
            serverDeliveryTimestamp: serverDeliveryTimestamp
        )

        return [callMessagePayloadKey: try JSONEncoder().encode(payload)]
    }

    private struct Payload: Codable {
        let encryptedEnvelopeData: Data
        let serverDeliveryTimestamp: UInt64
    }
}
