//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity
import SignalServiceKit
public import SignalUI

public class RegistrationTransferQRCodeViewController: OWSViewController, OWSNavigationChildController {

    public var prefersNavigationBarHidden: Bool { true }

    private lazy var qrCodeView = QRCodeView(contentInset: 8)

    private lazy var expansionButton: UIButton = {
        let button = UIButton(configuration: .filled(), primaryAction: UIAction { [weak self] _ in
            self?.toggleQRCodeExpansion()
        })
        button.configuration?.cornerStyle = .capsule
        button.configuration?.imagePadding = 4
        button.configuration?.titleTextAttributesTransformer = .defaultFont(.dynamicTypeHeadlineClamped)
        button.configuration?.contentInsets = .init(hMargin: 16, vMargin: 8)
        return button
    }()

    private lazy var compactQRCodeContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.directionalLayoutMargins = .init(margin: 16)
        view.backgroundColor = .Signal.secondaryBackground

        view.addSubview(qrCodeView)
        qrCodeView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(expansionButton)
        expansionButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            qrCodeView.widthAnchor.constraint(equalTo: qrCodeView.heightAnchor),

            qrCodeView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            qrCodeView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            qrCodeView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            expansionButton.topAnchor.constraint(equalTo: qrCodeView.bottomAnchor, constant: 12),
            expansionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            expansionButton.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
        ])

        return view
    }()

    private lazy var closeButton: UIButton = {
        let closeButton = OWSButton()
        closeButton.setImage(
            Theme.iconImage(.buttonX).withTintColor(.ows_white, renderingMode: .alwaysOriginal),
            for: .normal
        )
        closeButton.contentMode = .center
        closeButton.addTarget(self, action: #selector(compactQRCode), for: .touchUpInside)
        return closeButton
    }()

    private let titleLabel: UILabel = {
        let label = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "DEVICE_TRANSFER_QRCODE_TITLE",
                comment: "The title for the device transfer qr code view"
            )
        )
        label.accessibilityIdentifier = "onboarding.transferQRCode.titleLabel"
        return label
    }()

    private let explanationLabel: UILabel = {
        let label = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "DEVICE_TRANSFER_QRCODE_EXPLANATION",
                comment: "The explanation for the device transfer qr code view"
            )
        )
        label.accessibilityIdentifier = "onboarding.transferQRCode.bodyLabel"
        return label
    }()

    private lazy var explanationLabel2: UILabel = {
        let explanationLabel2 = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "DEVICE_TRANSFER_QRCODE_EXPLANATION2",
                comment: "The second explanation for the device transfer qr code view"
            )
        )
        return explanationLabel2
    }()

    private lazy var bottomButtonsContainer: UIView = {
        let helpButton = UIButton(
            configuration: .mediumBorderless(title: OWSLocalizedString(
                "DEVICE_TRANSFER_QRCODE_NOT_SEEING",
                comment: "A prompt to provide further explanation if the user is not seeing the transfer on both devices."
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapHelp()
            }
        )
        helpButton.enableMultilineLabel()

        var cancelButton = UIButton(
            configuration: .mediumSecondary(title: CommonStrings.cancelButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapCancel()
            }
        )

        return UIStackView.verticalButtonStack(buttons: [ helpButton, cancelButton ], isFullWidthButtons: false)
    }()

    private let url: URL

    public init(url: URL) {
        self.url = url

        super.init()

        navigationItem.hidesBackButton = true
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        // Put QR code view into full-width container to allow centering of the rounded edges view.
        let qrCodeContainerView = UIView.container()
        qrCodeContainerView.addSubview(compactQRCodeContainer)
        compactQRCodeContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            compactQRCodeContainer.topAnchor.constraint(equalTo: qrCodeContainerView.topAnchor),
            compactQRCodeContainer.bottomAnchor.constraint(equalTo: qrCodeContainerView.bottomAnchor),
            compactQRCodeContainer.leadingAnchor.constraint(greaterThanOrEqualTo: qrCodeContainerView.leadingAnchor),
            compactQRCodeContainer.centerXAnchor.constraint(equalTo: qrCodeContainerView.centerXAnchor),
        ])

        // Content view.
        let stackView = addStaticContentStackView(
            arrangedSubviews: [
                .spacer(withHeight: 16),
                titleLabel,
                explanationLabel,
                qrCodeContainerView,
                explanationLabel2,
                .vStretchingSpacer(),
                bottomButtonsContainer,
            ],
            isScrollable: true
        )
        stackView.setCustomSpacing(24, after: explanationLabel)
        stackView.setCustomSpacing(24, after: compactQRCodeContainer)

        // QR code view.
        qrCodeView.translatesAutoresizingMaskIntoConstraints = false
        qrCodeView.setContentHuggingVerticalLow()
        NSLayoutConstraint.activate([
            {
                let constraint = qrCodeView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: Constants.compactQRCodeWidthMultiple)
                constraint.priority = .defaultHigh
                return constraint
            }(),
            qrCodeView.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.compactQRCodeMinSize),
        ])

        view.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            closeButton.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: 8),
        ])

        updateExpansionState(animated: false)

        view.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(compactQRCode)
        ))
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        AppEnvironment.shared.deviceTransferServiceRef.addObserver(self)

        Task { @MainActor in
            qrCodeView.setQRCode(url: url, stylingMode: .brandedWithoutLogo)
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        AppEnvironment.shared.deviceTransferServiceRef.removeObserver(self)
        AppEnvironment.shared.deviceTransferServiceRef.stopAcceptingTransfersFromOldDevices()
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        guard isQRCodeExpanded else { return }

        coordinator.animate { context in
            self.isQRCodeExpanded = false
            self.updateExpansionState(animated: false)
        }
    }

    // MARK: - QR Code expansion

    private var isQRCodeExpanded = false

    private func updateExpansionState(animated: Bool) {
        view.isUserInteractionEnabled = false

        let otherViews = [
            titleLabel,
            explanationLabel,
            bottomButtonsContainer,
        ]

        let animations: () -> Void = {
            if self.isQRCodeExpanded {
                let darkTraitCollection = UITraitCollection(userInterfaceStyle: .dark)

                let desiredSize = min(self.contentLayoutGuide.layoutFrame.width, 0.7 * self.contentLayoutGuide.layoutFrame.height) - (Constants.expandedQRCodeMargin * 2)
                let qrExpandScale = desiredSize / self.qrCodeView.frame.width
                let currentQRCenterY = self.view.convert(
                    self.qrCodeView.center,
                    from: self.qrCodeView.superview
                ).y
                let desiredQRCenterY = self.contentLayoutGuide.layoutFrame.minY + 0.4 * self.contentLayoutGuide.layoutFrame.height
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

                self.explanationLabel2.textColor = .Signal.secondaryLabel.resolvedColor(with: darkTraitCollection)
                self.compactQRCodeContainer.backgroundColor = .clear
                self.view.backgroundColor = .Signal.background.resolvedColor(with: darkTraitCollection)

                self.closeButton.alpha = 1
                otherViews.forEach { $0.alpha = 0 }

                // Expand/collapse button
                self.expansionButton.configuration?.title = OWSLocalizedString(
                    "DEVICE_TRANSFER_CONTRACT_QR_CODE_BUTTON",
                    comment: "Button shown to contract a QR code and exit the fullscreen view."
                )
                self.expansionButton.configuration?.image = Theme.iconImage(.minimize16)
                self.expansionButton.configuration?.baseForegroundColor = Theme.darkThemePrimaryColor
                self.expansionButton.configuration?.baseBackgroundColor = Theme.darkThemeSecondaryBackgroundColor
            } else {
                self.qrCodeView.transform = .identity
                self.expansionButton.transform = .identity
                self.explanationLabel2.transform = .identity

                self.explanationLabel2.textColor = .Signal.secondaryLabel
                self.compactQRCodeContainer.backgroundColor = .Signal.secondaryBackground
                self.view.backgroundColor = .Signal.background

                self.closeButton.alpha = 0
                otherViews.forEach { $0.alpha = 1 }

                // Expand/collapse button
                self.expansionButton.configuration?.title = OWSLocalizedString(
                    "DEVICE_TRANSFER_EXPAND_QR_CODE_BUTTON",
                    comment: "Button shown to expand a QR code and view it fullscreen."
                )
                self.expansionButton.configuration?.image = Theme.iconImage(.maximize16)
                self.expansionButton.configuration?.baseForegroundColor = .Signal.label
                self.expansionButton.configuration?.baseBackgroundColor = .clear
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
        setNeedsStatusBarAppearanceUpdate()
    }

    @objc
    private func compactQRCode() {
        guard isQRCodeExpanded else { return }
        toggleQRCodeExpansion()
    }

    // MARK: - Events

    weak var permissionActionSheetController: ActionSheetController?

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
                    icon: UIImage(resource: UIApplication.shared.currentAppIcon.previewImageResource),
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
            button: UIButton(
                configuration: .largePrimary(title: OWSLocalizedString(
                    "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_NEED_HELP",
                    comment: "A button asking the user if they need further help getting their transfer working."
                )),
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapContactSupport()
                }
            )
        )

        let actionSheetController = ActionSheetController()
        permissionActionSheetController = actionSheetController
        actionSheetController.customHeader = turnOnView
        actionSheetController.isCancelable = true
        presentActionSheet(actionSheetController)
    }

    func didTapCancel() {
        guard !isQRCodeExpanded else { return }
        Logger.info("")

        guard let navigationController else {
            return owsFailBeta("unexpectedly missing nav controller")
        }

        navigationController.popViewController(animated: true)
    }

    func didTapContactSupport() {
        guard !isQRCodeExpanded else { return }
        Logger.info("")

        permissionActionSheetController?.dismiss(animated: true)
        permissionActionSheetController = nil

        ContactSupportActionSheet.present(
            emailFilter: .deviceTransfer,
            logDumper: .fromGlobals(),
            fromViewController: self
        )
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

    func deviceTransferServiceDidRequestAppRelaunch() {
        if CurrentAppContext().frontmostViewController() == self {
            owsFail("Relaunch not supported from QR screen")
        }
    }
}
