//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity
import SignalMessaging
import SignalUI

public class RegistrationTransferQRCodeViewController: OWSViewController {

    private let qrCodeView = QRCodeView()

    override public func loadView() {
        view = UIView()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString("DEVICE_TRANSFER_QRCODE_TITLE",
                                    comment: "The title for the device transfer qr code view")
        )
        view.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.transferQRCode.titleLabel"
        titleLabel.setContentHuggingHigh()

        let explanationLabel = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "DEVICE_TRANSFER_QRCODE_EXPLANATION",
                comment: "The explanation for the device transfer qr code view"
            )
        )
        explanationLabel.accessibilityIdentifier = "onboarding.transferQRCode.bodyLabel"
        explanationLabel.setContentHuggingHigh()

        qrCodeView.setContentHuggingVerticalLow()

        let explanationLabel2 = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "DEVICE_TRANSFER_QRCODE_EXPLANATION2",
                comment: "The second explanation for the device transfer qr code view"
            )
        )
        explanationLabel2.setContentHuggingHigh()

        let helpButton = OWSFlatButton.linkButtonForRegistration(
            title: OWSLocalizedString(
                "DEVICE_TRANSFER_QRCODE_NOT_SEEING",
                comment: "A prompt to provide further explanation if the user is not seeing the transfer on both devices."
            ),
            target: self,
            selector: #selector(didTapHelp)
        )
        helpButton.button.titleLabel?.textAlignment = .center
        helpButton.button.titleLabel?.numberOfLines = 0
        helpButton.button.titleLabel?.lineBreakMode = .byWordWrapping

        let cancelButton = OWSFlatButton.linkButtonForRegistration(
            title: CommonStrings.cancelButton,
            target: self,
            selector: #selector(didTapCancel)
        )

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
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.setHidesBackButton(true, animated: false)
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        deviceTransferService.addObserver(self)

        do {
            let url = try deviceTransferService.startAcceptingTransfersFromOldDevices(
                mode: .primary
            )

            qrCodeView.setQR(url: url)
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
    func didTapHelp() {
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
                    icon: UIImage(imageLiteralResourceName: "toggle-32"),
                    text: OWSLocalizedString(
                        "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_STEP_THREE",
                        comment: "Third step for local network permission action sheet"
                    )
                )
            ],
            button: OWSFlatButton.primaryButtonForRegistration(
                title: OWSLocalizedString(
                    "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_NEED_HELP",
                    comment: "A button asking the user if they need further help getting their transfer working."
                ),
                target: self,
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
    func didTapCancel() {
        Logger.info("")

        guard let navigationController = navigationController else {
            return owsFailBeta("unexpectedly missing nav controller")
        }

        navigationController.popViewController(animated: true)
    }

    @objc
    func didTapContactSupport() {
        Logger.info("")

        permissionActionSheetController?.dismiss(animated: true)
        permissionActionSheetController = nil

        ContactSupportAlert.presentStep2(
            emailSupportFilter: "Signal iOS Transfer",
            fromViewController: self
        )
    }
}

extension RegistrationTransferQRCodeViewController: DeviceTransferServiceObserver {
    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?) {}

    func deviceTransferServiceDidStartTransfer(progress: Progress) {
        let view = RegistrationTransferProgressViewController(progress: progress)
        navigationController?.pushViewController(view, animated: true)
    }

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {
        if let error = error {
            owsFailDebug("unexpected error while rendering QR code \(error)")
        }
    }
}
