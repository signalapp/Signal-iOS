//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
class DeviceMessage: NSObject {
    @objc
    let type: SSKProtoEnvelopeType

    @objc
    let destinationDeviceId: UInt32

    @objc
    let destinationRegistrationId: UInt32

    @objc
    let serializedMessage: Data

    init(
        type: SSKProtoEnvelopeType,
        destinationDeviceId: UInt32,
        destinationRegistrationId: UInt32,
        serializedMessage: Data
    ) {
        self.type = type
        self.destinationDeviceId = destinationDeviceId
        self.destinationRegistrationId = destinationRegistrationId
        self.serializedMessage = serializedMessage
    }
}
