//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

extension DeviceId {
    public static let primary: DeviceId = DeviceId(validating: OWSDevice.primaryDeviceId)!

    public var isPrimary: Bool { self == .primary }
}
