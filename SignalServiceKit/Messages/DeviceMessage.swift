//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct DeviceMessage {
    let type: SSKProtoEnvelopeType
    let destinationDeviceId: UInt32
    let destinationRegistrationId: UInt32
    let serializedMessage: Data
}

struct SentDeviceMessage {
    var destinationDeviceId: UInt32
    var destinationRegistrationId: UInt32
}
