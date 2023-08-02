//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

/// Represents an incoming envelope that's been validated but not decrypted.
///
/// If your method accepts this type, then it can rely on the validation
/// performed in the initializer because that's the ONLY way to produce an
/// object of this type.
///
/// This type also converts values it validates into new types with
/// stricter, compile-time guarantees. For example, the destination of the
/// envelope is converted to the two-case `localIdentity` enum rather than
/// an arbitrary `ServiceId`. Similarly, the envelope's type is converted to
/// a `Kind` enum; this enum eliminates the need to repeatedly consider all
/// possible envelope types in downstream code.
class ValidatedIncomingEnvelope {
    let timestamp: UInt64
    let serverTimestamp: UInt64
    let envelope: SSKProtoEnvelope
    let kind: Kind
    let localIdentity: OWSIdentity

    init(_ envelope: SSKProtoEnvelope, localIdentifiers: LocalIdentifiers) throws {
        self.envelope = envelope

        guard envelope.timestamp >= 1, SDS.fitsInInt64(envelope.timestamp) else {
            throw OWSAssertionError("Invalid timestamp.")
        }
        self.timestamp = envelope.timestamp

        guard envelope.hasServerTimestamp, SDS.fitsInInt64(envelope.serverTimestamp) else {
            throw OWSAssertionError("Invalid serverTimestamp.")
        }
        self.serverTimestamp = envelope.serverTimestamp

        let kind: Kind
        switch envelope.type {
        case .receipt:
            kind = .serverReceipt
        case .ciphertext:
            kind = .identifiedSender(.whisper)
        case .prekeyBundle:
            kind = .identifiedSender(.preKey)
        case .senderkeyMessage:
            kind = .identifiedSender(.senderKey)
        case .plaintextContent:
            kind = .identifiedSender(.plaintext)
        case .unidentifiedSender:
            kind = .unidentifiedSender
        case .unknown, .keyExchange, .none:
            throw OWSGenericError("Unsupported type.")
        }
        self.kind = kind

        self.localIdentity = try Self.localIdentity(for: envelope, localIdentifiers: localIdentifiers)
        try Self.validateEnvelopeKind(kind, for: localIdentity)
    }

    enum Kind {
        case serverReceipt
        case identifiedSender(CiphertextMessage.MessageType)
        case unidentifiedSender
    }

    // MARK: - Source

    func validateSource<T: ServiceId>(_ type: T.Type) throws -> (T, UInt32) {
        guard
            let sourceServiceIdString = envelope.sourceServiceID,
            let sourceServiceId = try ServiceId.parseFrom(serviceIdString: sourceServiceIdString) as? T
        else {
            throw OWSAssertionError("Invalid source.")
        }
        guard envelope.hasSourceDevice, envelope.sourceDevice >= 1 else {
            throw OWSAssertionError("Invalid source device.")
        }
        return (sourceServiceId, envelope.sourceDevice)
    }

    // MARK: - Destination

    private static func localIdentity(
        for envelope: SSKProtoEnvelope,
        localIdentifiers: LocalIdentifiers
    ) throws -> OWSIdentity {
        // Old, locally-persisted envelopes may not have a destination specified.
        guard let destinationServiceIdString = envelope.destinationServiceID, !destinationServiceIdString.isEmpty else {
            return .aci
        }
        let destinationServiceId = try ServiceId.parseFrom(serviceIdString: destinationServiceIdString)
        switch destinationServiceId {
        case localIdentifiers.aci:
            return .aci
        case localIdentifiers.pni:
            return .pni
        default:
            throw MessageProcessingError.wrongDestinationUuid
        }
    }

    private static func validateEnvelopeKind(_ kind: Kind, for localIdentity: OWSIdentity) throws {
        let canBeReceived: Bool = {
            switch kind {
            case .serverReceipt:
                return true
            case .identifiedSender(.whisper):
                return localIdentity == .aci
            case .identifiedSender(.preKey):
                return true
            case .identifiedSender(.senderKey):
                return localIdentity == .aci
            case .identifiedSender(.plaintext):
                return localIdentity == .aci
            case .identifiedSender:
                return false
            case .unidentifiedSender:
                return localIdentity == .aci
            }
        }()
        guard canBeReceived else {
            throw MessageProcessingError.invalidMessageTypeForDestinationUuid
        }
    }
}
