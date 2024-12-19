//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

class ProvisioningQRCodeViewController: ProvisioningBaseViewController {
    private enum ProvisioningUrlDisplayMode {
        case loading
        case loaded(URL)
        case refreshButton
    }

    private var qrCodeWrapperView: UIView!
    private var qrCodeWrapperViewSizeConstraint: NSLayoutConstraint!
    private var qrCodeView: QRCodeView!
    private var qrCodeRefreshButton: OWSButton!

    private var rotateQRCodeTask: Task<Void, Never>?

    private func setDisplayMode(_ displayMode: ProvisioningUrlDisplayMode) {
        switch displayMode {
        case .loading:
            qrCodeView.isHidden = false
            qrCodeRefreshButton.isHidden = true

            qrCodeView.setLoading()
        case .loaded(let url):
            qrCodeView.isHidden = false
            qrCodeRefreshButton.isHidden = true

            qrCodeView.setQRCode(url: url)
        case .refreshButton:
            qrCodeView.isHidden = true
            qrCodeRefreshButton.isHidden = false
        }
    }

    override init(provisioningController: ProvisioningController) {
        super.init(provisioningController: provisioningController)
    }

    // MARK: -

    override func loadView() {
        view = UIView()

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

        qrCodeView = QRCodeView()

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
            guard let self else { return }

            setDisplayMode(.loading)
            startQRCodeRotationTask()
        }

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

        qrCodeWrapperView.addSubview(qrCodeRefreshButton)
        qrCodeRefreshButton.autoCenterInSuperviewMargins()

        qrCodeWrapperView.addSubview(qrCodeView)
        qrCodeView.autoPinEdgesToSuperviewMargins()

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

        qrCodeWrapperView.autoPinToSquareAspectRatio()
        qrCodeWrapperViewSizeConstraint = qrCodeWrapperView.autoSetDimension(.height, toSize: 0)
    }

    private func updateLayoutForViewSize(_ size: CGSize) {
        if size.height > size.width {
            qrCodeWrapperView.layoutMargins = UIEdgeInsets(margin: 48)
            qrCodeWrapperViewSizeConstraint.constant = 352
        } else {
            qrCodeWrapperView.layoutMargins = UIEdgeInsets(margin: 24)
            qrCodeWrapperViewSizeConstraint.constant = 220
        }
    }

    // MARK: -

    private func startQRCodeRotationTask() {
        AssertIsOnMainThread()

        guard rotateQRCodeTask == nil else {
            return
        }

        rotateQRCodeTask = Task {
            /// Every 45s, five times, rotate the provisioning socket for which
            /// we're displaying a QR code. If we fail, or once we've exhausted
            /// the five rotations, fall back to showing a manual "refresh"
            /// button.
            ///
            /// Note that the server will close provisioning sockets after 90s,
            /// so hopefully rotating every 45s means no primary will ever end
            /// up trying to send into a closed socket.
            do {
                for _ in 0..<5 {
                    let provisioningUrl = try await openNewProvisioningSocket()

                    try Task.checkCancellation()

                    setDisplayMode(.loaded(provisioningUrl))

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
            rotateQRCodeTask = nil
        }
    }

    // MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()

        setDisplayMode(.loading)
        startQRCodeRotationTask()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        /// Wait until this method to update the layout, because this is the
        /// first point at which we will be laid out and know our size.
        updateLayoutForViewSize(view.bounds.size)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        rotateQRCodeTask?.cancel()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        updateLayoutForViewSize(size)
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

    private nonisolated func openNewProvisioningSocket() async throws -> URL {
        let provisioningUrl = try await provisioningController.openNewProvisioningSocket()

#if TESTABLE_BUILD
        currentProvisioningUrl.set(provisioningUrl)
#endif

        return provisioningUrl
    }
}
