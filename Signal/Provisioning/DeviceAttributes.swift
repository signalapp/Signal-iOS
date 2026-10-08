//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

struct DeviceAttributes: Encodable {
    /// See AccountAttributes.isManualMessageFetchEnabled.
    var fetchesMessages: Bool

    /// See AccountAttributes.registrationId.
    var registrationId: UInt32

    /// See AccountAttributes.pniRegistrationId.
    var pniRegistrationId: UInt32?

    /// See AccountAttributes.encryptedDeviceName.
    var name: Data

    var capabilities: AccountAttributes.Capabilities
}
