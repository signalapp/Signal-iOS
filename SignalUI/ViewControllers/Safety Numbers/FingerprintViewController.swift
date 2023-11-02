//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Lottie
import PureLayout
import SafariServices
import SignalMessaging
import SignalServiceKit
import UIKit

public class FingerprintViewController: OWSViewController, OWSNavigationChildController {

    public class func present(
        for theirAci: Aci?,
        from viewController: UIViewController
    ) {
        let fingerprintResult = databaseStorage.read { (tx) -> OWSFingerprintBuilder.FingerprintResult? in
            guard let theirAci else {
                return nil
            }
            let identityManager = DependenciesBridge.shared.identityManager
            let theirAddress = SignalServiceAddress(theirAci)
            guard let theirRecipientIdentity = identityManager.recipientIdentity(for: theirAddress, tx: tx.asV2Read) else {
                return nil
            }
            return OWSFingerprintBuilder(
                contactsManager: contactsManager,
                identityManager: identityManager,
                tsAccountManager: DependenciesBridge.shared.tsAccountManager
            ).fingerprints(
                theirAci: theirAci,
                theirRecipientIdentity: theirRecipientIdentity,
                tx: tx
            )
        }

        guard let fingerprintResult else {
            let actionSheet = ActionSheetController(message: OWSLocalizedString(
                "CANT_VERIFY_IDENTITY_EXCHANGE_MESSAGES",
                comment: "Alert shown when the user needs to exchange messages to see the safety number."
            ))

            actionSheet.addAction(.init(title: CommonStrings.learnMore, style: .default, handler: { _ in
                guard let vc = CurrentAppContext().frontmostViewController() else {
                    return
                }
                Self.showLearnMoreUrl(from: vc)
            }))
            actionSheet.addAction(OWSActionSheets.cancelAction)

            viewController.presentActionSheet(actionSheet)
            return
        }

        let fingerprintViewController = FingerprintViewController(
            fingerprint: fingerprintResult.fingerprint,
            recipientAci: fingerprintResult.theirAci,
            recipientIdentity: fingerprintResult.theirRecipientIdentity
        )
        let navigationController = OWSNavigationController(rootViewController: fingerprintViewController)
        viewController.present(navigationController, animated: true)
    }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .solid
    }

    public var navbarBackgroundColorOverride: UIColor? {
        return Self.backgroundColor
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    private let recipientAci: Aci
    private let recipientIdentity: OWSRecipientIdentity
    private let identityKey: Data
    private let fingerprint: OWSFingerprint
    private var isVerified = false

    public init(
        fingerprint: OWSFingerprint,
        recipientAci: Aci,
        recipientIdentity: OWSRecipientIdentity
    ) {
        self.recipientAci = recipientAci
        // By capturing the identity key when we enter these views, we prevent the edge case
        // where the user verifies a key that we learned about while this view was open.
        self.recipientIdentity = recipientIdentity
        self.identityKey = recipientIdentity.identityKey
        self.fingerprint = fingerprint

        super.init()

        title = NSLocalizedString("PRIVACY_VERIFICATION_TITLE", comment: "Navbar title")
        navigationItem.leftBarButtonItem = .init(
            barButtonSystemItem: .done,
            target: self, action: #selector(didTapDone),
            accessibilityIdentifier: "FingerprintViewController.done"
        )

        identityStateChangeObserver = NotificationCenter.default.addObserver(
            forName: .identityStateDidChange,
            object: nil,
            queue: .main) { [weak self] _ in
                self?.identityStateDidChange()
            }
    }

    deinit {
        if let identityStateChangeObserver {
            NotificationCenter.default.removeObserver(identityStateChangeObserver)
        }
    }

    private static var backgroundColor: UIColor {
        return Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray02
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Self.backgroundColor

        configureUI()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        view.backgroundColor = Self.backgroundColor

        updateVerificationStateLabel()
        setInstructionsText()
        setVerifyUnverifyButtonColors()
    }

    // MARK: UI

    private lazy var fingerprintCard = FingerprintCard(fingerprint: fingerprint, controller: self)

    private lazy var instructionsTextView: UITextView = {
        let textView = LinkingTextView()
        textView.delegate = self
        return textView
    }()

    private func setInstructionsText() {
        let instructionsFormat = OWSLocalizedString(
            "VERIFY_SAFETY_NUMBER_INSTRUCTIONS",
            comment: "Instructions for verifying your safety number. Embeds {{contact's name}}"
        )
        // Link doesn't matter, we will override tap behavior.
        let learnMoreString = CommonStrings.learnMore.styled(with: .link(URL(string: Constants.learnMoreUrl)!))
        instructionsTextView.attributedText = NSAttributedString.composed(of: [
            String(format: instructionsFormat, fingerprint.theirName),
            " ",
            learnMoreString
        ]).styled(
            with: .font(.dynamicTypeFootnote),
            .color(Theme.secondaryTextAndIconColor),
            .alignment(.center)
        )
        instructionsTextView.linkTextAttributes = [
            .foregroundColor: Theme.primaryTextColor,
            .underlineColor: UIColor.clear,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private lazy var verifyUnverifyButtonLabel = UILabel()
    private lazy var verifyUnverifyPillbox = PillBoxView()

    private lazy var verifyUnverifyButton: UIView = {
        verifyUnverifyPillbox.layer.masksToBounds = true
        verifyUnverifyPillbox.accessibilityIdentifier = "FingerprintViewController.verifyUnverifyButton"
        verifyUnverifyPillbox.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapVerifyUnverify)))

        verifyUnverifyButtonLabel.font = .systemFont(ofSize: 13, weight: .bold)
        verifyUnverifyButtonLabel.textAlignment = .center
        verifyUnverifyButtonLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        verifyUnverifyPillbox.addSubview(verifyUnverifyButtonLabel)
        verifyUnverifyButtonLabel.autoPinWidthToSuperview(withMargin: 24)
        verifyUnverifyButtonLabel.autoPinHeightToSuperview(withMargin: 12)

        return verifyUnverifyPillbox
    }()

    private func setVerifyUnverifyButtonColors() {
        verifyUnverifyButtonLabel.textColor = Theme.primaryTextColor
        verifyUnverifyPillbox.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .white
    }

    private func configureUI() {
        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        let containerView = UIView()
        scrollView.addSubview(containerView)

        scrollView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        containerView.autoPinEdges(toEdgesOf: scrollView)
        containerView.autoPinWidth(toWidthOf: view)

        containerView.addSubview(fingerprintCard)
        containerView.addSubview(instructionsTextView)
        view.addSubview(verifyUnverifyButton)

        fingerprintCard.autoPinEdge(toSuperviewSafeArea: .top, withInset: 56)
        fingerprintCard.autoPinWidth(toWidthOf: containerView, offset: -.scaleFromIPhone5To7Plus(60, 105))
        fingerprintCard.autoHCenterInSuperview()

        instructionsTextView.autoPinEdge(.leading, to: .leading, of: containerView, withOffset: .scaleFromIPhone5To7Plus(18, 28))
        instructionsTextView.autoPinEdge(.trailing, to: .trailing, of: containerView, withOffset: -.scaleFromIPhone5To7Plus(18, 28))
        instructionsTextView.autoPinEdge(.bottom, to: .bottom, of: scrollView, withOffset: -8)

        verifyUnverifyButton.autoHCenterInSuperview()
        verifyUnverifyButton.autoPinEdge(.top, to: .bottom, of: scrollView, withOffset: .scaleFromIPhone5To7Plus(12, 24))
        verifyUnverifyButton.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: .scaleFromIPhone5To7Plus(16, 40))

        instructionsTextView.autoPinEdge(.top, to: .bottom, of: fingerprintCard, withOffset: 24)

        updateVerificationStateLabel()
        setInstructionsText()
        setVerifyUnverifyButtonColors()
    }

    private func updateVerificationStateLabel() {
        let identityManager = DependenciesBridge.shared.identityManager
        isVerified = databaseStorage.read { tx in
            return identityManager.verificationState(for: SignalServiceAddress(recipientAci), tx: tx.asV2Read) == .verified
        }

        if isVerified {
            verifyUnverifyButtonLabel.text = NSLocalizedString(
                "PRIVACY_UNVERIFY_BUTTON",
                comment: "Button that lets user mark another user's identity as unverified."
            )
        } else {
            verifyUnverifyButtonLabel.text = OWSLocalizedString(
                "PRIVACY_VERIFY_BUTTON",
                comment: "Button that lets user mark another user's identity as verified."
            )
        }
        view.setNeedsLayout()
    }

    // MARK: - Fingerprint Card

    class FingerprintCard: UIView {

        private let fingerprint: OWSFingerprint
        private weak var controller: FingerprintViewController?

        init(fingerprint: OWSFingerprint, controller: FingerprintViewController) {
            self.fingerprint = fingerprint
            self.controller = controller
            super.init(frame: .zero)

            layer.cornerRadius = Constants.cornerRadius

            self.backgroundColor = UIColor(rgbHex: 0x506ecd)

            addSubview(shareButton)
            addSubview(qrCodeView)
            addSubview(safetyNumberLabel)

            shareButton.autoPinEdge(.top, to: .top, of: self, withOffset: 16)
            shareButton.autoPinEdge(.trailing, to: .trailing, of: self, withOffset: -16)

            qrCodeView.autoPinEdge(.top, to: .bottom, of: shareButton, withOffset: 8)
            // Set a minimum horizontal margin
            qrCodeView.autoPinEdge(.leading, to: .leading, of: self, withOffset: .scaleFromIPhone5To7Plus(44, 64), relation: .greaterThanOrEqual)
            qrCodeView.autoPinEdge(.trailing, to: .trailing, of: self, withOffset: -.scaleFromIPhone5To7Plus(44, 64), relation: .lessThanOrEqual)
            qrCodeView.autoHCenterInSuperview()

            safetyNumberLabel.autoPinEdge(.top, to: .bottom, of: qrCodeView, withOffset: 30)
            safetyNumberLabel.autoPinEdge(.leading, to: .leading, of: self, withOffset: .scaleFromIPhone5To7Plus(20, 35), relation: .greaterThanOrEqual)
            safetyNumberLabel.autoPinEdge(.trailing, to: .trailing, of: self, withOffset: -.scaleFromIPhone5To7Plus(20, 35), relation: .lessThanOrEqual)
            safetyNumberLabel.autoPinEdge(.bottom, to: .bottom, of: self, withOffset: -.scaleFromIPhone5To7Plus(27, 47))
            safetyNumberLabel.autoHCenterInSuperview()

            // Cap QR code width to the width of the safety number
            // Prevents it from being too large on iPad
            let qrCodeWidthConstraint = qrCodeView.widthAnchor.constraint(equalTo: safetyNumberLabel.widthAnchor)
            qrCodeWidthConstraint.priority = .defaultHigh
            qrCodeWidthConstraint.autoInstall()
            safetyNumberLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private lazy var shareButton: UIButton = {
            let button = UIButton()
            button.setTemplateImage(
                Theme.iconImage(.buttonShare).withRenderingMode(.alwaysTemplate),
                tintColor: .white
            )
            button.addTarget(self, action: #selector(didTapShare), for: .touchUpInside)
            return button
        }()

        private lazy var qrCodeView: UIView = {
            let containerView = UIView()
            containerView.backgroundColor = .white
            containerView.layer.cornerRadius = Constants.cornerRadius
            containerView.layer.masksToBounds = true

            let fingerprintImageView = UIImageView()
            fingerprintImageView.image = fingerprint.image
            // Don't antialias QR Codes.
            fingerprintImageView.layer.magnificationFilter = .nearest
            fingerprintImageView.layer.minificationFilter = .nearest
            fingerprintImageView.setCompressionResistanceLow()
            containerView.addSubview(fingerprintImageView)
            fingerprintImageView.autoPin(toAspectRatio: 1)
            fingerprintImageView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(margin: 20), excludingEdge: .bottom)

            let scanLabel = UILabel()
            scanLabel.text = NSLocalizedString("PRIVACY_TAP_TO_SCAN", comment: "Button that shows the 'scan with camera' view.")
            scanLabel.font = .systemFont(ofSize: .scaleFromIPhone5To7Plus(13, 15))
            scanLabel.textColor = Theme.lightThemeSecondaryTextAndIconColor
            containerView.addSubview(scanLabel)
            scanLabel.autoHCenterInSuperview()
            scanLabel.autoPinEdge(.top, to: .bottom, of: fingerprintImageView, withOffset: 12)
            scanLabel.autoPinEdge(.bottom, to: .bottom, of: containerView, withOffset: -14)

            containerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapToScan)))

            return containerView
        }()

        private lazy var safetyNumberLabel: UILabel = {
            let label = UILabel()
            label.text = fingerprint.displayableText
            label.font = UIFont(name: "Menlo-Regular", size: 23)
            label.textAlignment = .center
            label.textColor = .white
            label.numberOfLines = 3
            label.lineBreakMode = .byTruncatingTail
            label.adjustsFontSizeToFitWidth = true
            label.isUserInteractionEnabled = true
            label.accessibilityIdentifier = "FingerprintViewController.fingerprintLabel"
            label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapSafetyNumber)))
            return label
        }()

        @objc
        func didTapToScan() {
            controller?.didTapToScan()
        }

        @objc
        func didTapShare() {
            controller?.shareFingerprint(from: shareButton)
        }

        @objc
        func didTapSafetyNumber() {
            controller?.shareFingerprint(from: safetyNumberLabel)
        }

        enum Constants {
            static let cornerRadius: CGFloat = 18
        }
    }

    // MARK: PillBoxView

    class PillBoxView: UIView {
        override var bounds: CGRect {
            didSet {
                self.layer.cornerRadius = bounds.height / 2
            }
        }
    }

    // MARK: Actions

    @objc
    private func didTapDone() {
        dismiss(animated: true)
    }

    private func didTapLearnMore() {
        Self.showLearnMoreUrl(from: self)
    }

    fileprivate static func showLearnMoreUrl(from viewController: UIViewController) {
        let learnMoreUrl = URL(string: "https://support.signal.org/hc/articles/213134107")!
        let safariVC = SFSafariViewController(url: learnMoreUrl)
        viewController.present(safariVC, animated: true)
    }

    @objc
    private func didTapVerifyUnverify(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .recognized else { return }

        databaseStorage.write { tx in
            let identityManager = DependenciesBridge.shared.identityManager
            let newVerificationState: VerificationState = isVerified ? .implicit(isAcknowledged: false) : .verified
            identityManager.saveIdentityKey(identityKey, for: recipientAci, tx: tx.asV2Write)
            _ = identityManager.setVerificationState(
                newVerificationState,
                of: identityKey,
                for: SignalServiceAddress(recipientAci),
                isUserInitiatedChange: true,
                tx: tx.asV2Write
            )
        }

        dismiss(animated: true)
    }

    private func shareFingerprint(from fromView: UIView) {
        let compareActivity = CompareSafetyNumbersActivity(delegate: self)

        let shareFormat = NSLocalizedString(
            "SAFETY_NUMBER_SHARE_FORMAT",
            comment: "Snippet to share {{safety number}} with a friend. sent e.g. via SMS"
        )
        let shareString = String(format: shareFormat, fingerprint.displayableText)

        let activityController = UIActivityViewController(
            activityItems: [ shareString ],
            applicationActivities: [ compareActivity ]
        )

        if let popoverPresentationController = activityController.popoverPresentationController {
            popoverPresentationController.sourceView = fromView
        }

        // This value was extracted by inspecting `activityType` in the activityController.completionHandler
        let iCloudActivityType = "com.apple.CloudDocsUI.AddToiCloudDrive"
        activityController.excludedActivityTypes = [
            .postToFacebook,
            .postToWeibo,
            .airDrop,
            .postToTwitter,
            .init(rawValue: iCloudActivityType) // This isn't being excluded. RADAR https://openradar.appspot.com/27493621
        ]

        present(activityController, animated: true)
    }

    fileprivate func didTapToScan() {
        let viewController = FingerprintScanViewController(
            recipientAci: recipientAci,
            recipientIdentity: recipientIdentity,
            fingerprint: self.fingerprint
        )
        navigationController?.pushViewController(viewController, animated: true)
    }

    // MARK: Notifications

    private var identityStateChangeObserver: Any?

    private func identityStateDidChange() {
        AssertIsOnMainThread()
        updateVerificationStateLabel()
    }

    // MARK: - Constants

    enum Constants {
        static let cardHInset: CGFloat = .scaleFromIPhone5To7Plus(30, 53)
        static let learnMoreUrl = "https://support.signal.org/learnMore"
    }
}

extension FingerprintViewController: CompareSafetyNumbersActivityDelegate {

    public func compareSafetyNumbersActivitySucceeded(activity: CompareSafetyNumbersActivity) {
        FingerprintScanViewController.showVerificationSucceeded(
            from: self,
            identityKey: identityKey,
            recipientAci: recipientAci,
            contactName: fingerprint.theirName,
            tag: logTag
        )
    }

    public func compareSafetyNumbersActivity(_ activity: CompareSafetyNumbersActivity, failedWithError error: Error) {
        let isUserError = (error as NSError).code == OWSErrorCode.userError.rawValue

        FingerprintScanViewController.showVerificationFailed(
            from: self,
            isUserError: isUserError,
            localizedErrorDescription: error.userErrorDescription,
            tag: logTag
        )
    }

}

extension FingerprintViewController: UITextViewDelegate {
    public func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if URL.absoluteString == Constants.learnMoreUrl {
            self.didTapLearnMore()
        }
        return false
    }
}
