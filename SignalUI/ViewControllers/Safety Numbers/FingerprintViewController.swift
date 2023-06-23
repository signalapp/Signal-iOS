//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalMessaging
import SignalServiceKit
import UIKit

public class FingerprintViewController: OWSViewController {

    private let recipientAddress: SignalServiceAddress
    private let recipientIdentity: OWSRecipientIdentity
    private let contactName: String
    private let identityKey: IdentityKey
    private let fingerprint: OWSFingerprint

    private lazy var shareBarButtonItem = UIBarButtonItem(
        image: Theme.iconImage(.buttonShare),
        style: .plain,
        target: self,
        action: #selector(didTapShare),
        accessibilityIdentifier: "FingerprintViewController.share"
    )

    public class func present(from viewController: UIViewController, address: SignalServiceAddress) {
        owsAssertBeta(address.isValid)

        let canRenderSafetyNumber: Bool
        if RemoteConfig.uuidSafetyNumbers {
            canRenderSafetyNumber = address.uuid != nil
        } else {
            canRenderSafetyNumber = address.phoneNumber != nil
        }

        guard let recipientIdentity = OWSIdentityManager.shared.recipientIdentity(for: address),
              canRenderSafetyNumber,
              let fingerprintViewController = FingerprintViewController(recipientAddress: address, recipientIdentity: recipientIdentity)
        else {
            OWSActionSheets.showActionSheet(
                title: NSLocalizedString("CANT_VERIFY_IDENTITY_ALERT_TITLE",
                                         comment: "Title for alert explaining that a user cannot be verified."),
                message: NSLocalizedString("CANT_VERIFY_IDENTITY_ALERT_MESSAGE",
                                           comment: "Message for alert explaining that a user cannot be verified.")
            )
            return
        }

        let navigationController = OWSNavigationController(rootViewController: fingerprintViewController)
        viewController.presentFormSheet(navigationController, animated: true)
    }

    private init?(recipientAddress: SignalServiceAddress, recipientIdentity: OWSRecipientIdentity) {
        self.recipientAddress = recipientAddress
        self.contactName = SSKEnvironment.shared.contactsManagerRef.displayName(for: recipientAddress)
        // By capturing the identity key when we enter these views, we prevent the edge case
        // where the user verifies a key that we learned about while this view was open.
        self.recipientIdentity = recipientIdentity
        self.identityKey = recipientIdentity.identityKey
        guard let fingerprint = OWSFingerprintBuilder(
            accountManager: TSAccountManager.shared,
            contactsManager: SSKEnvironment.shared.contactsManagerRef
        ).fingerprint(theirSignalAddress: recipientAddress, theirIdentityKey: recipientIdentity.identityKey) else {
            return nil
        }
        self.fingerprint = fingerprint

        super.init()

        title = NSLocalizedString("PRIVACY_VERIFICATION_TITLE", comment: "Navbar title")
        navigationItem.leftBarButtonItem = .init(
            barButtonSystemItem: .stop,
            target: self, action: #selector(didTapStop),
            accessibilityIdentifier: "FingerprintViewController.stop"
        )
        navigationItem.rightBarButtonItem = shareBarButtonItem

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

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.backgroundColor

        configureUI()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        view.backgroundColor = Theme.backgroundColor
    }

    // MARK: UI

    private lazy var verifyUnverifyButtonLabel = UILabel()
    private lazy var verificationStateLabel = UILabel()

    private func configureUI() {

        // Verify/Unverify button
        let verifyUnverifyButton = UIView()
        verifyUnverifyButton.accessibilityIdentifier = "FingerprintViewController.verifyUnverifyButton"
        verifyUnverifyButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapVerifyUnverify)))
        view.addSubview(verifyUnverifyButton)
        verifyUnverifyButton.autoPinWidthToSuperview()
        verifyUnverifyButton.autoPin(toBottomLayoutGuideOf: self, withInset: 0)

        let verifyUnverifyPillbox = UIView()
        verifyUnverifyPillbox.backgroundColor = .ows_accentBlue
        verifyUnverifyPillbox.layer.cornerRadius = 3
        verifyUnverifyPillbox.layer.masksToBounds = true
        verifyUnverifyButton.addSubview(verifyUnverifyPillbox)
        verifyUnverifyPillbox.autoHCenterInSuperview()
        verifyUnverifyPillbox.autoPinEdge(toSuperviewEdge: .top, withInset: ScaleFromIPhone5To7Plus(10, 15))
        verifyUnverifyPillbox.autoPinEdge(toSuperviewEdge: .bottom, withInset: ScaleFromIPhone5To7Plus(10, 20))

        verifyUnverifyButtonLabel.font = .systemFont(ofSize: ScaleFromIPhone5To7Plus(14, 20), weight: .semibold)
        verifyUnverifyButtonLabel.textColor = .white
        verifyUnverifyButtonLabel.textAlignment = .center
        verifyUnverifyPillbox.addSubview(verifyUnverifyButtonLabel)
        verifyUnverifyButtonLabel.autoPinWidthToSuperview(withMargin: 50)
        verifyUnverifyButtonLabel.autoPinHeightToSuperview(withMargin: 8)

        // Learn More
        let learnMoreButton = UIView()
        learnMoreButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapLearnMore)))
        view.addSubview(learnMoreButton)
        learnMoreButton.autoPinWidthToSuperviewMargins()
        learnMoreButton.autoPinEdge(.bottom, to: .top, of: verifyUnverifyButton)
        learnMoreButton.accessibilityIdentifier = "FingerprintViewController.learnMoreButton"

        let learnMoreLabel = UILabel()
        learnMoreLabel.attributedText = NSAttributedString(
            string: CommonStrings.learnMore,
            attributes: [ .underlineStyle: NSUnderlineStyle.single ]
        )
        learnMoreLabel.font = .systemFont(ofSize: ScaleFromIPhone5To7Plus(13, 16))
        learnMoreLabel.textColor = Theme.accentBlueColor
        learnMoreLabel.textAlignment = .center
        learnMoreButton.addSubview(learnMoreLabel)
        learnMoreLabel.autoPinWidthToSuperview()
        learnMoreLabel.autoPinEdge(toSuperviewEdge: .top, withInset: ScaleFromIPhone5To7Plus(5, 10))
        learnMoreLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: ScaleFromIPhone5To7Plus(5, 10))

        // Instructions
        let instructionsFormat = NSLocalizedString(
            "PRIVACY_VERIFICATION_INSTRUCTIONS",
            comment: "Paragraph(s) shown alongside the safety number when verifying privacy with {{contact name}}"
        )
        let instructionsLabel = UILabel()
        instructionsLabel.text = String(format: instructionsFormat, contactName)
        instructionsLabel.font = .systemFont(ofSize: ScaleFromIPhone5To7Plus(11, 14))
        instructionsLabel.textColor = Theme.secondaryTextAndIconColor
        instructionsLabel.textAlignment = .center
        instructionsLabel.numberOfLines = 0
        instructionsLabel.lineBreakMode = .byWordWrapping
        view.addSubview(instructionsLabel)
        instructionsLabel.autoPinWidthToSuperviewMargins()
        instructionsLabel.autoPinEdge(.bottom, to: .top, of: learnMoreButton)

        // Fingerprint Label
        let fingerprintLabel = UILabel()
        fingerprintLabel.text = fingerprint.displayableText
        fingerprintLabel.font = UIFont(name: "Menlo-Regular", size: ScaleFromIPhone5To7Plus(20, 23))
        fingerprintLabel.textAlignment = .center
        fingerprintLabel.textColor = Theme.secondaryTextAndIconColor
        fingerprintLabel.numberOfLines = 3
        fingerprintLabel.lineBreakMode = .byTruncatingTail
        fingerprintLabel.adjustsFontSizeToFitWidth = true
        fingerprintLabel.isUserInteractionEnabled = true
        fingerprintLabel.accessibilityIdentifier = "FingerprintViewController.fingerprintLabel"
        fingerprintLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapFingerprintLabel)))
        view.addSubview(fingerprintLabel)
        fingerprintLabel.autoPinWidthToSuperview(withMargin: ScaleFromIPhone5To7Plus(50, 60))
        fingerprintLabel.autoPinEdge(.bottom, to: .top, of: instructionsLabel, withOffset: -ScaleFromIPhone5To7Plus(8, 15))

        // Fingerprint Image
        let fingerprintView = UIView()
        fingerprintView.isUserInteractionEnabled = true
        fingerprintView.accessibilityIdentifier = "FingerprintViewController.fingerprintView"
        view.addSubview(fingerprintView)
        fingerprintView.autoPinWidthToSuperviewMargins()
        fingerprintView.autoPinEdge(.bottom, to: .top, of: fingerprintLabel, withOffset: -ScaleFromIPhone5To7Plus(10, 15))
        fingerprintView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapFingerprintView)))

        let fingerprintCircle = CircleView()
        fingerprintCircle.backgroundColor = Theme.washColor
        fingerprintView.addSubview(fingerprintCircle)
        fingerprintCircle.autoPin(toAspectRatio: 1)
        fingerprintCircle.autoCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            fingerprintCircle.autoPinEdgesToSuperviewEdges()
        }

        let fingerprintImageView = UIImageView()
        fingerprintImageView.image = fingerprint.image
        // Don't antialias QR Codes.
        fingerprintImageView.layer.magnificationFilter = .nearest
        fingerprintImageView.layer.minificationFilter = .nearest
        fingerprintImageView.setCompressionResistanceLow()
        fingerprintView.addSubview(fingerprintImageView)
        fingerprintImageView.autoCenterInSuperview()
        fingerprintImageView.autoPin(toAspectRatio: 1)
        fingerprintImageView.widthAnchor.constraint(equalTo: fingerprintCircle.widthAnchor, multiplier: 0.675).isActive = true

        let scanLabel = UILabel()
        scanLabel.text = NSLocalizedString("PRIVACY_TAP_TO_SCAN", comment: "Button that shows the 'scan with camera' view.")
        scanLabel.font = .systemFont(ofSize: ScaleFromIPhone5To7Plus(14, 16), weight: .semibold)
        scanLabel.textColor = Theme.secondaryTextAndIconColor
        fingerprintView.addSubview(scanLabel)
        scanLabel.autoHCenterInSuperview()
        scanLabel.autoPinEdge(.top, to: .bottom, of: fingerprintImageView)
        scanLabel.autoPinEdge(.bottom, to: .bottom, of: fingerprintCircle, withOffset: -4)

        // Verification State
        verificationStateLabel.font = .systemFont(ofSize: ScaleFromIPhone5To7Plus(16, 20), weight: .semibold)
        verificationStateLabel.textColor = Theme.secondaryTextAndIconColor
        verificationStateLabel.textAlignment = .center
        verificationStateLabel.numberOfLines = 0
        verificationStateLabel.lineBreakMode = .byWordWrapping
        view.addSubview(verificationStateLabel)
        verificationStateLabel.autoPinWidthToSuperviewMargins()
        // Bind height of label to height of two lines of text.
        // This should always be sufficient, and will prevent the view's
        // layout from changing if the user is marked as verified or not
        // verified.
        verificationStateLabel.autoSetDimension(.height, toSize: round(verificationStateLabel.font.lineHeight * 2.25))
        verificationStateLabel.autoPin(toTopLayoutGuideOf: self, withInset: ScaleFromIPhone5To7Plus(15, 20))
        verificationStateLabel.autoPinEdge(.bottom, to: .top, of: fingerprintView, withOffset: -ScaleFromIPhone5To7Plus(10, 15))

        updateVerificationStateLabel()
    }

    private func updateVerificationStateLabel() {
        owsAssertBeta(recipientAddress.isValid)

        let isVerified = OWSIdentityManager.shared.verificationState(for: recipientAddress) == .verified

        let symbolFont = UIFont.awesomeFont(ofSize: verificationStateLabel.font.pointSize)
        let checkmark = NSAttributedString(string: LocalizationNotNeeded("\u{F00C} "), attributes: [ .font: symbolFont ])

        if isVerified {
            verificationStateLabel.attributedText = checkmark.stringByAppendingString(NSAttributedString(string: String(
                format: NSLocalizedString(
                    "PRIVACY_IDENTITY_IS_VERIFIED_FORMAT",
                    comment: "Label indicating that the user is verified. Embeds  user's name or phone number}}."
                ),
                contactName
            )))

            verifyUnverifyButtonLabel.text = NSLocalizedString(
                "PRIVACY_UNVERIFY_BUTTON",
                comment: "Button that lets user mark another user's identity as unverified."
            )
        } else {
            verificationStateLabel.text = String(
                format: NSLocalizedString(
                    "PRIVACY_IDENTITY_IS_NOT_VERIFIED_FORMAT",
                    comment: "Label indicating that the user is not verified. Embeds {{the user's name or phone number}}."
                ),
                contactName
            )

            verifyUnverifyButtonLabel.attributedText = checkmark.stringByAppendingString(NSAttributedString(
                string: NSLocalizedString(
                    "PRIVACY_VERIFY_BUTTON",
                    comment: "Button that lets user mark another user's identity as verified."
                )
            ))
        }

        view.setNeedsLayout()
    }

    // MARK: Actions

    @objc
    private func didTapStop() {
        dismiss(animated: true)
    }

    @objc
    private func didTapShare() {
        shareFingerprint()
    }

    @objc
    private func didTapVerifyUnverify(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .recognized else { return }

        databaseStorage.write { transaction in
            let isVerified = OWSIdentityManager.shared.verificationState(for: recipientAddress, transaction: transaction) == .verified
            let newVerificationState: OWSVerificationState = isVerified ? .default : .verified
            OWSIdentityManager.shared.setVerificationState(
                newVerificationState,
                identityKey: identityKey,
                address: recipientAddress,
                isUserInitiatedChange: true,
                transaction: transaction
            )
        }

        dismiss(animated: true)
    }

    @objc
    private func didTapLearnMore(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .recognized else { return }

        let learnMoreUrl = URL(string: "https://support.signal.org/hc/articles/213134107")!
        let safariVC = SFSafariViewController(url: learnMoreUrl)
        present(safariVC, animated: true)
    }

    @objc
    private func didTapFingerprintLabel(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .recognized else { return }

        shareFingerprint()
    }

    @objc
    private func didTapFingerprintView(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .recognized else { return }

        showScanner()
    }

    private func shareFingerprint() {
        Logger.debug("Sharing safety numbers")

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
            popoverPresentationController.barButtonItem = shareBarButtonItem
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

    private func showScanner() {
        guard let viewController = FingerprintScanViewController(recipientAddress: recipientAddress, recipientIdentity: recipientIdentity) else {
            owsFailDebug("Unable to create fingerprint")
            return
        }
        navigationController?.pushViewController(viewController, animated: true)
    }

    // MARK: Notifications

    private var identityStateChangeObserver: Any?

    private func identityStateDidChange() {
        AssertIsOnMainThread()
        updateVerificationStateLabel()
    }
}

extension FingerprintViewController: CompareSafetyNumbersActivityDelegate {

    public func compareSafetyNumbersActivitySucceeded(activity: CompareSafetyNumbersActivity) {
        FingerprintScanViewController.showVerificationSucceeded(
            from: self,
            identityKey: identityKey,
            recipientAddress: recipientAddress,
            contactName: contactName,
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
