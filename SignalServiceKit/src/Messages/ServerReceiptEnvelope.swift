//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Represents an envelope containing a servery delivery receipt.
///
/// When you send a non-Sealed Sender message to the server, the server
/// sends back a delivery receipt. This type represents those envelopes.
@objc
class ServerReceiptEnvelope: NSObject {
    let validatedEnvelope: ValidatedIncomingEnvelope
    let sourceServiceId: ServiceId
    @objc
    let sourceDeviceId: UInt32

    @objc
    var timestamp: UInt64 { validatedEnvelope.timestamp }

    @objc
    var sourceServiceIdObjC: UntypedServiceIdObjC {
        UntypedServiceIdObjC(sourceServiceId.untypedServiceId)
    }

    init(_ validatedEnvelope: ValidatedIncomingEnvelope) throws {
        let (sourceServiceId, sourceDeviceId) = try validatedEnvelope.validateSource(ServiceId.self)
        self.sourceServiceId = sourceServiceId
        self.sourceDeviceId = sourceDeviceId
        self.validatedEnvelope = validatedEnvelope
    }
}
