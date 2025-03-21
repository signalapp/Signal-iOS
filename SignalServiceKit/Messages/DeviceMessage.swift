//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct DeviceMessage {
    let type: SSKProtoEnvelopeType
    let destinationDeviceId: DeviceId
    let destinationRegistrationId: UInt32
    let content: Data
}

struct SentDeviceMessage {
    var destinationDeviceId: DeviceId
    var destinationRegistrationId: UInt32
}
