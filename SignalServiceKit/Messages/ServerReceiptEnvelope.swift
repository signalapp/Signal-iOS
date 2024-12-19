//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Represents an envelope containing a server delivery receipt.
///
/// When you send a non-Sealed Sender message to the server, the server
/// sends back a delivery receipt. This type represents those envelopes.
class ServerReceiptEnvelope {
    let validatedEnvelope: ValidatedIncomingEnvelope
    let sourceServiceId: ServiceId
    let sourceDeviceId: UInt32

    init(_ validatedEnvelope: ValidatedIncomingEnvelope) throws {
        let (sourceServiceId, sourceDeviceId) = try validatedEnvelope.validateSource(ServiceId.self)
        self.sourceServiceId = sourceServiceId
        self.sourceDeviceId = sourceDeviceId
        self.validatedEnvelope = validatedEnvelope
    }
}
