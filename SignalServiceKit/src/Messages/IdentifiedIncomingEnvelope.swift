//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
class IdentifiedIncomingEnvelope: NSObject {
    let sourceServiceId: UntypedServiceId

    @objc
    let sourceServiceIdObjC: UntypedServiceIdObjC

    @objc
    let sourceDeviceId: UInt32

    @objc
    let timestamp: UInt64

    @objc
    let serverTimestamp: UInt64

    @objc
    let envelopeType: SSKProtoEnvelopeType

    @objc
    let envelope: SSKProtoEnvelope

    private init(
        validatedEnvelope: ValidatedIncomingEnvelope,
        updatedEnvelope: SSKProtoEnvelope,
        sourceServiceId: UntypedServiceId,
        sourceDeviceId: UInt32
    ) throws {
        self.envelope = updatedEnvelope
        self.timestamp = validatedEnvelope.timestamp
        self.serverTimestamp = validatedEnvelope.serverTimestamp
        self.envelopeType = validatedEnvelope.envelopeType
        self.sourceServiceId = sourceServiceId
        self.sourceServiceIdObjC = UntypedServiceIdObjC(sourceServiceId)
        guard sourceDeviceId >= 1 else {
            throw OWSAssertionError("Invalid source device.")
        }
        self.sourceDeviceId = sourceDeviceId
    }

    convenience init(validatedEnvelope: ValidatedIncomingEnvelope) throws {
        let envelope = validatedEnvelope.envelope
        guard let sourceServiceId = envelope.sourceServiceId else {
            throw OWSAssertionError("Invalid source.")
        }
        guard envelope.hasSourceDevice else {
            throw OWSAssertionError("Invalid source device.")
        }
        try self.init(
            validatedEnvelope: validatedEnvelope,
            updatedEnvelope: envelope,
            sourceServiceId: sourceServiceId,
            sourceDeviceId: envelope.sourceDevice
        )
    }

    convenience init(
        validatedEnvelope: ValidatedIncomingEnvelope,
        sourceServiceId: UntypedServiceId,
        sourceDeviceId: UInt32
    ) throws {
        let envelopeBuilder = validatedEnvelope.envelope.asBuilder()
        envelopeBuilder.setSourceUuid(sourceServiceId.uuidValue.uuidString)
        envelopeBuilder.setSourceDevice(sourceDeviceId)
        try self.init(
            validatedEnvelope: validatedEnvelope,
            updatedEnvelope: envelopeBuilder.build(),
            sourceServiceId: sourceServiceId,
            sourceDeviceId: sourceDeviceId
        )
    }
}
