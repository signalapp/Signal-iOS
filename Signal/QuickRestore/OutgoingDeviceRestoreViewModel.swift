//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

enum DeviceRestoreError: Error {
    case invalidRestoreData
}

class OutgoingDeviceRestoreViewModel: ObservableObject {

    private(set) var transferStatusViewModel = TransferStatusViewModel()
    private let quickRestoreManager: QuickRestoreManager
    private let provisioningURL: DeviceProvisioningURL
    private let outgoingDeviceTransferTask: OutgoingDeviceTransferTask

    @MainActor
    init(
        db: DB,
        deviceProvisioningURL: DeviceProvisioningURL,
        deviceSleepManager: DeviceSleepManager?,
        quickRestoreManager: QuickRestoreManager,
        registrationStateChangeManager: RegistrationStateChangeManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.quickRestoreManager = quickRestoreManager
        self.provisioningURL = deviceProvisioningURL
        self.outgoingDeviceTransferTask = OutgoingDeviceTransferTask(
            db: db,
            deviceSleepManager: deviceSleepManager,
            deviceTransferConnectionFactory: DeviceTransfer.defaultFactory,
            registrationStateChangeManager: registrationStateChangeManager,
            tsAccountManager: tsAccountManager,
        )

        transferStatusViewModel.cancelTransferBlock = { [weak self] in
            self?.cancelTransfer()
        }
    }

    func confirmTransfer() async -> Bool {
        return await LocalDeviceAuthentication().performBiometricAuth() != nil
    }

    /// This uses the QuickRestore path behind the scenes to bootstrap a device transfer between two devices.
    /// 1. Outgoing device scans the QR code, then sends a RegistrationProvisioningMessage to the device that displayed the QR.
    /// 2. Outgoing device will wait for the restore method choice from the other device.
    /// 3. Confirm the returned choice is 'device transfer' or fail.
    /// 4. Parse out the MPC connection information returned in the restore method choice, and return this connection data
    func waitForRestoreMethodResponse() async throws(DeviceRestoreError) -> QuickRestoreManager.RestoreMethodType {
        let restoreMethod: QuickRestoreManager.RestoreMethodType
        do {
            let token = try await quickRestoreManager.register(deviceProvisioningUrl: provisioningURL)
            restoreMethod = try await quickRestoreManager.waitForRestoreMethodChoice(restoreMethodToken: token)
        } catch {
            Logger.error("Failed to wait for restore method choice: \(error)")
            throw DeviceRestoreError.invalidRestoreData
        }
        return restoreMethod
    }

    /// Take the `PeerConnectionData` returned by `waitForConnectionData` and
    /// begin listening for the connection described in `PeerConnectionData`.
    func waitForDeviceConnection(transferUrl: URL) async throws {
        // If in any state but .idle, return
        guard case .idle = transferStatusViewModel.state else {
            return
        }

        transferStatusViewModel.state = .starting
        try await outgoingDeviceTransferTask.connectToNewDevice(deviceTransferUrl: transferUrl)
    }

    /// Once connected to the device described in `PeerConnectionData`
    /// begin a device transfer.
    @MainActor
    func startTransfer() async throws {
        defer {
            stopListeningForTransfer(error: nil)
        }
        do {
            try await outgoingDeviceTransferTask.transferAccountToNewDevice { [weak self] progress in
                self?.updateProgress(progress: progress)
            }
            transferStatusViewModel.state = .done
            transferStatusViewModel.onSuccess()
        } catch where error is CancellationError {
            throw error
        } catch {
            Logger.error("Failed transfer to new device")
            transferStatusViewModel.state = .error(error)
            throw error
        }
    }

    @MainActor
    private func cancelTransfer() {
        stopListeningForTransfer(error: CancellationError())
        transferStatusViewModel.state = .cancelled
    }

    @MainActor
    private func stopListeningForTransfer(error: Error?) {
        outgoingDeviceTransferTask.stop(error: error)
    }

    private var progressObserver: NSKeyValueObservation?
    private func updateProgress(progress: Progress) {
        self.progressObserver = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, change in
            Task { @MainActor in
                let newValue = change.newValue ?? 0
                self?.transferStatusViewModel.state = .transferring(newValue)
            }
        }
    }
}
