//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity
import SignalMessaging

public class Deprecated_OnboardingTransferQRCodeViewController: Deprecated_OnboardingBaseViewController {

    private let qrCodeView = QRCodeView()

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.createTitleLabel(
            text: OWSLocalizedString("DEVICE_TRANSFER_QRCODE_TITLE",
                                    comment: "The title for the device transfer qr code view")
        )
        primaryView.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.transferQRCode.titleLabel"
        titleLabel.setContentHuggingHigh()

        let explanationLabel = self.createExplanationLabel(
            explanationText: OWSLocalizedString("DEVICE_TRANSFER_QRCODE_EXPLANATION",
                                               comment: "The explanation for the device transfer qr code view")
        )
        explanationLabel.accessibilityIdentifier = "onboarding.transferQRCode.bodyLabel"
        explanationLabel.setContentHuggingHigh()

        qrCodeView.setContentHuggingVerticalLow()

        let explanationLabel2 = self.createExplanationLabel(
            explanationText: OWSLocalizedString("DEVICE_TRANSFER_QRCODE_EXPLANATION2",
            comment: "The second explanation for the device transfer qr code view")
        )
        explanationLabel2.setContentHuggingHigh()

        let helpButton = self.linkButton(
            title: OWSLocalizedString(
                "DEVICE_TRANSFER_QRCODE_NOT_SEEING",
                comment: "A prompt to provide further explanation if the user is not seeing the transfer on both devices."
            ),
            selector: #selector(didTapHelp)
        )
        helpButton.button.titleLabel?.textAlignment = .center
        helpButton.button.titleLabel?.numberOfLines = 0
        helpButton.button.titleLabel?.lineBreakMode = .byWordWrapping

        let cancelButton = self.linkButton(title: CommonStrings.cancelButton, selector: #selector(didTapCancel))

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            qrCodeView,
            explanationLabel2,
            UIView.vStretchingSpacer(),
            helpButton,
            cancelButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12
        primaryView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        deviceTransferService.addObserver(self)

        do {
            let url = try deviceTransferService.startAcceptingTransfersFromOldDevices(
                mode: onboardingController.onboardingMode == .provisioning ? .linked : .primary
            )
            try qrCodeView.setQR(url: url)
        } catch {
            owsFailDebug("error \(error)")
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        deviceTransferService.removeObserver(self)
        deviceTransferService.stopAcceptingTransfersFromOldDevices()
    }

    // MARK: - Events

    weak var permissionActionSheetController: ActionSheetController?

    @objc
    private func didTapHelp() {
        let turnOnView = TurnOnPermissionView(
            title: OWSLocalizedString(
                "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_TITLE",
                comment: "Title for local network permission action sheet"
            ),
            message: OWSLocalizedString(
                "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_BODY",
                comment: "Body for local network permission action sheet"
            ),
            steps: [
                .init(
                    icon: #imageLiteral(resourceName: "settings-app-icon-32"),
                    text: OWSLocalizedString(
                        "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_STEP_ONE",
                        comment: "First step for local network permission action sheet"
                    )
                ),
                .init(
                    icon: #imageLiteral(resourceName: "AppIcon"),
                    text: OWSLocalizedString(
                        "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_STEP_TWO",
                        comment: "Second step for local network permission action sheet"
                    )
                ),
                .init(
                    icon: #imageLiteral(resourceName: "toggle-32"),
                    text: OWSLocalizedString(
                        "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_STEP_THREE",
                        comment: "Third step for local network permission action sheet"
                    )
                )
            ],
            button: primaryButton(
                title: OWSLocalizedString(
                    "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_NEED_HELP",
                    comment: "A button asking the user if they need further help getting their transfer working."
                ),
                selector: #selector(didTapContactSupport)
            )
        )

        let actionSheetController = ActionSheetController()
        permissionActionSheetController = actionSheetController
        actionSheetController.customHeader = turnOnView
        actionSheetController.isCancelable = true
        presentActionSheet(actionSheetController)
    }

    @objc
    private func didTapCancel() {
        Logger.info("")

        guard let navigationController = navigationController else {
            return owsFailDebug("unexpectedly missing nav controller")
        }

        onboardingController.pushStartDeviceRegistrationView(onto: navigationController)
    }

    @objc
    private func didTapContactSupport() {
        Logger.info("")

        permissionActionSheetController?.dismiss(animated: true)
        permissionActionSheetController = nil

        ContactSupportAlert.presentStep2(
            emailSupportFilter: "Signal iOS Transfer",
            fromViewController: self
        )
    }

    override func shouldShowBackButton() -> Bool {
        // Never show the back button here
        return false
    }
}

extension Deprecated_OnboardingTransferQRCodeViewController: DeviceTransferServiceObserver {
    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?) {}

    func deviceTransferServiceDidStartTransfer(progress: Progress) {
        onboardingController.accountTransferInProgress(fromViewController: self, progress: progress)
    }

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {
        if let error = error {
            owsFailDebug("unexpected error while rendering QR code \(error)")
        }
    }
}
