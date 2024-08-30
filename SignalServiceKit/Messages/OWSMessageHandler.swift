//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class OWSMessageHandler: NSObject {

    private static func descriptionForEnvelopeType(_ envelope: SSKProtoEnvelope) -> String {
        guard envelope.hasType else {
            return "Missing Type."
        }
        switch envelope.unwrappedType {
        case .unknown:
            // Shouldn't happen
            return "Unknown"
        case .ciphertext:
            return "SignalEncryptedMessage"
        case .keyExchange:
            // Unsupported
            return "KeyExchange"
        case .prekeyBundle:
            return "PreKeyEncryptedMessage"
        case .receipt:
            return "DeliveryReceipt"
        case .unidentifiedSender:
            return "UnidentifiedSender"
        case .senderkeyMessage:
            return "SenderKey"
        case .plaintextContent:
            return "PlaintextContent"
        }
    }

    static func description(for envelope: SSKProtoEnvelope) -> String {
        return "<Envelope type: \(descriptionForEnvelopeType(envelope)), source: \(envelope.formattedAddress), timestamp: \(envelope.timestamp), serverTimestamp: \(envelope.serverTimestamp), serverGuid: \(envelope.serverGuid ?? "(null)"), content.length: \(envelope.content?.count ?? 0) />"
    }
}
