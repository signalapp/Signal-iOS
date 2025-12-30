//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MultipeerConnectivity
import SignalServiceKit
public import SignalUI
import UIKit

public class RegistrationTransferProgressViewController: OWSViewController {

    let progressView: TransferProgressView

    public init(progress: Progress) {
        self.progressView = TransferProgressView(progress: progress)

        super.init()

        navigationItem.hidesBackButton = true
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        let titleLabel = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "DEVICE_TRANSFER_RECEIVING_TITLE",
                comment: "The title on the view that shows receiving progress",
            ),
        )
        titleLabel.accessibilityIdentifier = "onboarding.transferProgress.titleLabel"

        let explanationLabel = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "DEVICE_TRANSFER_RECEIVING_EXPLANATION",
                comment: "The explanation on the view that shows receiving progress",
            ),
        )
        explanationLabel.accessibilityIdentifier = "onboarding.transferProgress.bodyLabel"

        let cancelButton = UIButton(
            configuration: .mediumSecondary(title: CommonStrings.cancelButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapCancel()
            },
        )

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        addStaticContentStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            topSpacer,
            progressView,
            bottomSpacer,
            cancelButton.enclosedInVerticalStackView(isFullWidthButton: false),
        ])
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor).isActive = true
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        progressView.startUpdatingProgress()

        AppEnvironment.shared.deviceTransferServiceRef.addObserver(self)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        progressView.stopUpdatingProgress()

        AppEnvironment.shared.deviceTransferServiceRef.removeObserver(self)
        AppEnvironment.shared.deviceTransferServiceRef.cancelTransferFromOldDevice()
    }

    // MARK: - Events

    func didTapCancel() {
        Logger.info("")

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "DEVICE_TRANSFER_CANCEL_CONFIRMATION_TITLE",
                comment: "The title of the dialog asking the user if they want to cancel a device transfer",
            ),
            message: OWSLocalizedString(
                "DEVICE_TRANSFER_CANCEL_CONFIRMATION_MESSAGE",
                comment: "The message of the dialog asking the user if they want to cancel a device transfer",
            ),
        )
        actionSheet.addAction(OWSActionSheets.cancelAction)

        let okAction = ActionSheetAction(
            title: OWSLocalizedString(
                "DEVICE_TRANSFER_CANCEL_CONFIRMATION_ACTION",
                comment: "The stop action of the dialog asking the user if they want to cancel a device transfer",
            ),
            style: .destructive,
        ) { [weak self] _ in
            // viewWillDissapear will cancel the transfer
            self?.navigationController?.popViewController(animated: true)
        }
        actionSheet.addAction(okAction)

        present(actionSheet, animated: true)
    }
}

extension RegistrationTransferProgressViewController: DeviceTransferServiceObserver {
    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?) {}

    func deviceTransferServiceDidStartTransfer(progress: Progress) {}

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {
        guard let error else { return }

        switch error {
        case .assertion:
            progressView.renderError(
                text: OWSLocalizedString(
                    "DEVICE_TRANSFER_ERROR_GENERIC",
                    comment: "An error indicating that something went wrong with the transfer and it could not complete",
                ),
            )
        case .backgroundedDevice:
            progressView.renderError(
                text: OWSLocalizedString(
                    "DEVICE_TRANSFER_ERROR_BACKGROUNDED",
                    comment: "An error indicating that the other device closed signal mid-transfer and it could not complete",
                ),
            )
        case .cancel:
            // User initiated, nothing to do
            break
        case .certificateMismatch:
            owsFailDebug("This should never happen on the new device")
        case .notEnoughSpace:
            progressView.renderError(
                text: OWSLocalizedString(
                    "DEVICE_TRANSFER_ERROR_NOT_ENOUGH_SPACE",
                    comment: "An error indicating that the user does not have enough free space on their device to complete the transfer",
                ),
            )
        case .unsupportedVersion:
            progressView.renderError(
                text: OWSLocalizedString(
                    "DEVICE_TRANSFER_ERROR_UNSUPPORTED_VERSION",
                    comment: "An error indicating the user must update their device before trying to transfer.",
                ),
            )
        case .modeMismatch:
            owsFailDebug("This should never happen on the new device")
        }
    }

    func deviceTransferServiceDidRequestAppRelaunch() {
        self.present(TransferRelaunchSheet(), animated: true)
    }
}

private class TransferRelaunchSheet: HeroSheetViewController {
    override var canBeDismissed: Bool { false }

    init() {
        super.init(
            hero: .image(UIImage(named: "transfer_complete")!),
            title: OWSLocalizedString(
                "TRANSFER_COMPLETE_SHEET_TITLE",
                comment: "Title for bottom sheet shown when device transfer completes on the receiving device.",
            ),
            body: OWSLocalizedString(
                "TRANSFER_COMPLETE_SHEET_SUBTITLE",
                comment: "Subtitle for bottom sheet shown when device transfer completes on the receiving device.",
            ),
            primaryButton: .init(title: OWSLocalizedString(
                "TRANSFER_COMPLETE_SHEET_BUTTON",
                comment: "Button for bottom sheet shown when device transfer completes on the receiving device. Tapping will terminate the Signal app and trigger a notification to relaunch.",
            )) { _ in
                Self.didTapExitButton()
            },
        )
    }

    private static func didTapExitButton() {
        Logger.info("")
        SSKEnvironment.shared.notificationPresenterRef.notifyUserToRelaunchAfterTransfer {
            Logger.info("Deliberately terminating app post-transfer.")
            exit(0)
        }
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview("Transfer Progress") {
    return UINavigationController(
        rootViewController: RegistrationTransferProgressViewController(
            progress: .discreteProgress(totalUnitCount: 1024),
        ),
    )
}

@available(iOS 17, *)
#Preview("Relaunch Sheet") {
    return TransferRelaunchSheet()
}

#endif
