//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

struct MPCDeviceTransferConnectionFactory: DeviceTransfer.ConnectionFactory {
    @MainActor
    func buildOutgoingConnection(tsAccountManager: TSAccountManager) -> any DeviceTransfer.OutgoingConnection {
        MPCDeviceTransferBrowser(tsAccountManager: tsAccountManager)
    }

    @MainActor
    func buildIncomingConnection(tsAccountManager: TSAccountManager) -> any DeviceTransfer.IncomingConnection {
        MPCDeviceTransferAdvertiser(tsAccountManager: tsAccountManager)
    }
}
