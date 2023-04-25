//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MultipeerConnectivity
import SignalMessaging
import UIKit

@objc
public class Deprecated_OnboardingTransferProgressViewController: Deprecated_OnboardingBaseViewController {

    let progressView: TransferProgressView

    public init(onboardingController: Deprecated_OnboardingController, progress: Progress) {
        self.progressView = TransferProgressView(progress: progress)
        super.init(onboardingController: onboardingController)
    }

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.createTitleLabel(
            text: OWSLocalizedString("DEVICE_TRANSFER_RECEIVING_TITLE",
                                    comment: "The title on the view that shows receiving progress")
        )
        primaryView.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.transferProgress.titleLabel"
        titleLabel.setContentHuggingHigh()

        let explanationLabel = self.createExplanationLabel(
            explanationText: OWSLocalizedString("DEVICE_TRANSFER_RECEIVING_EXPLANATION",
                                               comment: "The explanation on the view that shows receiving progress")
        )
        explanationLabel.accessibilityIdentifier = "onboarding.transferProgress.bodyLabel"
        explanationLabel.setContentHuggingHigh()

        let cancelButton = self.linkButton(title: CommonStrings.cancelButton, selector: #selector(didTapCancel))

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            topSpacer,
            progressView,
            bottomSpacer,
            cancelButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12
        primaryView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        progressView.startUpdatingProgress()

        deviceTransferService.addObserver(self)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        progressView.stopUpdatingProgress()

        deviceTransferService.removeObserver(self)
        deviceTransferService.cancelTransferFromOldDevice()
    }

    // MARK: - Events

    @objc
    func didTapCancel() {
        Logger.info("")

        guard let navigationController = navigationController else {
            return owsFailDebug("unexpectedly missing nav controller")
        }

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString("DEVICE_TRANSFER_CANCEL_CONFIRMATION_TITLE",
                                     comment: "The title of the dialog asking the user if they want to cancel a device transfer"),
            message: OWSLocalizedString("DEVICE_TRANSFER_CANCEL_CONFIRMATION_MESSAGE",
                                       comment: "The message of the dialog asking the user if they want to cancel a device transfer")
        )
        actionSheet.addAction(OWSActionSheets.cancelAction)

        let okAction = ActionSheetAction(
            title: OWSLocalizedString("DEVICE_TRANSFER_CANCEL_CONFIRMATION_ACTION",
                                     comment: "The stop action of the dialog asking the user if they want to cancel a device transfer"),
            style: .destructive
        ) { _ in
            self.onboardingController.pushStartDeviceRegistrationView(onto: navigationController)
        }
        actionSheet.addAction(okAction)

        present(actionSheet, animated: true)
    }

    override func shouldShowBackButton() -> Bool {
        // Never show the back button here
        return false
    }
}

extension Deprecated_OnboardingTransferProgressViewController: DeviceTransferServiceObserver {
    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?) {}

    func deviceTransferServiceDidStartTransfer(progress: Progress) {}

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {
        guard let error = error else { return }

        switch error {
        case .assertion:
            progressView.renderError(
                text: OWSLocalizedString("DEVICE_TRANSFER_ERROR_GENERIC",
                                        comment: "An error indicating that something went wrong with the transfer and it could not complete")
            )
        case .cancel:
            // User initiated, nothing to do
            break
        case .certificateMismatch:
            owsFailDebug("This should never happen on the new device")
        case .notEnoughSpace:
            progressView.renderError(
                text: OWSLocalizedString("DEVICE_TRANSFER_ERROR_NOT_ENOUGH_SPACE",
                                        comment: "An error indicating that the user does not have enough free space on their device to complete the transfer")
            )
        case .unsupportedVersion:
            progressView.renderError(
                text: OWSLocalizedString("DEVICE_TRANSFER_ERROR_UNSUPPORTED_VERSION",
                                        comment: "An error indicating the user must update their device before trying to transfer.")
            )
        case .modeMismatch:
            owsFailDebug("This should never happen on the new device")
        }
    }
}
