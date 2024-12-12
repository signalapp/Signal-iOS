//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

class ProvisioningQRCodeViewController: ProvisioningBaseViewController {
    private enum QRCodeDisplayMode {
        case qrCodeImage(UIImage?)
        case refreshButton
        case loadingSpinner
    }

    private var qrCodeWrapperView: UIView!
    private var qrCodeWrapperViewSizeConstraints: [NSLayoutConstraint]!
    private var qrCodeImageBackgroundView: UIView!
    private var qrCodeImageView: UIImageView!
    private var qrCodeRefreshButton: OWSButton!
    private var qrCodeLoadingSpinner: UIActivityIndicatorView!

    private var rotateQRCodeTask: Task<Void, Never>?

    private func setDisplayMode(_ displayMode: QRCodeDisplayMode) {
        switch displayMode {
        case .qrCodeImage(let image):
            qrCodeLoadingSpinner.isHidden = true
            qrCodeImageBackgroundView.isHidden = false
            qrCodeRefreshButton.isHidden = true

            qrCodeImageView.setTemplateImage(image, tintColor: .qrCodeBlue)
        case .refreshButton:
            qrCodeLoadingSpinner.isHidden = true
            qrCodeImageBackgroundView.isHidden = true
            qrCodeRefreshButton.isHidden = false
        case .loadingSpinner:
            qrCodeLoadingSpinner.isHidden = false
            qrCodeImageBackgroundView.isHidden = true
            qrCodeRefreshButton.isHidden = true
        }
    }

    override init(provisioningController: ProvisioningController) {
        super.init(provisioningController: provisioningController)
    }

    private func populateViewContents() {
        view.removeAllSubviews()

        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.createTitleLabel(text: OWSLocalizedString(
            "SECONDARY_ONBOARDING_SCAN_CODE_TITLE",
            comment: "header text while displaying a QR code which, when scanned, will link this device."
        ))

        let bodyLabel = self.createTitleLabel(text: OWSLocalizedString(
            "SECONDARY_ONBOARDING_SCAN_CODE_BODY",
            comment: "body text while displaying a QR code which, when scanned, will link this device."
        ))
        bodyLabel.font = UIFont.dynamicTypeBody
        bodyLabel.numberOfLines = 0

        qrCodeWrapperView = UIView()
        qrCodeWrapperView.backgroundColor = .ows_gray02
        qrCodeWrapperView.layer.cornerRadius = 24

        qrCodeImageBackgroundView = UIView()
        qrCodeImageBackgroundView.backgroundColor = .white
        qrCodeImageBackgroundView.layoutMargins = UIEdgeInsets(margin: 20)
        qrCodeImageBackgroundView.layer.cornerRadius = 12

        qrCodeImageView = UIImageView()
        qrCodeImageView.backgroundColor = .white

        qrCodeRefreshButton = OWSRoundedButton()
        qrCodeRefreshButton.setAttributedTitle(
            {
                let icon = NSAttributedString.with(
                    image: UIImage(named: "refresh")!,
                    font: .dynamicTypeBody,
                    centerVerticallyRelativeTo: .dynamicTypeBody
                )

                let text = OWSLocalizedString(
                    "SECONDARY_ONBOARDING_SCAN_CODE_REFRESH_CODE_BUTTON",
                    comment: "Text for a button offering to refresh the QR code to link an iPad."
                )

                let string = NSMutableAttributedString()
                string.append(icon)
                string.append(" ")
                string.append(text)
                return string
            }(),
            for: .normal
        )
        qrCodeRefreshButton.setTitleColor(.black, for: .normal)
        qrCodeRefreshButton.titleLabel!.font = .dynamicTypeBody.bold()
        qrCodeRefreshButton.backgroundColor = .white
        qrCodeRefreshButton.ows_contentEdgeInsets = UIEdgeInsets(hMargin: 24, vMargin: 0)
        qrCodeRefreshButton.autoSetDimension(.height, toSize: 40)
        qrCodeRefreshButton.block = { [weak self] in
            Task { [weak self] in
                guard let self else { return }

                setDisplayMode(.loadingSpinner)

                do {
                    let qrCodeImage = try await fetchNewProvisioningQRCode()
                    setDisplayMode(.qrCodeImage(qrCodeImage))
                } catch {
                    setDisplayMode(.refreshButton)
                }
            }
        }

        qrCodeLoadingSpinner = UIActivityIndicatorView(style: .large)
        qrCodeLoadingSpinner.color = Theme.lightThemePrimaryColor
        qrCodeLoadingSpinner.autoSetDimensions(to: .init(width: 40, height: 40))
        qrCodeLoadingSpinner.startAnimating()

        let getHelpLabel = UILabel()
        getHelpLabel.text = OWSLocalizedString(
            "SECONDARY_ONBOARDING_SCAN_CODE_HELP_TEXT",
            comment: "Link text for page with troubleshooting info shown on the QR scanning screen"
        )
        getHelpLabel.textColor = Theme.accentBlueColor
        getHelpLabel.font = UIFont.dynamicTypeSubheadlineClamped
        getHelpLabel.numberOfLines = 0
        getHelpLabel.textAlignment = .center
        getHelpLabel.lineBreakMode = .byWordWrapping
        getHelpLabel.isUserInteractionEnabled = true
        getHelpLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapExplanationLabel)))
        getHelpLabel.setContentHuggingHigh()

        // MARK: Layout

        qrCodeImageBackgroundView.addSubview(qrCodeImageView)
        qrCodeImageView.autoPinEdgesToSuperviewMargins()

        qrCodeWrapperView.addSubview(qrCodeLoadingSpinner)
        qrCodeLoadingSpinner.autoCenterInSuperviewMargins()

        qrCodeWrapperView.addSubview(qrCodeRefreshButton)
        qrCodeRefreshButton.autoCenterInSuperviewMargins()

        qrCodeWrapperView.addSubview(qrCodeImageBackgroundView)
        qrCodeImageBackgroundView.autoPinEdgesToSuperviewMargins()

        let qrCodeTopSpacer = UIView()
        let qrCodeBottomSpacer = UIView()

        let contentStack = UIStackView(arrangedSubviews: [
            titleLabel,
            bodyLabel,
            qrCodeTopSpacer,
            qrCodeWrapperView,
            qrCodeBottomSpacer,
            getHelpLabel,
        ])
#if TESTABLE_BUILD
        let shareURLButton = UIButton(type: .system)
        shareURLButton.setTitle(LocalizationNotNeeded("Debug only: Share URL"), for: .normal)
        shareURLButton.addTarget(self, action: #selector(didTapShareURL), for: .touchUpInside)

        contentStack.addArrangedSubview(shareURLButton)
#endif

        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 12

        primaryView.addSubview(contentStack)
        contentStack.autoPinEdgesToSuperviewMargins()

        qrCodeTopSpacer.autoMatch(.height, to: .height, of: qrCodeBottomSpacer, withMultiplier: 0.33)

        /// Constraint constants managed by `adjustLayoutForCurrentOrientation`.
        qrCodeWrapperViewSizeConstraints = [
            qrCodeWrapperView.autoSetDimension(.height, toSize: 0),
            qrCodeWrapperView.autoSetDimension(.width, toSize: 0),
        ]

        adjustLayoutForCurrentOrientation()
    }

    @objc
    private func adjustLayoutForCurrentOrientation() {
        if UIDevice.current.orientation.isPortrait {
            qrCodeWrapperView.layoutMargins = UIEdgeInsets(margin: 48)
            qrCodeWrapperViewSizeConstraints.forEach { $0.constant = 352 }
        } else {
            qrCodeWrapperView.layoutMargins = UIEdgeInsets(margin: 24)
            qrCodeWrapperViewSizeConstraints.forEach { $0.constant = 220 }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        populateViewContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(adjustLayoutForCurrentOrientation),
            name: UIDevice.orientationDidChangeNotification,
            object: UIDevice.current
        )

        setDisplayMode(.loadingSpinner)

        rotateQRCodeTask = Task {
            /// Refresh the QR code every 45s, five times. If we fail, or once
            /// we've exhausted the five refreshes, fall back to showing an
            /// error state with a manual retry.
            do {
                for _ in 0..<5 {
                    let qrCodeImage = try await fetchNewProvisioningQRCode()

                    try Task.checkCancellation()

                    setDisplayMode(.qrCodeImage(qrCodeImage))

                    try await Task.sleep(nanoseconds: 45 * NSEC_PER_SEC)

                    try Task.checkCancellation()
                }
            } catch is CancellationError {
                // Bail!
                return
            } catch {
                // Fall through as if we'd exhausted our rotations.
            }

            setDisplayMode(.refreshButton)
        }
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        rotateQRCodeTask?.cancel()
        rotateQRCodeTask = nil
        setDisplayMode(.refreshButton)
    }

    // MARK: - Events

    override func shouldShowBackButton() -> Bool {
        // Never show the back button here
        return false
    }

    @objc
    func didTapExplanationLabel(sender: UIGestureRecognizer) {
        UIApplication.shared.open(URL(string: "https://support.signal.org/hc/articles/360007320451")!)
    }

#if TESTABLE_BUILD
    private let currentProvisioningUrl: AtomicValue<URL?> = AtomicValue(nil, lock: .init())

    @IBAction func didTapShareURL(_ sender: UIButton) {
        if let provisioningUrl = currentProvisioningUrl.get() {
            UIPasteboard.general.url = provisioningUrl
            // If we share the plain url and airdrop it to a mac, it will just open the url,
            // and fail because signal desktop can't open it.
            // Share some text instead so we can open it on mac and copy paste into
            // a primary device simulator.
            let activityVC = UIActivityViewController(
                activityItems: ["Provisioning URL: " + provisioningUrl.absoluteString],
                applicationActivities: nil
            )
            activityVC.popoverPresentationController?.sourceView = sender
            self.present(activityVC, animated: true)
        } else {
            UIPasteboard.general.string = LocalizationNotNeeded("URL NOT READY YET")
        }
    }
#endif

    // MARK: -

    private nonisolated func fetchNewProvisioningQRCode() async throws -> UIImage? {
        let provisioningUrl = try await provisioningController.getProvisioningURL()

#if TESTABLE_BUILD
        currentProvisioningUrl.set(provisioningUrl)
#endif

        return SignalBrandedQRCodeGenerator(
            foregroundColor: .qrCodeBlue,
            backgroundColor: .clear
        ).generateQRCode(url: provisioningUrl)
    }
}

private extension UIColor {
    static var qrCodeBlue: UIColor {
        return SignalBrandedQRCodes.QRCodeColor.blue.foreground
    }
}
