//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity
import SignalServiceKit

public class RegistrationTransferStatusState: DeviceTransferServiceObserver, Equatable {
    let transferStatusViewModel = TransferStatusViewModel()

    private let deviceTransferService: RegistrationCoordinatorImpl.Shims.DeviceTransferService
    private let quickRestoreManager: RegistrationCoordinatorImpl.Shims.QuickRestoreManager
    private let restoreMethodToken: String

    public var onCancel: (() -> Void) {
        get {
            transferStatusViewModel.onCancel
        }
        set {
            transferStatusViewModel.onCancel = { [weak self] in
                self?.stopAcceptingTransfers()
                self?.cancelTransfer()
                newValue()
            }
        }
    }

    public var onSuccess: (() -> Void) {
        get {
            transferStatusViewModel.onSuccess
        }
        set {
            transferStatusViewModel.onSuccess = { [weak self] in
                self?.stopAcceptingTransfers()
                newValue()
            }
        }
    }

    init(
        deviceTransferService: RegistrationCoordinatorImpl.Shims.DeviceTransferService,
        quickRestoreManager: RegistrationCoordinatorImpl.Shims.QuickRestoreManager,
        restoreMethodToken: String
    ) {
        self.deviceTransferService = deviceTransferService
        self.quickRestoreManager = quickRestoreManager
        self.restoreMethodToken = restoreMethodToken
    }

    public func start() async throws {
        transferStatusViewModel.state = .starting
        deviceTransferService.addObserver(self)
        let url = try deviceTransferService.startAcceptingTransfersFromOldDevices(mode: .primary)
        let transferData = url.absoluteString.data(using: .utf8)!.base64EncodedStringWithoutPadding()

        try await quickRestoreManager.reportRestoreMethodChoice(
            method: .deviceTransfer(transferData),
            restoreMethodToken: restoreMethodToken
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

    public static func == (lhs: RegistrationTransferStatusState, rhs: RegistrationTransferStatusState) -> Bool {
        lhs.restoreMethodToken == rhs.restoreMethodToken
    }
}
