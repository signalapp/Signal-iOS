//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

struct MPCDeviceTransferConnectionFactory: DeviceTransfer.ConnectionFactory {
    @MainActor
    func buildOutgoingConnection(tsAccountManager: TSAccountManager, deviceTransferURL: URL) throws -> any DeviceTransfer.OutgoingConnection {
        try MPCDeviceTransferBrowser(tsAccountManager: tsAccountManager, deviceTransferURL: deviceTransferURL)
    }

    @MainActor
    func buildIncomingConnection(tsAccountManager: TSAccountManager) throws -> any DeviceTransfer.IncomingConnection {
        try MPCDeviceTransferAdvertiser(tsAccountManager: tsAccountManager)
    }
}
