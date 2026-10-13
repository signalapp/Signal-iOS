//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import WiFiAware

@available(iOS 26.0, *)
struct WADeviceTransferPeer: DeviceTransfer.Peer, CustomStringConvertible {

    let id: Int
    var displayName: String { pairedDevice.displayName }
    let pairedDevice: WAPairedDevice

    init(pairedDevice: WAPairedDevice) {
        var hasher = Hasher()
        hasher.combine(pairedDevice.displayName)
        hasher.combine(pairedDevice.id)
        self.id = hasher.finalize()
        self.pairedDevice = pairedDevice
    }

    /// Deliberately omits `displayName`. These values are logged at `.info`, so
    /// they end up in submitted debug logs, and the display name is a
    /// user-chosen device name that often contains a real name.
    var description: String {
        "WADeviceTransferPeer(id: \(id), pairedDeviceId: \(pairedDevice.id))"
    }
}
