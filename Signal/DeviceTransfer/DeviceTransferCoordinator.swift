//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// DeviceTransferCoordinator manages high-level orchestration of the device transfer flow,
/// using a TransferStatusViewModel passed to the UI that drives progress and success/cancel behavior.
public class DeviceTransferCoordinator: Equatable {

    let transferStatusViewModel = TransferStatusViewModel()

    private let incomingDeviceTransferTask: IncomingDeviceTransferTask
    private let quickRestoreManager: QuickRestoreManager
    private let restoreMethodToken: String
    private let restoreMode: DeviceTransfer.Mode

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
            await stopAcceptingTransfers()
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
        stopAcceptingTransfers()
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
        stopAcceptingTransfers()
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
    ) {
        self.quickRestoreManager = quickRestoreManager
        self.restoreMethodToken = restoreMethodToken
        self.restoreMode = restoreMode

        self.incomingDeviceTransferTask = IncomingDeviceTransferTask(
            db: db,
            deviceSleepManager: deviceSleepManager,
            deviceTransferRestore: deviceTransferRestore,
            registrationStateChangeManager: registrationStateChangeManager,
            tsAccountManager: tsAccountManager,
        )

        self.cancelTransferBlock = _onCancelTransfer
        self.onSuccess = _onSuccess
        self.onFailure = _onFailure
    }

    @MainActor
    public func start() async throws {
        transferStatusViewModel.state = .starting

        let url = try await incomingDeviceTransferTask.start(mode: restoreMode)
        let transferData = url.absoluteString.data(using: .utf8)!.base64EncodedStringWithoutPadding()

        try await quickRestoreManager.reportRestoreMethodChoice(
            method: .deviceTransfer(transferData),
            restoreMethodToken: restoreMethodToken,
        )

        do {
            try await incomingDeviceTransferTask.waitForTransferFromOldDevice { [weak self] progress in
                self?.initializeProgressTracking(progress: progress)
            }

            transferStatusViewModel.state = .done
            transferStatusViewModel.onSuccess()
        } catch {
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

    private func updateStatus(value: Double) {
        transferStatusViewModel.state = .transferring(value)
    }

    @MainActor
    private func cancelTransfer() async {
        incomingDeviceTransferTask.cancelTransferFromOldDevice()
    }

    @MainActor
    public func stopAcceptingTransfers() {
        incomingDeviceTransferTask.stopAcceptingTransfersFromOldDevices()
    }

    public static func ==(lhs: DeviceTransferCoordinator, rhs: DeviceTransferCoordinator) -> Bool {
        lhs.restoreMethodToken == rhs.restoreMethodToken
    }
}
