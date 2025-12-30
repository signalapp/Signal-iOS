//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity
import SignalServiceKit

/// DeviceTransferCoordinator manages high-level orchestration of the device transfer flow,
/// using a TransferStatusViewModel passed to the UI that drives progress and success/cancel behavior.
public class DeviceTransferCoordinator: DeviceTransferServiceObserver, Equatable {

    let transferStatusViewModel = TransferStatusViewModel()

    private let deviceTransferService: any DeviceTransferServiceProtocol
    private let quickRestoreManager: QuickRestoreManager
    private let restoreMethodToken: String
    private let restoreMode: DeviceTransferService.TransferMode

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
        stopAcceptingTransfers()
        cancelTransfer()
    }

    public var onSuccess: () -> Void {
        get { transferStatusViewModel.onSuccess }
        set {
            transferStatusViewModel.onSuccess = { [weak self] in
                self?._onSuccess()
                newValue()
            }
        }
    }

    private func _onSuccess() {
        stopAcceptingTransfers()
    }

    public var onFailure: (Error) -> Void {
        get { transferStatusViewModel.onFailure }
        set { transferStatusViewModel.onFailure = { [weak self] error in
            self?._onFailure(error)
            newValue(error)
        }
        }
    }

    private func _onFailure(_ error: Error) {
        stopAcceptingTransfers()
    }

    init(
        deviceTransferService: DeviceTransferServiceProtocol,
        quickRestoreManager: QuickRestoreManager,
        restoreMethodToken: String,
        restoreMode: DeviceTransferService.TransferMode,
    ) {
        self.deviceTransferService = deviceTransferService
        self.quickRestoreManager = quickRestoreManager
        self.restoreMethodToken = restoreMethodToken
        self.restoreMode = restoreMode

        self.cancelTransferBlock = _onCancelTransfer
        self.onSuccess = _onSuccess
        self.onFailure = _onFailure
    }

    public func start() async throws {
        transferStatusViewModel.state = .starting
        deviceTransferService.addObserver(self)
        let url = try deviceTransferService.startAcceptingTransfersFromOldDevices(mode: restoreMode)
        let transferData = url.absoluteString.data(using: .utf8)!.base64EncodedStringWithoutPadding()

        try await quickRestoreManager.reportRestoreMethodChoice(
            method: .deviceTransfer(transferData),
            restoreMethodToken: restoreMethodToken,
        )
    }

    private func cancelTransfer() {
        deviceTransferService.cancelTransferFromOldDevice()
    }

    public func stopAcceptingTransfers() {
        deviceTransferService.removeObserver(self)
        deviceTransferService.stopAcceptingTransfersFromOldDevices()
    }

    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?) {
        transferStatusViewModel.state = .connecting
    }

    private var progressObserver: NSKeyValueObservation?
    func deviceTransferServiceDidStartTransfer(progress: Progress) {
        self.progressObserver = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async {
                let newValue = change.newValue ?? 0
                self?.transferStatusViewModel.state = .transferring(newValue)
            }
        }
    }

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {
        if let error {
            transferStatusViewModel.state = .error(error)
        } else {
            transferStatusViewModel.state = .done
        }
    }

    func deviceTransferServiceDidRequestAppRelaunch() {
        transferStatusViewModel.onSuccess()
    }

    public static func ==(lhs: DeviceTransferCoordinator, rhs: DeviceTransferCoordinator) -> Bool {
        lhs.restoreMethodToken == rhs.restoreMethodToken
    }
}
