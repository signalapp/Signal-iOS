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
    private let logger = PrefixedLogger(prefix: "[WiFiAware][Outgoing]")

    private(set) var transferStatusViewModel = TransferStatusViewModel()
    private var outgoingDeviceTransferTask: OutgoingDeviceTransferTask?

    private let db: DB
    private let provisioningURL: DeviceProvisioningURL
    private let deviceSleepManager: DeviceSleepManager?
    private let messageProcessor: MessageProcessor
    private let messagePipelineSupervisor: MessagePipelineSupervisor
    private let quickRestoreManager: QuickRestoreManager
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let tsAccountManager: TSAccountManager

    private var pairedPeersListenerTask: Task<Void, Error>?
    private var discoveredPeersListenerTask: Task<Void, Error>?
    let waitForPeerContinuation = AtomicValue<CheckedContinuation<any DeviceTransfer.Peer, Error>?>(nil, lock: .init())

    @MainActor
    init(
        db: DB,
        deviceProvisioningURL: DeviceProvisioningURL,
        deviceSleepManager: DeviceSleepManager?,
        messagePipelineSupervisor: MessagePipelineSupervisor,
        messageProcessor: MessageProcessor,
        quickRestoreManager: QuickRestoreManager,
        registrationStateChangeManager: RegistrationStateChangeManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.db = db
        self.provisioningURL = deviceProvisioningURL
        self.deviceSleepManager = deviceSleepManager
        self.messagePipelineSupervisor = messagePipelineSupervisor
        self.messageProcessor = messageProcessor
        self.quickRestoreManager = quickRestoreManager
        self.registrationStateChangeManager = registrationStateChangeManager
        self.tsAccountManager = tsAccountManager

        transferStatusViewModel.cancelTransferBlock = { [weak self] in
            Task {
                await self?.cancelTransfer()
            }
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
    @MainActor
    func waitForRestoreMethodResponse() async throws -> QuickRestoreManager.RestoreMethodType {
        let restoreMethod: QuickRestoreManager.RestoreMethodType
        do {
            let token = try await quickRestoreManager.register(deviceProvisioningUrl: provisioningURL)
            restoreMethod = try await quickRestoreManager.waitForRestoreMethodChoice(restoreMethodToken: token)
        } catch {
            logger.error("Failed to wait for restore method choice: \(error)")
            throw DeviceRestoreError.invalidRestoreData
        }

        switch restoreMethod {
        case .localBackup, .remoteBackup, .decline:
            break
        case .deviceTransfer(let transferUrl):
            let factory: DeviceTransfer.ConnectionFactory
            if
                #available(iOS 26.0, *),
                provisioningURL.capabilities.contains(.wifiaware),
                DeviceTransfer.platformSupportsWifiAware(),
                RemoteConfig.current.wifiAwareDeviceTransferEnabled
            {
                transferStatusViewModel.supportsWifiAware = true
                factory = WADeviceTransferConnectionFactory()
            } else {
                factory = MPCDeviceTransferConnectionFactory()
            }

            let outgoingDeviceTransferTask = try OutgoingDeviceTransferTask(
                deviceTransferURL: transferUrl,
                db: db,
                deviceSleepManager: deviceSleepManager,
                deviceTransferConnectionFactory: factory,
                registrationStateChangeManager: registrationStateChangeManager,
                tsAccountManager: tsAccountManager,
            )
            if let peer = outgoingDeviceTransferTask.selectedPeer {
                transferStatusViewModel.selectedPeer = peer
            }

            self.pairedPeersListenerTask = Task {
                for try await peer in outgoingDeviceTransferTask.pairedPeerStream {
                    transferStatusViewModel.onPeerDiscovered(peer)
                }
            }

            self.discoveredPeersListenerTask = Task {
                for try await peers in outgoingDeviceTransferTask.discoveredPeerStream {
                    transferStatusViewModel.discoveredPeers = peers
                }
            }

            self.outgoingDeviceTransferTask = outgoingDeviceTransferTask
        }

        return restoreMethod
    }

    /// Take the `PeerConnectionData` returned by `waitForConnectionData` and
    /// begin listening for the connection described in `PeerConnectionData`.
    @MainActor
    func waitForDeviceConnection(peer: any DeviceTransfer.Peer) async throws {
        logger.info("")
        guard let outgoingDeviceTransferTask else {
            throw OWSAssertionError("Transfer started before negotiating connection")
        }
        // If in any state but .idle, return
        guard case .idle = transferStatusViewModel.state else {
            return
        }

        transferStatusViewModel.state = .connecting

        // Wait for messages to process, then suspend processing
        try await messageProcessor.waitForFetchingAndProcessing()
        messagePipelineSupervisor.suspendMessageProcessingWithoutHandle(for: .deviceTransfer)

        do {
            try await outgoingDeviceTransferTask.connectToNewDevice(peer: peer)
        } catch {
            // If an error is encountered, unsuspend message processing since the user may
            // give up on transferring and go back to using the app as normal
            messagePipelineSupervisor.unsuspendMessageProcessing(for: .deviceTransfer)
            throw error
        }
    }

    /// Once connected to the device described in `PeerConnectionData`
    /// begin a device transfer.
    @MainActor
    func startTransfer() async throws {
        logger.info("")
        self.pairedPeersListenerTask.take()?.cancel()
        guard let outgoingDeviceTransferTask else {
            throw OWSAssertionError("Transfer started before negotiating connection")
        }
        defer {
            messagePipelineSupervisor.unsuspendMessageProcessing(for: .deviceTransfer)
            Task {
                await stopListeningForTransfer(error: nil)
            }
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
            logger.error("Failed transfer to new device \(error)")
            transferStatusViewModel.state = .error(error)
            throw error
        }
    }

    @MainActor
    private func cancelTransfer() async {
        self.pairedPeersListenerTask.take()?.cancel()
        self.discoveredPeersListenerTask.take()?.cancel()
        self.waitForPeerContinuation.swap(nil)?.resume(throwing: CancellationError())
        await stopListeningForTransfer(error: CancellationError())
        transferStatusViewModel.state = .cancelled
    }

    @MainActor
    private func stopListeningForTransfer(error: Error?) async {
        await outgoingDeviceTransferTask?.stop(error: error)
    }

    private var progressObserver: NSKeyValueObservation?
    private func updateProgress(progress: Progress) {
        self.progressObserver = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, change in
            Task { @MainActor in
                let newValue = change.newValue ?? 0
                // A fuzzy check that the file transfer has completed and the transfer is finializing
                if newValue >= 1.0 {
                    self?.transferStatusViewModel.state = .finishing
                } else {
                    self?.transferStatusViewModel.state = .transferring(newValue)
                }
            }
        }
    }
}
