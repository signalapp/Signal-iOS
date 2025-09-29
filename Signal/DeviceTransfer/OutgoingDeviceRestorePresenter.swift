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

final class OutgoingDeviceRestorePresenter: OutgoingDeviceRestoreInitialPresenter {

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
            hero: .image(UIImage(named: "other-device")!),
            title: OWSLocalizedString(
                "OUTGOING_DEVICE_RESTORE_CONTINUE_ON_OTHER_DEVICE_TITLE",
                comment: "Title of prompt notifying that action is necessary on the other device."
            ),
            body: OWSLocalizedString(
                "OUTGOING_DEVICE_RESTORE_CONTINUE_ON_OTHER_DEVICE_BODY",
                comment: "Body of prompt notifying that action is necessary on the other device."
            ),
            primary: .hero(.animation(named: "circular_indeterminate", height: 60))
        )
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
    private func displayTransferComplete(presentingViewController: UIViewController) async {
        let sheet = HeroSheetViewController(
            hero: .image(UIImage(resource: .checkCircle)),
            title: OWSLocalizedString(
                "OUTGOING_DEVICE_TRANSFER_COMPLETE_TITLE",
                comment: "Title of prompt notifying device transfer completed."
            ),
            body: OWSLocalizedString(
                "OUTGOING_DEVICE_TRANSFER_COMPLETE_BODY",
                comment: "Body of prompt notifying device transfer completed."
            ),
            primaryButton: .dismissing(title: CommonStrings.okayButton)
        )
        await presentingViewController.awaitablePresent(sheet, animated: true)
    }

    @MainActor
    private func displayRestoreMessage(isBackup: Bool, presentingViewController: UIViewController) async {

        let (title, body) = if isBackup {
            (
                OWSLocalizedString(
                    "OUTGOING_DEVICE_RESTORE_COMPLETE_TITLE",
                    comment: "Title of prompt notifying device restore started on the new device."
                ),
                OWSLocalizedString(
                    "OUTGOING_DEVICE_RESTORE_COMPLETE_BODY",
                    comment: "Body of prompt notifying device restore started on the new device."
                )
            )
        } else {
            (
                OWSLocalizedString(
                    "OUTGOING_DEVICE_REGISTRATION_COMPLETE_TITLE",
                    comment: "Title of prompt notifying registration without restore completed on the new device."
                ),
                OWSLocalizedString(
                    "OUTGOING_DEVICE_REGISTRATION_COMPLETE_BODY",
                    comment: "Body of prompt notifying registration without restore completed on the new device."
                )
            )
        }

        let sheet = HeroSheetViewController(
            hero: .image(UIImage(resource: .checkCircle)),
            title: title,
            body: body,
            primaryButton: .init(title: CommonStrings.okayButton, action: { _ in
                presentingViewController.dismiss(animated: false)
            })
        )
        await presentingViewController.presentedViewController?.awaitableDismiss(animated: true)
        await internalNavigationController.awaitablePresent(sheet, animated: true)
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

            guard await viewModel.confirmTransfer() else {
                // Silently fail here. The confirmTransfer UI will notify the user of
                // success/failure (e.g. FaceID UI)
                return
            }

            // Show a sheet while fetching the transfer data
            await presentSheet()
            let restoreMethodData = try await viewModel.waitForRestoreMethodResponse()

            switch restoreMethodData.restoreMethod {
            case .remoteBackup, .localBackup:
                await displayRestoreMessage(isBackup: true, presentingViewController: presentingViewController)
            case .decline:
                await displayRestoreMessage(isBackup: false, presentingViewController: presentingViewController)
            case .deviceTransfer:
                guard let peerConnectionData = restoreMethodData.peerConnectionData else {
                    Logger.error("Missing transfer connection data")
                    throw DeviceRestoreError.invalidRestoreData
                }

                // Push the status sheet if this is a transfer
                await pushProgressViewController(
                    viewModel: viewModel,
                    presentingViewController: presentingViewController
                )

                await viewModel.waitForDeviceConnection(peerConnectionData: peerConnectionData)
                Task { @MainActor [weak self] in
                    // TODO: [Backups] - DeviceTransferService does a db.write
                    // internally, and this should be updated to an actor/async aware
                    // in a followup piece of work (and possibly once the old device transfer
                    // flow is removed)
                    do {
                        try viewModel.startTransfer(peerConnectionData: peerConnectionData)
                    } catch {
                        Logger.warn("Device transfer failed: \(error)")
                        await self?.handleError(
                            DeviceRestoreError.unknownError,
                            presentingViewController: presentingViewController
                        )
                    }
                }
                let success = await viewModel.waitForTransferCompletion()
                if !success {
                    await handleError(
                        DeviceRestoreError.restoreCancelled,
                        presentingViewController: presentingViewController
                    )
                } else {
                    await displayTransferComplete(presentingViewController: presentingViewController)
                }
            }
        } catch {
            switch error {
            case let restoreError as DeviceRestoreError:
                await handleError(restoreError, presentingViewController: presentingViewController)
            default:
                Logger.error("Unexpected device transfer error: \(error)")
            }
        }
    }

    @MainActor
    func handleError(_ error: DeviceRestoreError, presentingViewController: UIViewController?) async {
        guard let presentingViewController else {
            Logger.warn("Cannot display transfer error")
            return
        }

        let (title, body) = switch error {
        case .invalidRestoreData: (
            OWSLocalizedString(
                "OUTGOING_DEVICE_REGISTRATION_FAILED_RESTORE_TITLE",
                comment: "Title of prompt notifying restore failed."
            ),
            OWSLocalizedString(
                "OUTGOING_DEVICE_REGISTRATION_FAILED_RESTORE_BODY",
                comment: "Body of prompt notifying restore failed."
            )
        )
        case .restoreCancelled: (
            OWSLocalizedString(
                "OUTGOING_DEVICE_REGISTRATION_CANCELLED_RESTORE_TITLE",
                comment: "Title of prompt notifying restore was cancelled."
            ),
            OWSLocalizedString(
                "OUTGOING_DEVICE_REGISTRATION_CANCELLED_RESTORE_BODY",
                comment: "Body of prompt notifying restore was cancelled."
            )
        )
        case .unknownError: (
            OWSLocalizedString(
                "OUTGOING_DEVICE_REGISTRATION_UNKNOWN_ERROR_TITLE",
                comment: "Title of prompt notifying restore failed for unknown reasons."
            ),
            OWSLocalizedString(
                "OUTGOING_DEVICE_REGISTRATION_UNKNOWN_ERROR_BODY",
                comment: "Body of prompt notifying restore failed for unknown reasons."
            )
        )
        }

        let sheet = HeroSheetViewController(
            hero: .image(UIImage(resource: .checkCircle)),
            title: title,
            body: body,
            primaryButton: .init(title: CommonStrings.okayButton, action: { _ in
                presentingViewController.dismiss(animated: true)
            })
        )
        await presentingViewController.awaitableDismiss(animated: true)
        await presentingViewController.awaitablePresent(sheet, animated: true)
    }
}
