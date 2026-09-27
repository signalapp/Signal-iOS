//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// DeviceTransferCoordinator manages high-level orchestration of the device transfer flow,
/// using a TransferStatusViewModel passed to the UI that drives progress and success/cancel behavior.
public class DeviceTransferCoordinator: Equatable {
    private let logger = PrefixedLogger(prefix: "[DeviceTransfer][Incoming]")

    let transferStatusViewModel = TransferStatusViewModel()

    private let incomingDeviceTransferTask: IncomingDeviceTransferTask
    private let quickRestoreManager: QuickRestoreManager
    private let restoreMethodToken: String
    private let restoreMode: DeviceTransfer.Mode
    public let supportsWifiAware: Bool

    private var discoveredPeersListenerTask: Task<Void, Error>?

    var onTransferStart: (() -> Void) = { }

    @MainActor
    var pairedPeerStream: AsyncThrowingStream<any DeviceTransfer.Peer, Error> {
        incomingDeviceTransferTask.pairedPeerStream
    }

    public var confirmCancellation: () async -> Bool {
        get { transferStatusViewModel.confirmCancellation }
        set {
            transferStatusViewModel.confirmCancellation = newValue
        }
    }

    public var cancelTransferBlock: () -> Void {
        get { transferStatusViewModel.cancelTransferBlock }
        set {
            transferStatusViewModel.cancelTransferBlock = { [weak self] in
                self?._onCancelTransfer()
                newValue()
            }
        }
    }

    private func _onCancelTransfer() {
        Task {
            await cancelTransfer()
        }
    }

    public var onSuccess: @MainActor () -> Void {
        get { transferStatusViewModel.onSuccess }
        set {
            transferStatusViewModel.onSuccess = { @MainActor [weak self] in
                self?._onSuccess()
                newValue()
            }
        }
    }

    @MainActor
    private func _onSuccess() {
        Task {
            await stopAcceptingTransfers()
        }
    }

    @MainActor
    public var onFailure: @MainActor (Error) -> Void {
        get { transferStatusViewModel.onFailure }
        set { transferStatusViewModel.onFailure = { [weak self] error in
            self?._onFailure(error)
            newValue(error)
        }
        }
    }

    @MainActor
    private func _onFailure(_ error: Error) {
        Task {
            await stopAcceptingTransfers()
        }
    }

    @MainActor
    init(
        db: DB,
        deviceSleepManager: DeviceSleepManager?,
        deviceTransferRestore: DeviceTransferRestore,
        quickRestoreManager: QuickRestoreManager,
        registrationStateChangeManager: RegistrationStateChangeManager,
        restoreMethodToken: String,
        restoreMode: DeviceTransfer.Mode,
        tsAccountManager: TSAccountManager,
        supportsWifiAware: Bool,
    ) throws {
        self.quickRestoreManager = quickRestoreManager
        self.restoreMethodToken = restoreMethodToken
        self.restoreMode = restoreMode

        self.supportsWifiAware = supportsWifiAware
        self.transferStatusViewModel.supportsWifiAware = supportsWifiAware
        let factory: DeviceTransfer.ConnectionFactory
        if
            #available(iOS 26.0, *),
            supportsWifiAware
        {
            factory = WADeviceTransferConnectionFactory()
        } else {
            factory = MPCDeviceTransferConnectionFactory()
        }

        self.incomingDeviceTransferTask = try IncomingDeviceTransferTask(
            db: db,
            deviceSleepManager: deviceSleepManager,
            deviceTransferRestore: deviceTransferRestore,
            deviceTransferConnectionFactory: factory,
            registrationStateChangeManager: registrationStateChangeManager,
            tsAccountManager: tsAccountManager,
        )

        self.cancelTransferBlock = _onCancelTransfer
        self.onSuccess = _onSuccess
        self.onFailure = _onFailure

        self.discoveredPeersListenerTask = Task {
            for try await peers in incomingDeviceTransferTask.discoveredPeerStream {
                transferStatusViewModel.discoveredPeers = peers
            }
        }
    }

    @MainActor
    public func reportTransferMethodChoice() async throws {
        transferStatusViewModel.state = .starting

        let url = try await incomingDeviceTransferTask.start(mode: restoreMode)
        try await quickRestoreManager.reportRestoreMethodChoice(
            method: .deviceTransfer(url),
            restoreMethodToken: restoreMethodToken,
        )
    }

    /// Start listening for the old device to connect and begin the transfer.
    ///
    /// - Parameter peer: An optional peer that the new device prefers to connect to.  This allows connection layers like WiFiAware to listen
    /// specifically for this peer and ignore any others.
    @MainActor
    func waitForTransferFromPeer(peer: (any DeviceTransfer.Peer)?) async throws {
        do {
            try await incomingDeviceTransferTask.waitForTransferFromOldDevice(peer: peer) { [weak self] progress in
                self?.initializeProgressTracking(progress: progress)
            }
            logger.error("Transfer complete")

            transferStatusViewModel.state = .done
            transferStatusViewModel.onSuccess()
        } catch {
            logger.error("Error during device transfer: \(error)")
            transferStatusViewModel.state = .error(error)
        }
    }

    private var progressObserver: NSKeyValueObservation?
    private func initializeProgressTracking(progress: Progress) {
        self.progressObserver = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, change in
            let newValue = change.newValue ?? 0
            Task { @MainActor in
                self?.updateStatus(value: newValue)
            }
        }
    }

    private let hasTransferStarted = AtomicValue(false, lock: .init())
    private func updateStatus(value: Double) {
        if !hasTransferStarted.swap(true) {
            onTransferStart()
        }
        // A fuzzy check that the file transfer has completed and the transfer is finializing
        if value >= 1.0 {
            transferStatusViewModel.state = .finishing
        } else {
            transferStatusViewModel.state = .transferring(value)
        }
    }

    @MainActor
    private func cancelTransfer() async {
        await incomingDeviceTransferTask.cancelTransferFromOldDevice()
    }

    @MainActor
    public func stopAcceptingTransfers() async {
        await incomingDeviceTransferTask.stopAcceptingTransfersFromOldDevices()
        discoveredPeersListenerTask.take()?.cancel()
    }

    public static func ==(lhs: DeviceTransferCoordinator, rhs: DeviceTransferCoordinator) -> Bool {
        lhs.restoreMethodToken == rhs.restoreMethodToken
    }
}
