//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

// These notifications tell the rest of the app that an outgoing restore is now in flight. This mainly
// allows for disabling ConversationSplitViewControllers habit of listening for the old style device transfer
// These could be removed once that functionality is deprecated and removed
extension Notification.Name {
    static let outgoingDeviceTransferDidStart = Notification.Name("OutgoingDeviceTransferDidStartNotification")
    static let outgoingDeviceTransferDidEnd = Notification.Name("OutgoingDeviceTransferDidEndNotification")
}

class OutgoingDeviceRestorePresenter: OutgoingDeviceRestoreInitialPresenter {

    private let internalNavigationController = OWSNavigationController()
    private let deviceTransferService: DeviceTransferService
    private let quickRestoreManager: QuickRestoreManager

    private var viewModel: OutgoingDeviceRestoreViewModel?
    private var presentingViewController: UIViewController?

    init(
        deviceTransferService: DeviceTransferService,
        quickRestoreManager: QuickRestoreManager
    ) {
        self.deviceTransferService = deviceTransferService
        self.quickRestoreManager = quickRestoreManager
    }

    func present(
        provisioningURL: DeviceProvisioningURL,
        presentingViewController: UIViewController,
        animated: Bool
    ) {
        self.viewModel = OutgoingDeviceRestoreViewModel(
            deviceTransferService: deviceTransferService,
            quickRestoreManager: quickRestoreManager,
            deviceProvisioningURL: provisioningURL
        )

        internalNavigationController.pushViewController(
            OutgoingDeviceRestoreIntialViewController(presenter: self),
            animated: false
        )

        self.presentingViewController = presentingViewController
        presentingViewController.present(internalNavigationController, animated: true)
    }

    @MainActor
    private func presentSheet() {
        let sheet = HeroSheetViewController(
            hero: .image(UIImage(named: "transfer_account")!),
            // TODO: [Backups] - Localize
            title: LocalizationNotNeeded("Continue on your other device"),
            body: LocalizationNotNeeded("Continue transferring your account on your other device."),
            primary: .hero(.animation(named: "circular_indeterminate", height: 60))
        )
        sheet.modalPresentationStyle = .formSheet
        internalNavigationController.present(sheet, animated: true)
    }

    @MainActor
    private func pushProgressViewController(
        viewModel: OutgoingDeviceRestoreViewModel,
        presentingViewController: UIViewController
    ) async {
        await internalNavigationController.awaitableDismiss(animated: false)
        await presentingViewController.awaitableDismiss(animated: true)
        await presentingViewController.awaitablePresent(
            OutgoingDeviceRestoreProgressViewController(viewModel: viewModel.transferStatusViewModel),
            animated: true
        )
    }

    @MainActor
    private func displayComplete(presentingViewController: UIViewController) async {
        let sheet = HeroSheetViewController(
            hero: .image(UIImage(resource: .checkCircle)),
            // TODO: [Backups] - Localize
            title: LocalizationNotNeeded("Transfer complete"),
            body: LocalizationNotNeeded("Your Signal account and messages have been transferred to your other device. Signal is now inactive on this device."),
            primaryButton: .dismissing(title: "Okay")
        )
        sheet.modalPresentationStyle = .formSheet
        await presentingViewController.awaitablePresent(sheet, animated: true)
    }

    @MainActor
    private func displayStartedRestore() {
        // TODO: [Backups] - Show the 'Restore complete'
    }

    @MainActor
    private func displaySkippedRestore() {
        // TODO: [Backups] - Show the 'Registration finished complete'
    }

    func didTapTransfer() async {
        NotificationCenter.default.post(name: .outgoingDeviceTransferDidStart, object: self)
        defer {
            NotificationCenter.default.post(name: .outgoingDeviceTransferDidEnd, object: self)
        }
        do {
            guard
                let viewModel,
                let presentingViewController
            else {
                // This was called before setting up the transfer.
                return
            }

            await viewModel.confirmTransfer()

            // Show a sheet while fetching the transfer data
            await presentSheet()
            let connectionData = try await viewModel.waitForConnectionData()

            switch connectionData.restoreMethod {
            case .remoteBackup, .localBackup:
                await displayStartedRestore()
            case .decline:
                await displaySkippedRestore()
            case .deviceTransfer:

                // Push the status sheet if this is a transfer
                await pushProgressViewController(
                    viewModel: viewModel,
                    presentingViewController: presentingViewController
                )

                await viewModel.waitForDeviceConnection(connectionData: connectionData)
                Task { @MainActor in
                    // TODO: [Backups] - DeviceTransferService does a db.write
                    // internally, and this should be updated to an actor/async aware
                    // in a followup piece of work (and possibly once the old device transfer
                    // flow is removed)
                    try viewModel.startTransfer(connectionData: connectionData)
                }
                await viewModel.waitForTransferCompletion()

                await displayComplete(presentingViewController: presentingViewController)
            }
        } catch {
            // TODO: [Backups] - Display an error
            Logger.error("error: \(error)")
        }
    }
}
