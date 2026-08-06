//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

enum DeviceRestoreError: Error {
    case invalidRestoreData
    case restoreCancelled
    case unknownError
}

class OutgoingDeviceRestoreViewModel: ObservableObject {

    struct RestoreMethodData {
        struct PeerConnectionData {
            var peerId: any DeviceTransferPeerID
            var certificateHash: Data
        }

        let restoreMethod: QuickRestoreManager.RestoreMethodType
        let peerConnectionData: PeerConnectionData?

        fileprivate init(restoreMethod: QuickRestoreManager.RestoreMethodType, peerConnectionData: PeerConnectionData?) {
            self.restoreMethod = restoreMethod
            self.peerConnectionData = peerConnectionData
        }
    }

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
    func waitForRestoreMethodResponse() async throws(DeviceRestoreError) -> RestoreMethodData {
        let restoreMethod: QuickRestoreManager.RestoreMethodType
        do {
            let token = try await quickRestoreManager.register(deviceProvisioningUrl: provisioningURL)
            restoreMethod = try await quickRestoreManager.waitForRestoreMethodChoice(restoreMethodToken: token)
        } catch {
            Logger.error("Failed to wait for restore method choice: \(error)")
            throw DeviceRestoreError.invalidRestoreData
        }

        guard case let .deviceTransfer(transferData) = restoreMethod else {
            return RestoreMethodData(restoreMethod: restoreMethod, peerConnectionData: nil)
        }
        guard
            let stringData = Data(base64EncodedWithoutPadding: transferData),
            let urlString = String(data: stringData, encoding: .utf8),
            let transferURL = URL(string: urlString)
        else {
            Logger.error("Attempting to restore using a method other than device transfer")
            throw DeviceRestoreError.invalidRestoreData
        }

        do {
            let (peerId, certificateHash) = try await outgoingDeviceTransferTask.parseTransferURL(
                transferURL,
                tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            )
            return RestoreMethodData(
                restoreMethod: restoreMethod,
                peerConnectionData: RestoreMethodData.PeerConnectionData(
                    peerId: peerId,
                    certificateHash: certificateHash,
                ),
            )
        } catch {
            Logger.error("Failed to parse transfer URL: \(error)")
            throw DeviceRestoreError.invalidRestoreData
        }
    }

    /// Take the `PeerConnectionData` returned by `waitForConnectionData` and
    /// begin listening for the connection described in `PeerConnectionData`.
    func waitForDeviceConnection(peerConnectionData: RestoreMethodData.PeerConnectionData) async throws {
        // If in any state but .idle, return
        guard case .idle = transferStatusViewModel.state else {
            return
        }

        transferStatusViewModel.state = .starting
        try await outgoingDeviceTransferTask.connectToNewDevice(
            with: peerConnectionData.peerId,
            certificateHash: peerConnectionData.certificateHash,
        )
    }

    /// Once connected to the device described in `PeerConnectionData`
    /// begin a device transfer.
    @MainActor
    func startTransfer() async throws {
        do {
            try await outgoingDeviceTransferTask.transferAccountToNewDevice { [weak self] progress in
                self?.updateProgress(progress: progress)
            }
            transferStatusViewModel.state = .done
        } catch where error is CancellationError {
            throw error
        } catch {
            stopListeningForTransfer()
            Logger.error("Failed transfer to new device")
            transferStatusViewModel.state = .error(error)
            throw error
        }
    }

    @MainActor
    private func cancelTransfer() {
        stopListeningForTransfer()
        transferStatusViewModel.state = .cancelled
    }

    @MainActor
    private func stopListeningForTransfer() {
        outgoingDeviceTransferTask.stop()
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
