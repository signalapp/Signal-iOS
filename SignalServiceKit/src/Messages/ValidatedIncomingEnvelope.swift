//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

class ValidatedIncomingEnvelope {
    let timestamp: UInt64
    let serverTimestamp: UInt64
    let envelopeType: SSKProtoEnvelopeType
    let envelope: SSKProtoEnvelope

    init(_ envelope: SSKProtoEnvelope) throws {
        self.envelope = envelope

        guard envelope.timestamp >= 1, SDS.fitsInInt64(envelope.timestamp) else {
            throw OWSAssertionError("Invalid timestamp.")
        }
        self.timestamp = envelope.timestamp

        guard envelope.hasServerTimestamp, SDS.fitsInInt64(envelope.serverTimestamp) else {
            throw OWSAssertionError("Invalid serverTimestamp.")
        }
        self.serverTimestamp = envelope.serverTimestamp

        guard let envelopeType = envelope.type else {
            throw OWSAssertionError("Missing type.")
        }
        self.envelopeType = envelopeType
    }

    func canBeReceived(by localIdentity: OWSIdentity) -> Bool {
        switch envelopeType {
        case .unknown:
            return localIdentity == .aci
        case .ciphertext:
            return localIdentity == .aci
        case .keyExchange:
            return localIdentity == .aci
        case .prekeyBundle:
            return true
        case .receipt:
            return true
        case .unidentifiedSender:
            return localIdentity == .aci
        case .senderkeyMessage:
            return localIdentity == .aci
        case .plaintextContent:
            return localIdentity == .aci
        }
    }
}
