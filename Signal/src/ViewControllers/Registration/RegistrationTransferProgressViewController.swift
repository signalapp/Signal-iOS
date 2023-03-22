//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MultipeerConnectivity
import SignalMessaging
import SignalUI
import UIKit

public class RegistrationTransferProgressViewController: OWSViewController {

    let progressView: TransferProgressView

    public init(progress: Progress) {
        self.progressView = TransferProgressView(progress: progress)
        super.init()
    }

    override public func loadView() {
        view = UIView()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = UILabel.titleLabelForRegistration(
            text: NSLocalizedString(
                "DEVICE_TRANSFER_RECEIVING_TITLE",
                comment: "The title on the view that shows receiving progress"
            )
        )
        view.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.transferProgress.titleLabel"
        titleLabel.setContentHuggingHigh()

        let explanationLabel = UILabel.explanationLabelForRegistration(
            text: NSLocalizedString(
                "DEVICE_TRANSFER_RECEIVING_EXPLANATION",
                comment: "The explanation on the view that shows receiving progress"
            )
        )
        explanationLabel.accessibilityIdentifier = "onboarding.transferProgress.bodyLabel"
        explanationLabel.setContentHuggingHigh()

        let cancelButton = OWSFlatButton.linkButtonForRegistration(
            title: CommonStrings.cancelButton,
            target: self,
            selector: #selector(didTapCancel)
        )

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
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.setHidesBackButton(true, animated: false)
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

        let actionSheet = ActionSheetController(
            title: NSLocalizedString("DEVICE_TRANSFER_CANCEL_CONFIRMATION_TITLE",
                                     comment: "The title of the dialog asking the user if they want to cancel a device transfer"),
            message: NSLocalizedString("DEVICE_TRANSFER_CANCEL_CONFIRMATION_MESSAGE",
                                       comment: "The message of the dialog asking the user if they want to cancel a device transfer")
        )
        actionSheet.addAction(OWSActionSheets.cancelAction)

        let okAction = ActionSheetAction(
            title: NSLocalizedString("DEVICE_TRANSFER_CANCEL_CONFIRMATION_ACTION",
                                     comment: "The stop action of the dialog asking the user if they want to cancel a device transfer"),
            style: .destructive
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
        guard let error = error else { return }

        switch error {
        case .assertion:
            progressView.renderError(
                text: NSLocalizedString("DEVICE_TRANSFER_ERROR_GENERIC",
                                        comment: "An error indicating that something went wrong with the transfer and it could not complete")
            )
        case .cancel:
            // User initiated, nothing to do
            break
        case .certificateMismatch:
            owsFailDebug("This should never happen on the new device")
        case .notEnoughSpace:
            progressView.renderError(
                text: NSLocalizedString("DEVICE_TRANSFER_ERROR_NOT_ENOUGH_SPACE",
                                        comment: "An error indicating that the user does not have enough free space on their device to complete the transfer")
            )
        case .unsupportedVersion:
            progressView.renderError(
                text: NSLocalizedString("DEVICE_TRANSFER_ERROR_UNSUPPORTED_VERSION",
                                        comment: "An error indicating the user must update their device before trying to transfer.")
            )
        case .modeMismatch:
            owsFailDebug("This should never happen on the new device")
        }
    }
}
