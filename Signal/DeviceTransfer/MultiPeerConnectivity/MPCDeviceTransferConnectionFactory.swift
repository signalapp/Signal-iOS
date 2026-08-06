//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

struct MPCDeviceTransferConnectionFactory: DeviceTransferConnectionFactory {
    @MainActor
    func buildOutgoingConnection() -> any DeviceTransferOutgoingConnection {
        MPCDeviceTransferBrowser()
    }

    @MainActor
    func buildIncomingConnection() -> any DeviceTransferIncomingConnection {
        MPCDeviceTransferAdvertiser()
    }
}
