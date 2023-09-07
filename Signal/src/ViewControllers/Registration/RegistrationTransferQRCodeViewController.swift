//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity
import SignalMessaging
import SignalUI

public class RegistrationTransferQRCodeViewController: OWSViewController, OWSNavigationChildController {

    public var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }
    public var navbarBackgroundColorOverride: UIColor? { .clear }

    private lazy var qrCodeView = QRCodeView(useCircularWrapper: false)

    private lazy var expansionButton: ExpansionButton = {
        let button = ExpansionButton()
        button.addTarget(self, action: #selector(toggleQRCodeExpansion), for: .touchUpInside)
        return button
    }()

    private lazy var qrCodeSizeButtonSpacer = SpacerView()

    private lazy var compactQRCodeContainer: UIView = {
        let view = UIView()

        view.layer.cornerRadius = 12
        view.backgroundColor = Theme.secondaryBackgroundColor

        view.addSubview(qrCodeView)
        view.addSubview(expansionButton)

        qrCodeView.autoPinEdge(toSuperviewEdge: .top, withInset: 16)
        expansionButton.autoPinEdge(.top, to: .bottom, of: qrCodeView, withOffset: 12)
        expansionButton.autoPinEdge(toSuperviewEdge: .bottom, withInset: 16)

        qrCodeView.autoPinEdge(toSuperviewEdge: .leading, withInset: 16)
        qrCodeView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)

        expansionButton.autoHCenterInSuperview()

        return view
    }()

    private lazy var explanationLabel2: UILabel = {
        let explanationLabel2 = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "DEVICE_TRANSFER_QRCODE_EXPLANATION2",
                comment: "The second explanation for the device transfer qr code view"
            )
        )
        explanationLabel2.setContentHuggingHigh()
        return explanationLabel2
    }()

    private lazy var closeButton: UIButton = {
        let closeButton = OWSButton()
        closeButton.setImage(
            Theme.iconImage(.buttonX).asTintedImage(color: .ows_white),
            for: .normal
        )
        closeButton.contentMode = .center
        closeButton.addTarget(self, action: #selector(compactQRCode), for: .touchUpInside)
        return closeButton
    }()

    private let titleLabel = UILabel.titleLabelForRegistration(
        text: OWSLocalizedString(
            "DEVICE_TRANSFER_QRCODE_TITLE",
            comment: "The title for the device transfer qr code view"
        )
    )

    private let explanationLabel = UILabel.explanationLabelForRegistration(
        text: OWSLocalizedString(
            "DEVICE_TRANSFER_QRCODE_EXPLANATION",
            comment: "The explanation for the device transfer qr code view"
        )
    )

    private lazy var helpButton = OWSFlatButton.linkButtonForRegistration(
        title: OWSLocalizedString(
            "DEVICE_TRANSFER_QRCODE_NOT_SEEING",
            comment: "A prompt to provide further explanation if the user is not seeing the transfer on both devices."
        ),
        target: self,
        selector: #selector(didTapHelp)
    )

    private lazy var cancelButton = OWSFlatButton.linkButtonForRegistration(
        title: CommonStrings.cancelButton,
        target: self,
        selector: #selector(didTapCancel)
    )

    override public func loadView() {
        view = UIView()

        view.backgroundColor = Theme.backgroundColor

        view.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.transferQRCode.titleLabel"
        titleLabel.setContentHuggingHigh()

        explanationLabel.textColor = Theme.primaryTextColor
        explanationLabel.accessibilityIdentifier = "onboarding.transferQRCode.bodyLabel"
        explanationLabel.setContentHuggingHigh()

        qrCodeView.setContentHuggingVerticalLow()

        helpButton.button.titleLabel?.textAlignment = .center
        helpButton.button.titleLabel?.numberOfLines = 0
        helpButton.button.titleLabel?.lineBreakMode = .byWordWrapping

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            compactQRCodeContainer,
            explanationLabel2,
            UIView.vStretchingSpacer(),
            helpButton,
            cancelButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 20
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        qrCodeView.autoPinToSquareAspectRatio()
        qrCodeView.autoMatch(
            .width,
            to: .width,
            of: view,
            withMultiplier: Constants.compactQRCodeWidthMultiple
        ).priority = .defaultHigh
        qrCodeView.autoSetDimension(
            .width,
            toSize: Constants.compactQRCodeMinSize,
            relation: .greaterThanOrEqual
        ).priority = .required

        for view in [titleLabel, explanationLabel, explanationLabel2] {
            view.setCompressionResistanceHigh()
            view.autoPinEdge(toSuperviewMargin: .leading)
            view.autoPinEdge(toSuperviewMargin: .trailing)
        }

        view.addSubview(closeButton)
        closeButton.autoPinLeadingToSuperviewMargin()
        closeButton.autoPinEdge(.top, to: .top, of: view, withOffset: 24)

        updateExpansionState(animated: false)

        view.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(compactQRCode)
        ))
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

    // MARK: - QR Code expansion

    private var isQRCodeExpanded = false

    private func updateExpansionState(animated: Bool) {
        view.isUserInteractionEnabled = false

        let otherViews = [
            titleLabel,
            explanationLabel,
            helpButton,
            cancelButton
        ]

        let animations: () -> Void = {
            if self.isQRCodeExpanded {
                let desiredSize = UIScreen.main.bounds.width - (Constants.expandedQRCodeMargin * 2)
                let qrExpandScale = desiredSize / self.qrCodeView.frame.width
                let currentQRCenterY = self.view.convert(
                    self.qrCodeView.center,
                    from: self.qrCodeView.superview
                ).y
                let desiredQRCenterY = self.view.frame.height * 0.4
                let qrExpandYOffset = desiredQRCenterY - currentQRCenterY
                self.qrCodeView.layer.anchorPoint = .init(x: 0.5, y: 0.5)
                self.qrCodeView.transform = .scale(qrExpandScale)
                    .concatenating(.translate(CGPoint(x: 0, y: qrExpandYOffset)))

                let expandedQRCodeBottom = desiredQRCenterY + (desiredSize / 2)

                let desiredButtonTop = expandedQRCodeBottom + 16
                let currentButtonTop = self.view.convert(
                    self.expansionButton.frame.origin,
                    from: self.expansionButton.superview
                ).y
                let buttonYOffset = max(0, desiredButtonTop - currentButtonTop)
                self.expansionButton.transform = .translate(CGPoint(x: 0, y: buttonYOffset))

                let desiredLabelTop = desiredButtonTop + self.expansionButton.frame.height + 16
                let currentLabelTop = self.view.convert(
                    self.explanationLabel2.frame.origin,
                    from: self.explanationLabel2.superview
                ).y
                let labelYOffset = max(0, desiredLabelTop - currentLabelTop)
                self.explanationLabel2.transform = .translate(CGPoint(x: 0, y: labelYOffset))

                self.explanationLabel2.textColor = Theme.darkThemePrimaryColor
                self.closeButton.alpha = 1
                otherViews.forEach { $0.alpha = 0 }
                self.compactQRCodeContainer.backgroundColor = .clear
                self.view.backgroundColor = .ows_black
                self.qrCodeView.backgroundColor = .ows_white
                self.expansionButton.mode = .contract
            } else {
                self.qrCodeView.transform = .identity
                self.expansionButton.transform = .identity
                self.explanationLabel2.transform = .identity
                self.explanationLabel2.textColor = Theme.primaryTextColor
                self.closeButton.alpha = 0
                otherViews.forEach { $0.alpha = 1 }
                self.compactQRCodeContainer.backgroundColor = Theme.secondaryBackgroundColor
                self.view.backgroundColor = Theme.backgroundColor
                self.qrCodeView.backgroundColor = .ows_white
                self.expansionButton.mode = .expand
            }
        }

        guard animated else {
            animations()
            view.isUserInteractionEnabled = true
            return
        }
        UIView.animate(withDuration: 0.2, animations: animations) { _ in
            self.view.isUserInteractionEnabled = true
        }
    }

    @objc
    private func toggleQRCodeExpansion() {
        isQRCodeExpanded = !isQRCodeExpanded
        updateExpansionState(animated: true)
    }

    @objc
    private func compactQRCode() {
        guard isQRCodeExpanded else { return }
        toggleQRCodeExpansion()
    }

    // MARK: - Events

    weak var permissionActionSheetController: ActionSheetController?

    @objc
    func didTapHelp() {
        guard !isQRCodeExpanded else { return }
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
        guard !isQRCodeExpanded else { return }
        Logger.info("")

        guard let navigationController = navigationController else {
            return owsFailBeta("unexpectedly missing nav controller")
        }

        navigationController.popViewController(animated: true)
    }

    @objc
    func didTapContactSupport() {
        guard !isQRCodeExpanded else { return }
        Logger.info("")

        permissionActionSheetController?.dismiss(animated: true)
        permissionActionSheetController = nil

        ContactSupportAlert.presentStep2(
            emailSupportFilter: "Signal iOS Transfer",
            fromViewController: self
        )
    }

    // MARK: - Expand/Contract Button

    private class ExpansionButton: UIButton {
        enum Mode {
            case expand
            case contract

            var text: String {
                switch self {
                case .expand:
                    return OWSLocalizedString(
                        "DEVICE_TRANSFER_EXPAND_QR_CODE_BUTTON",
                        comment: "Button shown to expand a QR code and view it fullscreen."
                    )
                case .contract:
                    return OWSLocalizedString(
                        "DEVICE_TRANSFER_CONTRACT_QR_CODE_BUTTON",
                        comment: "Button shown to contract a QR code and exit the fullscreen view."
                    )
                }
            }

            var image: UIImage {
                switch self {
                case .expand:
                    return Theme.iconImage(.maximize)
                case .contract:
                    return Theme.iconImage(.minimize)
                }
            }

            var backgroundColor: UIColor {
                switch self {
                case .expand: return .clear
                case .contract: return Theme.darkThemeSecondaryBackgroundColor
                }
            }

            var textColor: UIColor {
                switch self {
                case .expand: return Theme.primaryTextColor
                case .contract: return Theme.darkThemePrimaryColor
                }
            }
        }

        var mode: Mode = .expand {
            didSet {
                updateForMode()
            }
        }

        private lazy var _imageView = UIImageView()
        private lazy var _label = UILabel()

        required init() {
            super.init(frame: .zero)

            addSubview(_imageView)
            addSubview(_label)

            _imageView.autoPinLeadingToSuperviewMargin()
            _imageView.autoPinEdge(toSuperviewEdge: .leading, withInset: 12)
            _label.autoPinEdge(.leading, to: .trailing, of: _imageView, withOffset: 4)
            _imageView.autoPinHeight(toHeightOf: _label, offset: -4)
            _imageView.autoPinEdge(
                .top,
                to: .top,
                of: _label,
                withOffset: 2
            )
            _label.autoPinEdge(toSuperviewEdge: .top, withInset: 6, relation: .greaterThanOrEqual)
            _label.autoPinEdge(toSuperviewEdge: .bottom, withInset: 8, relation: .lessThanOrEqual)
            _label.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)

            _imageView.autoPinToSquareAspectRatio()
            _label.setContentHuggingHigh()
            _imageView.setContentHuggingHigh()

            updateForMode()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func updateForMode() {
            _label.text = mode.text
            _imageView.image = mode.image
            _imageView.tintColor = mode.textColor
            _label.textColor = mode.textColor
            backgroundColor = mode.backgroundColor
            layer.cornerRadius = bounds.height / 2
        }

        override var bounds: CGRect {
            didSet {
                layer.cornerRadius = bounds.height / 2
            }
        }
    }

    // MARK: - Constants

    private enum Constants {
        static let compactQRCodeWidthMultiple: CGFloat = 0.6
        static let compactQRCodeMinSize: CGFloat = 182

        static let expandedQRCodeMargin: CGFloat = 8
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
