//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

struct MPCDeviceTransferConnectionFactory: DeviceTransferConnectionFactory {
    @MainActor
    func buildOutgoingConnection(tsAccountManager: TSAccountManager) -> any DeviceTransferOutgoingConnection {
        MPCDeviceTransferBrowser(tsAccountManager: tsAccountManager)
    }

    @MainActor
    func buildIncomingConnection(tsAccountManager: TSAccountManager) -> any DeviceTransferIncomingConnection {
        MPCDeviceTransferAdvertiser(tsAccountManager: tsAccountManager)
    }
}
