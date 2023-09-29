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
            text: OWSLocalizedString(
                "DEVICE_TRANSFER_RECEIVING_TITLE",
                comment: "The title on the view that shows receiving progress"
            )
        )
        view.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.transferProgress.titleLabel"
        titleLabel.setContentHuggingHigh()

        let explanationLabel = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
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
                text: OWSLocalizedString("DEVICE_TRANSFER_ERROR_GENERIC",
                                        comment: "An error indicating that something went wrong with the transfer and it could not complete")
            )
        case .backgroundedDevice:
            progressView.renderError(
                text: OWSLocalizedString(
                    "DEVICE_TRANSFER_ERROR_BACKGROUNDED",
                    comment: "An error indicating that the other device closed signal mid-transfer and it could not complete"
                )
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

    func deviceTransferServiceDidRequestAppRelaunch() {
        self.present(TransferRelaunchSheet(), animated: true)
    }
}

private class TransferRelaunchSheet: InteractiveSheetViewController {
    let stackView = UIStackView()

    public override var canBeDismissed: Bool { false }

    public override var sheetBackgroundColor: UIColor { Theme.tableView2PresentedBackgroundColor }

    override public func viewDidLoad() {
        super.viewDidLoad()

        minimizedHeight = 460
        super.allowsExpansion = false

        stackView.axis = .vertical
        stackView.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 24)
        stackView.spacing = 22
        stackView.isLayoutMarginsRelativeArrangement = true
        contentView.addSubview(stackView)

        let image = UIImage(named: "transfer_complete")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        stackView.addArrangedSubview(imageView)
        imageView.autoSetDimensions(to: CGSize(width: 128, height: 64))

        let titleLabel = UILabel()
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.dynamicTypeTitle2.semibold()
        titleLabel.text = OWSLocalizedString(
            "TRANSFER_COMPLETE_SHEET_TITLE",
            comment: "Title for bottom sheet shown when device transfer completes on the receiving device."
        )
        stackView.addArrangedSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.text = OWSLocalizedString(
            "TRANSFER_COMPLETE_SHEET_SUBTITLE",
            comment: "Subtitle for bottom sheet shown when device transfer completes on the receiving device."
        )
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = .dynamicTypeBody
        subtitleLabel.numberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping
        stackView.addArrangedSubview(subtitleLabel)

        let exitButton = UIButton()
        exitButton.backgroundColor = .ows_accentBlue
        exitButton.layer.cornerRadius = 8
        exitButton.titleEdgeInsets = UIEdgeInsets(hMargin: 0, vMargin: 18)
        exitButton.setTitleColor(.ows_white, for: .normal)
        exitButton.setTitle(
            OWSLocalizedString(
                "TRANSFER_COMPLETE_SHEET_BUTTON",
                comment: "Button for bottom sheet shown when device transfer completes on the receiving device. Tapping will terminate the Signal app and trigger a notification to relaunch."
            ),
            for: .normal
        )
        exitButton.addTarget(self, action: #selector(didTapExitButton), for: .touchUpInside)
        contentView.addSubview(exitButton)
        exitButton.autoPinEdge(
            .leading,
            to: .leading,
            of: contentView,
            withOffset: 32,
            relation: .greaterThanOrEqual
        ).priority = .required
        exitButton.autoPinEdge(
            .trailing,
            to: .trailing,
            of: contentView,
            withOffset: -32,
            relation: .greaterThanOrEqual
        ).priority = .required
        exitButton.autoSetDimension(.width, toSize: 325, relation: .greaterThanOrEqual)
        exitButton.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)
        exitButton.autoPinEdge(.bottom, to: .bottom, of: contentView, withOffset: -50)
        exitButton.autoHCenterInSuperview()

        stackView.autoPinEdge(.top, to: .top, of: contentView)
        stackView.autoPinWidth(toWidthOf: contentView)
        stackView.autoHCenterInSuperview()
    }

    @objc
    private func didTapExitButton() {
        Logger.info("")
        notificationPresenter.notifyUserToRelaunchAfterTransfer {
            Logger.info("Deliberately terminating app post-transfer.")
            exit(0)
        }
    }
}
