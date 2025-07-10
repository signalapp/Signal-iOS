//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import MultipeerConnectivity

class OutgoingDeviceRestoreViewModel: ObservableObject, DeviceTransferServiceObserver {

    struct RestoreMethodData {
        struct PeerConnectionData {
            var peerId: MCPeerID
            var certificateHash: Data
        }

        public let restoreMethod: QuickRestoreManager.RestoreMethodType
        public let peerConnectionData: PeerConnectionData?

        fileprivate init(restoreMethod: QuickRestoreManager.RestoreMethodType, peerConnectionData: PeerConnectionData?) {
            self.restoreMethod = restoreMethod
            self.peerConnectionData = peerConnectionData
        }
    }

    private(set) var transferStatusViewModel = TransferStatusViewModel()
    private let deviceTransferService: DeviceTransferService
    private let quickRestoreManager: QuickRestoreManager
    private let provisioningURL: DeviceProvisioningURL

    private var deviceConnectedContinuation: AtomicValue<(
        continuation: CheckedContinuation<Void, Never>,
        peerConnectionData: RestoreMethodData.PeerConnectionData
    )?> = AtomicValue(nil, lock: .init())

    private var finishTransferContinuation: AtomicValue<
        CheckedContinuation<Void, Never>?
    > = AtomicValue(nil, lock: .init())

    init(
        deviceTransferService: DeviceTransferService,
        quickRestoreManager: QuickRestoreManager,
        deviceProvisioningURL: DeviceProvisioningURL,
    ) {
        self.deviceTransferService = deviceTransferService
        self.quickRestoreManager = quickRestoreManager
        self.provisioningURL = deviceProvisioningURL
    }

    func confirmTransfer() async -> Bool {
        return await LocalDeviceAuthentication().performBiometricAuth()
    }

    /// This uses the QuickRestore path behind the scenes to bootstrap a device transfer between two devices.
    /// 1. Outgoing device scans the QR code, then sends a RegistrationProvisioningMessage to the device that displayed the QR.
    /// 2. Outgoing device will wait for the restore method choice from the other device.
    /// 3. Confirm the returned choice is 'device transfer' or fail.
    /// 4. Parse out the MPC connection information returned in the restore method choice, and return this connection data
    func waitForRestoreMethodResponse() async throws -> RestoreMethodData {
        let restoreMethodToken = try await quickRestoreManager.register(deviceProvisioningUrl: provisioningURL)
        let restoreMethod = try await quickRestoreManager.waitForRestoreMethodChoice(restoreMethodToken: restoreMethodToken)
        guard case let .deviceTransfer(transferData) = restoreMethod else {
            return RestoreMethodData(restoreMethod: restoreMethod, peerConnectionData: nil)
        }
        guard
            let stringData = Data(base64EncodedWithoutPadding: transferData),
            let urlString = String(data: stringData, encoding: .utf8),
            let transferURL = URL(string: urlString)
        else {
            throw OWSAssertionError("Attempting to restore using a method other than device transfer")
        }

        do {
            let (peerId, certificateHash) = try deviceTransferService.parseTransferURL(transferURL)
            return RestoreMethodData(
                restoreMethod: restoreMethod,
                peerConnectionData: RestoreMethodData.PeerConnectionData(
                    peerId: peerId,
                    certificateHash: certificateHash
                )
            )
        } catch {
            Logger.error("Failed to register device via URL: \(error)")
            throw error
        }
    }

    /// Take the `PeerConnectionData` returned by `waitForConnectionData` and
    /// begin listening for the connection described in `PeerConnectionData`.
    func waitForDeviceConnection(peerConnectionData: RestoreMethodData.PeerConnectionData) async {
        // If in any state but .idle, return
        guard case .idle = transferStatusViewModel.state else {
            return
        }
        return await withCheckedContinuation { continuation in
            // Update with "Waiting to connect to new iPhone" message
            deviceConnectedContinuation.update { existingContinuation in
                transferStatusViewModel.state = .starting
                existingContinuation = (continuation, peerConnectionData)
            }

            deviceTransferService.startListeningForNewDevices()
            deviceTransferService.addObserver(self)
        }
    }

    /// Once connected to the device described in `PeerConnectionData`
    /// begin a device transfer.
    func startTransfer(peerConnectionData: RestoreMethodData.PeerConnectionData) throws {
        do {
            try deviceTransferService.transferAccountToNewDevice(
                with: peerConnectionData.peerId,
                certificateHash: peerConnectionData.certificateHash
            )
        } catch {
            stopListeningForTransfer()
            Logger.error("Failed transfer to new device")
            throw error
        }
    }

    func waitForTransferCompletion() async {
        return await withCheckedContinuation { continuation in
            self.finishTransferContinuation.update {
                switch transferStatusViewModel.state {
                case .done, .error:
                    // If the transfer is finished, just return
                    continuation.resume()
                    return
                case .connecting, .idle, .starting, .transferring:
                    break
                }
                $0 = continuation
            }
        }
    }

    private func stopListeningForTransfer() {
        deviceTransferService.removeObserver(self)
        deviceTransferService.stopListeningForNewDevices()
    }

    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?) {
        deviceConnectedContinuation.update { existingContinuation in
            guard peerId == existingContinuation?.peerConnectionData.peerId else {
                // Don't resume the continuation if we got a notification for a different peerId
                return
            }
            transferStatusViewModel.state = .connecting
            existingContinuation?.continuation.resume()
            // Successfully discovered the expected peer, clear the continuation
            existingContinuation = nil
        }
    }

    private var progressObserver: NSKeyValueObservation?
    func deviceTransferServiceDidStartTransfer(progress: Progress) {
        self.progressObserver = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, change in
            Task { @MainActor in
                let newValue = change.newValue ?? 0
                self?.transferStatusViewModel.state = .transferring(newValue)
            }
        }
    }

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {
        stopListeningForTransfer()
        finishTransferContinuation.update { continuation in
            if let error {
                transferStatusViewModel.state = .error(error)
            } else {
                transferStatusViewModel.state = .done
            }
            continuation?.resume()
            continuation = nil
        }
    }

    func deviceTransferServiceDidRequestAppRelaunch() { }
}
