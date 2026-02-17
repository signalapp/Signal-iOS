//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient
import Lottie
import PureLayout
import SafariServices
import SignalServiceKit
import UIKit

public class FingerprintViewController: OWSViewController, OWSNavigationChildController {

    public class func present(
        for theirAci: Aci?,
        from viewController: UIViewController,
    ) {
        struct FingerprintResult {
            let theirAci: Aci
            let theirRecipientIdentity: OWSRecipientIdentity
            let theirVerificationState: VerificationState
            let fingerprint: OWSFingerprint
        }

        let contactsManager = SSKEnvironment.shared.contactManagerRef
        let db = DependenciesBridge.shared.db
        let identityManager = DependenciesBridge.shared.identityManager
        let keyTransparencyManager = DependenciesBridge.shared.keyTransparencyManager
        let keyTransparencyStore = KeyTransparencyStore()
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        let fingerprintResult: FingerprintResult?
        let keyTransparencyState: KeyTransparencyState?
        let keyTransparencyShouldShowEducation: Bool
        (
            fingerprintResult,
            keyTransparencyState,
            keyTransparencyShouldShowEducation,
        ) = db.read { tx in
            guard let theirAci else {
                return (nil, nil, false)
            }

            let theirAddress = SignalServiceAddress(theirAci)
            let theirName = contactsManager.displayName(for: theirAddress, tx: tx).resolvedValue()
            let theirVerificationState = identityManager.verificationState(for: theirAddress, tx: tx)

            guard
                let theirRecipientIdentity = identityManager.recipientIdentity(for: theirAddress, tx: tx),
                let theirAciIdentityKey = try? theirRecipientIdentity.identityKeyObject,
                let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx),
                let myAciIdentityKey = identityManager.identityKeyPair(for: .aci, tx: tx)?.keyPair.identityKey
            else {
                return (nil, nil, false)
            }

            let keyTransparencyIsEnabled = keyTransparencyManager.isEnabled(tx: tx)
            let keyTransparencyCheckParams = keyTransparencyManager.prepareCheck(
                aci: theirAci,
                localIdentifiers: localIdentifiers,
                tx: tx,
            )
            let keyTransparencyShouldShowEducation = keyTransparencyStore.shouldShowFirstTimeEducation(tx: tx)

            return (
                FingerprintResult(
                    theirAci: theirAci,
                    theirRecipientIdentity: theirRecipientIdentity,
                    theirVerificationState: theirVerificationState,
                    fingerprint: OWSFingerprint(
                        myAci: localIdentifiers.aci,
                        theirAci: theirAci,
                        myAciIdentityKey: myAciIdentityKey,
                        theirAciIdentityKey: theirAciIdentityKey,
                        theirName: theirName,
                    ),
                ),
                KeyTransparencyState(
                    isEnabled: keyTransparencyIsEnabled,
                    checkParams: keyTransparencyCheckParams,
                    viewInitialState: keyTransparencyCheckParams == nil ? .unableToVerify : .readyToVerify,
                ),
                keyTransparencyShouldShowEducation,
            )
        }

        guard let fingerprintResult, let keyTransparencyState else {
            let actionSheet = ActionSheetController(message: OWSLocalizedString(
                "CANT_VERIFY_IDENTITY_EXCHANGE_MESSAGES",
                comment: "Alert shown when the user needs to exchange messages to see the safety number.",
            ))

            actionSheet.addAction(.init(title: CommonStrings.learnMore, style: .default, handler: { _ in
                guard let vc = CurrentAppContext().frontmostViewController() else {
                    return
                }
                Self.showUrl(URL.Support.safetyNumbers, from: vc)
            }))
            actionSheet.addAction(OWSActionSheets.cancelAction)

            viewController.presentActionSheet(actionSheet)
            return
        }

        let fingerprintViewController = FingerprintViewController(
            recipientAci: fingerprintResult.theirAci,
            recipientIdentity: fingerprintResult.theirRecipientIdentity,
            recipientVerificationState: fingerprintResult.theirVerificationState,
            fingerprint: fingerprintResult.fingerprint,
            keyTransparencyState: keyTransparencyState,
            deps: FingerprintViewController.Deps(
                db: db,
                identityManager: identityManager,
                keyTransparencyManager: keyTransparencyManager,
            ),
        )
        let navigationController = OWSNavigationController(rootViewController: fingerprintViewController)

        if keyTransparencyShouldShowEducation {
            let educationSheet = KeyTransparencyFirstTimeEducationHeroSheet {
                db.write { tx in
                    keyTransparencyStore.setShouldShowFirstTimeEducation(false, tx: tx)
                }

                viewController.present(navigationController, animated: true)
            }
            viewController.present(educationSheet, animated: true)
        } else {
            viewController.present(navigationController, animated: true)
        }
    }

    // MARK: -

    fileprivate struct Deps {
        let db: DB
        let identityManager: OWSIdentityManager
        let keyTransparencyManager: KeyTransparencyManager
    }

    fileprivate struct KeyTransparencyState {
        let isEnabled: Bool
        let checkParams: KeyTransparencyManager.CheckParams?
        let viewInitialState: KeyTransparencyView.State
    }

    private let recipientAci: Aci
    private let recipientIdentity: OWSRecipientIdentity
    private let recipientVerificationState: VerificationState
    private let fingerprint: OWSFingerprint
    private let keyTransparencyState: KeyTransparencyState

    private let deps: Deps?
    private var identityStateChangeObserver: AnyObject?

    fileprivate init(
        recipientAci: Aci,
        recipientIdentity: OWSRecipientIdentity,
        recipientVerificationState: VerificationState,
        fingerprint: OWSFingerprint,
        keyTransparencyState: KeyTransparencyState,
        deps: Deps?,
    ) {
        // We snapshot state when we present this view and dismiss the view when
        // there's an identity change, to avoid edge cases related to state
        // changing while this view is presented. (E.g., you verified them on
        // another device; you learned their identity key changed; etc.)
        self.recipientAci = recipientAci
        self.recipientIdentity = recipientIdentity
        self.recipientVerificationState = recipientVerificationState
        self.fingerprint = fingerprint
        self.keyTransparencyState = keyTransparencyState

        self.deps = deps

        super.init()

        title = NSLocalizedString("PRIVACY_VERIFICATION_TITLE", comment: "Navbar title")
        navigationItem.rightBarButtonItem = .doneButton(dismissingFrom: self)

        identityStateChangeObserver = NotificationCenter.default.addObserver(
            forName: .identityStateDidChange,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.dismiss(animated: true)
        }
    }

    deinit {
        if let identityStateChangeObserver {
            NotificationCenter.default.removeObserver(identityStateChangeObserver)
        }
    }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .solid
    }

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .Signal.groupedBackground
        configureUI()
    }

    // MARK: UI

    private lazy var fingerprintCard = FingerprintCard(
        fingerprint: fingerprint,
        theirVerificationState: recipientVerificationState,
        controller: self,
    )

    private lazy var instructionsTextView: UITextView = {
        let instructions = String(
            format: OWSLocalizedString(
                "VERIFY_SAFETY_NUMBER_INSTRUCTIONS",
                comment: "Instructions for verifying your safety number. Embeds {{contact's name}}",
            ),
            fingerprint.theirName,
        )
        // Link doesn't matter, we will override tap behavior.
        let learnMore = CommonStrings.learnMore.styled(with: .link(URL(string: "https://signal.org")!))

        let textView = LinkingTextView { [weak self] in
            self?.didTapSafetyNumbersLearnMore()
        }
        textView.attributedText = NSAttributedString.composed(of: [
            instructions,
            " ",
            learnMore,
        ]).styled(
            with: .font(.dynamicTypeFootnote),
            .color(.Signal.secondaryLabel),
            .alignment(.center),
        )
        textView.linkTextAttributes = [.foregroundColor: UIColor.Signal.label]

        return textView
    }()

    private lazy var keyTransparencyView = KeyTransparencyView(
        initialState: keyTransparencyState.viewInitialState,
        controller: self,
    )

    private func configureUI() {
        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()

        let containerView = UIView()
        scrollView.addSubview(containerView)
        containerView.autoPinEdges(toEdgesOf: scrollView)
        containerView.autoPinWidth(toWidthOf: view)

        containerView.addSubview(fingerprintCard)
        containerView.addSubview(instructionsTextView)
        if keyTransparencyState.isEnabled {
            containerView.addSubview(keyTransparencyView)
        }

        fingerprintCard.autoPinEdge(toSuperviewSafeArea: .top, withInset: 10)
        fingerprintCard.autoPinWidth(toWidthOf: containerView, offset: -.scaleFromIPhone5To7Plus(60, 105))
        fingerprintCard.autoHCenterInSuperview()

        instructionsTextView.autoPinEdge(.top, to: .bottom, of: fingerprintCard, withOffset: 24)
        instructionsTextView.autoPinEdge(.leading, to: .leading, of: containerView, withOffset: .scaleFromIPhone5To7Plus(18, 28))
        instructionsTextView.autoPinEdge(.trailing, to: .trailing, of: containerView, withOffset: -.scaleFromIPhone5To7Plus(18, 28))

        if keyTransparencyState.isEnabled {
            keyTransparencyView.autoPinEdge(.top, to: .bottom, of: instructionsTextView, withOffset: 44)
            keyTransparencyView.autoPinEdge(.leading, to: .leading, of: containerView, withOffset: 16)
            keyTransparencyView.autoPinEdge(.trailing, to: .trailing, of: containerView, withOffset: -16)
            keyTransparencyView.autoPinEdge(.bottom, to: .bottom, of: scrollView, withOffset: -8)
        } else {
            instructionsTextView.autoPinEdge(.bottom, to: .bottom, of: scrollView, withOffset: -8)
        }
    }

    // MARK: - Fingerprint Card

    private final class FingerprintCard: UIView {
        private let fingerprint: OWSFingerprint
        private let theirVerificationState: VerificationState
        private weak var controller: FingerprintViewController?

        init(
            fingerprint: OWSFingerprint,
            theirVerificationState: VerificationState,
            controller: FingerprintViewController,
        ) {
            self.fingerprint = fingerprint
            self.theirVerificationState = theirVerificationState
            self.controller = controller
            super.init(frame: .zero)

            layer.cornerRadius = Constants.cornerRadius

            self.backgroundColor = UIColor(rgbHex: 0x506ecd)

            addSubview(shareButton)
            addSubview(qrCodeView)
            addSubview(safetyNumberLabel)
            addSubview(verifyUnverifyButton)

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
            safetyNumberLabel.autoHCenterInSuperview()

            verifyUnverifyButton.autoPinEdge(.top, to: .bottom, of: safetyNumberLabel, withOffset: 30)
            verifyUnverifyButton.autoPinEdge(.leading, to: .leading, of: self, withOffset: .scaleFromIPhone5To7Plus(20, 35), relation: .greaterThanOrEqual)
            verifyUnverifyButton.autoPinEdge(.trailing, to: .trailing, of: self, withOffset: -.scaleFromIPhone5To7Plus(20, 35), relation: .lessThanOrEqual)
            verifyUnverifyButton.autoHCenterInSuperview()
            verifyUnverifyButton.autoPinEdge(.bottom, to: .bottom, of: self, withOffset: -20)

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
                UIImage(named: "share"),
                tintColor: .white,
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
            scanLabel.textColor = .Signal.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            scanLabel.numberOfLines = 0
            scanLabel.textAlignment = .center
            containerView.addSubview(scanLabel)
            scanLabel.autoPinWidthToSuperviewMargins()
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
            label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapSafetyNumber)))
            return label
        }()

        private lazy var verifyUnverifyButton: UIButton = {
            let lightTheme = UITraitCollection(userInterfaceStyle: .light)

            var configuration = UIButton.Configuration.filled()
            configuration.titleAlignment = .center
            configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadlineClamped.semibold())
            configuration.baseBackgroundColor = .Signal.background.resolvedColor(with: lightTheme)
            configuration.baseForegroundColor = .Signal.label.resolvedColor(with: lightTheme)
            configuration.contentInsets = NSDirectionalEdgeInsets(hMargin: 16, vMargin: 12)
            configuration.cornerStyle = .capsule

            switch theirVerificationState {
            case .verified:
                configuration.title = OWSLocalizedString(
                    "PRIVACY_UNVERIFY_BUTTON",
                    comment: "Button that lets user mark another user's identity as unverified.",
                )
            case .noLongerVerified, .implicit:
                configuration.title = OWSLocalizedString(
                    "PRIVACY_VERIFY_BUTTON",
                    comment: "Button that lets user mark another user's identity as verified.",
                )
            }

            return UIButton(
                configuration: configuration,
                primaryAction: UIAction { [weak self] _ in
                    self?.controller?.didTapVerifyUnverify()
                },
            )
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

        private enum Constants {
            static let cornerRadius: CGFloat = 18
        }
    }

    // MARK: -

    fileprivate final class KeyTransparencyView: UIView {
        enum State {
            case unableToVerify
            case readyToVerify
            case verifying
            case verifiedSuccess
            case verifiedFailure
        }

        var state: State {
            didSet { updateForCurrentState() }
        }

        private weak var controller: FingerprintViewController?

        init(
            initialState: State,
            controller: FingerprintViewController,
        ) {
            self.state = initialState
            self.controller = controller
            super.init(frame: .zero)

            addSubview(sectionHeaderLabel)
            addSubview(verifyButton)
            addSubview(footerTextView)

            sectionHeaderLabel.autoPinEdge(toSuperviewEdge: .top, withInset: 12)
            sectionHeaderLabel.autoPinEdge(toSuperviewEdge: .leading, withInset: 26)
            sectionHeaderLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 26)

            verifyButton.autoPinEdge(.top, to: .bottom, of: sectionHeaderLabel, withOffset: 10)
            verifyButton.autoPinEdge(toSuperviewEdge: .leading, withInset: 16)
            verifyButton.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)

            footerTextView.autoPinEdge(.top, to: .bottom, of: verifyButton, withOffset: 12)
            footerTextView.autoPinEdge(toSuperviewEdge: .leading, withInset: 32)
            footerTextView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 32)
            footerTextView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 24)

            updateForCurrentState()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func updateForCurrentState() {
            let leadingView: UIView
            let titleText: String
            let foregroundColor: UIColor
            let showChevron: Bool
            switch state {
            case .readyToVerify:
                leadingView = verifyButtonLeadingViewKey
                titleText = OWSLocalizedString(
                    "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_BUTTON_VERIFY",
                    comment: "Title for a button offering automatic key verification.",
                )
                foregroundColor = .Signal.label
                showChevron = false
            case .verifying:
                leadingView = verifyButtonLeadingViewSpinner
                titleText = OWSLocalizedString(
                    "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_BUTTON_VERIFYING",
                    comment: "Title for a button while automatic key verification is ongoing.",
                )
                foregroundColor = .Signal.label
                showChevron = false
            case .verifiedSuccess:
                leadingView = verifyButtonLeadingViewSuccess
                titleText = OWSLocalizedString(
                    "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_BUTTON_VERIFY_SUCCESS",
                    comment: "Title for a button when automatic key verification succeeds.",
                )
                foregroundColor = .Signal.label
                showChevron = true
            case .verifiedFailure, .unableToVerify:
                leadingView = verifyButtonLeadingViewFailure
                titleText = OWSLocalizedString(
                    "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_BUTTON_VERIFY_FAILURE",
                    comment: "Title for a button when automatic key verification fails.",
                )
                foregroundColor = .Signal.secondaryLabel
                showChevron = true
            }

            for view in verifyButtonLeadingViews {
                view.isHidden = view !== leadingView
            }
            verifyButton.configuration!.title = titleText
            verifyButton.configuration!.baseForegroundColor = foregroundColor
            if showChevron {
                verifyButton.configuration!.image = UIImage(named: "chevron-right-20")!
                verifyButton.contentHorizontalAlignment = .fill
            } else {
                verifyButton.configuration!.image = nil
                verifyButton.contentHorizontalAlignment = .leading
            }
        }

        // MARK: - Views

        private static let leadingViewSize: CGFloat = 24

        private lazy var sectionHeaderLabel: UILabel = {
            let label = UILabel()
            label.text = OWSLocalizedString(
                "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_HEADER",
                comment: "Header for automatic key verification",
            )
            label.font = .dynamicTypeBody.semibold()
            label.textColor = .Signal.label
            label.numberOfLines = 0
            return label
        }()

        private lazy var verifyButtonLeadingViewKey: UIImageView = {
            let imageView = UIImageView(image: UIImage(named: "key")!)
            imageView.tintColor = .Signal.label
            return imageView
        }()

        private lazy var verifyButtonLeadingViewSpinner: UIActivityIndicatorView = {
            let view = UIActivityIndicatorView(style: .medium)
            view.startAnimating()
            return view
        }()

        private lazy var verifyButtonLeadingViewSuccess: UIImageView = {
            let imageView = UIImageView(image: UIImage(named: "check-circle-fill")!)
            imageView.tintColor = .Signal.green
            return imageView
        }()

        private lazy var verifyButtonLeadingViewFailure: UIImageView = {
            let imageView = UIImageView(image: UIImage(named: "info")!)
            imageView.tintColor = .Signal.secondaryLabel
            return imageView
        }()

        private var verifyButtonLeadingViews: [UIView] {
            [
                verifyButtonLeadingViewKey,
                verifyButtonLeadingViewSpinner,
                verifyButtonLeadingViewSuccess,
                verifyButtonLeadingViewFailure,
            ]
        }

        private lazy var verifyButton: UIButton = {
            // Define overall insets for the button, with extra inset at the
            // leading edge since we'll be manually overlaying a view there.
            let inset: CGFloat = 16
            var buttonInsets = NSDirectionalEdgeInsets(margin: inset)
            buttonInsets.leading += Self.leadingViewSize + 12

            // This configuration is updated in updateForCurrentState() as well.
            var configuration = UIButton.Configuration.filled()
            configuration.imagePadding = 12
            configuration.imagePlacement = .trailing
            configuration.contentInsets = buttonInsets
            configuration.baseBackgroundColor = .Signal.tertiaryBackground
            configuration.cornerStyle = .capsule
            configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeBody)

            let button = UIButton(
                configuration: configuration,
                primaryAction: UIAction { [weak self] _ in
                    guard let self else { return }
                    controller?.didTapKeyTransparencyButton(state: state)
                },
            )

            for view in verifyButtonLeadingViews {
                button.addSubview(view)
                view.autoSetDimensions(to: .square(Self.leadingViewSize))
                view.autoPinEdge(.leading, to: .leading, of: button, withOffset: inset)
                view.autoVCenterInSuperview()
            }

            return button
        }()

        private lazy var footerTextView: LinkingTextView = {
            let textView = LinkingTextView { [weak self] in
                self?.controller?.didTapKeyTransparencyLearnMore()
            }

            let footerText = OWSLocalizedString(
                "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_FOOTER",
                comment: "Footer explaining that automatic verification is not available for all chats",
            )

            // Link doesn't matter, we override tap behavior
            let learnMoreLink = CommonStrings.learnMore.styled(with: .link(URL(string: "https://signal.org")!))

            textView.attributedText = NSAttributedString.composed(of: [
                footerText,
                " ",
                learnMoreLink,
            ]).styled(
                with: .font(.dynamicTypeCaption1),
                .color(.Signal.secondaryLabel),
            )
            textView.linkTextAttributes = [.foregroundColor: UIColor.Signal.label]

            return textView
        }()
    }

    // MARK: -

    private func didTapSafetyNumbersLearnMore() {
        Self.showUrl(URL.Support.safetyNumbers, from: self)
    }

    fileprivate func didTapKeyTransparencyLearnMore() {
        Self.showUrl(URL.Support.keyTransparency, from: self)
    }

    fileprivate static func showUrl(_ url: URL, from viewController: UIViewController) {
        let safariVC = SFSafariViewController(url: url)
        viewController.present(safariVC, animated: true)
    }

    fileprivate func didTapVerifyUnverify() {
        guard let deps else { return }

        deps.db.write { tx in
            let identityKey = fingerprint.theirAciIdentityKey

            let newVerificationState: VerificationState
            switch recipientVerificationState {
            case .verified:
                newVerificationState = .implicit(isAcknowledged: false)
            case .noLongerVerified, .implicit:
                newVerificationState = .verified
            }

            deps.identityManager.saveIdentityKey(identityKey, for: recipientAci, tx: tx)
            _ = deps.identityManager.setVerificationState(
                newVerificationState,
                of: identityKey.publicKey.keyBytes,
                for: SignalServiceAddress(recipientAci),
                isUserInitiatedChange: true,
                tx: tx,
            )
        }

        dismiss(animated: true)
    }

    private func shareFingerprint(from fromView: UIView) {
        let compareActivity = CompareSafetyNumbersActivity(delegate: self)

        let shareFormat = NSLocalizedString(
            "SAFETY_NUMBER_SHARE_FORMAT",
            comment: "Snippet to share {{safety number}} with a friend. sent e.g. via SMS",
        )
        let shareString = String(format: shareFormat, fingerprint.displayableText)

        let activityController = UIActivityViewController(
            activityItems: [shareString],
            applicationActivities: [compareActivity],
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
            .init(rawValue: iCloudActivityType), // This isn't being excluded. RADAR https://openradar.appspot.com/27493621
        ]

        present(activityController, animated: true)
    }

    fileprivate func didTapToScan() {
        let viewController = FingerprintScanViewController(
            recipientAci: recipientAci,
            recipientIdentity: recipientIdentity,
            fingerprint: self.fingerprint,
        )
        navigationController?.pushViewController(viewController, animated: true)
    }

    fileprivate func didTapKeyTransparencyButton(state: KeyTransparencyView.State) {
        owsPrecondition(keyTransparencyState.isEnabled)

        switch state {
        case .unableToVerify:
            present(KeyTransparencyNotAvailableHeroSheet(), animated: true)
        case .readyToVerify:
            guard
                let deps,
                let checkParams = keyTransparencyState.checkParams
            else { return }

            keyTransparencyView.state = .verifying
            Task { @MainActor [weak self] in
                do {
                    try await deps.keyTransparencyManager.performCheck(params: checkParams)
                    self?.keyTransparencyView.state = .verifiedSuccess
                } catch {
                    self?.keyTransparencyView.state = .verifiedFailure
                }
            }
        case .verifying:
            break
        case .verifiedSuccess:
            present(KeyTransparencySuccessHeroSheet(), animated: true)
        case .verifiedFailure:
            present(KeyTransparencyFailureHeroSheet(theirName: fingerprint.theirName), animated: true)
        }
    }
}

// MARK: -

extension FingerprintViewController: CompareSafetyNumbersActivityDelegate {

    func compareSafetyNumbersActivitySucceeded(activity: CompareSafetyNumbersActivity) {
        FingerprintScanViewController.showVerificationSucceeded(
            from: self,
            identityKey: fingerprint.theirAciIdentityKey,
            recipientAci: recipientAci,
            contactName: fingerprint.theirName,
            tag: "[\(type(of: self))]",
        )
    }

    func compareSafetyNumbersActivity(_ activity: CompareSafetyNumbersActivity, failedWithError error: CompareSafetyNumberError) {
        FingerprintScanViewController.showVerificationFailed(
            from: self,
            isUserError: error == .userError,
            localizedErrorDescription: error.localizedError,
            tag: "[\(type(of: self))]",
        )
    }
}

// MARK: -

private final class KeyTransparencyNotAvailableHeroSheet: HeroSheetViewController {
    init() {
        super.init(
            hero: .image(UIImage(named: "info")!, tintColor: .Signal.label),
            title: OWSLocalizedString(
                "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_NOT_AVAILABLE_SHEET_TITLE",
                comment: "Title for a sheet explaining that encryption auto-verification is not available.",
            ),
            body: OWSLocalizedString(
                "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_NOT_AVAILABLE_SHEET_BODY",
                comment: "Body for a sheet explaining that encryption auto-verification is not available.",
            ),
            primaryButton: .dismissing(title: CommonStrings.okButton),
        )
    }
}

// MARK: -

private final class KeyTransparencySuccessHeroSheet: HeroSheetViewController {
    init() {
        super.init(
            hero: .image(UIImage(named: "check-circle")!, tintColor: .Signal.label),
            title: OWSLocalizedString(
                "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_SUCCESS_SHEET_TITLE",
                comment: "Title for a sheet explaining that encryption auto-verification succeeded.",
            ),
            body: OWSLocalizedString(
                "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_SUCCESS_SHEET_BODY",
                comment: "Body for a sheet explaining that encryption auto-verification succeeded.",
            ),
            primaryButton: .dismissing(title: CommonStrings.okButton),
        )
    }
}

// MARK: -

private final class KeyTransparencyFailureHeroSheet: HeroSheetViewController {
    init(theirName: String) {
        super.init(
            hero: .image(UIImage(named: "check-circle")!, tintColor: .Signal.label),
            title: OWSLocalizedString(
                "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_FAILURE_SHEET_TITLE",
                comment: "Title for a sheet explaining that encryption auto-verification did not succeed.",
            ),
            body: String(
                format: OWSLocalizedString(
                    "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_FAILURE_SHEET_BODY_FORMAT",
                    comment: "Body for a sheet explaining that encryption auto-verification did not succeed. Embeds {{ 1: the contact's name }}.",
                ),
                theirName,
            ),
            primaryButton: .dismissing(title: CommonStrings.okButton),
        )
    }
}

// MARK: -

private final class KeyTransparencyFirstTimeEducationHeroSheet: HeroSheetViewController {
    init(onContinue: @MainActor @escaping () -> Void) {
        super.init(
            hero: .image(UIImage(named: "safety-number-verification")!),
            title: OWSLocalizedString(
                "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_EDUCATION_SHEET_TITLE",
                comment: "Title for a sheet introducing Key Transparency.",
            ),
            body: OWSLocalizedString(
                "SAFETY_NUMBERS_AUTOMATIC_VERIFICATION_EDUCATION_SHEET_BODY",
                comment: "Body for a sheet introducing Key Transparency.",
            ),
            primaryButton: HeroSheetViewController.Button(
                title: CommonStrings.continueButton,
                action: { sheet in
                    sheet.dismiss(animated: true) {
                        onContinue()
                    }
                },
            ),
        )
    }
}

// MARK: -

#if DEBUG

private extension IdentityKey {
    static func forPreview() -> IdentityKey {
        let randomBytes = Randomness.generateRandomBytes(32)
        return IdentityKey(publicKey: try! PublicKey(keyData: randomBytes))
    }
}

private final class FingerprintPreviewViewController: UINavigationController {
    init(
        theirVerificationState: VerificationState = .verified,
        keyTransparencyIsEnabled: Bool = true,
        keyTransparencyViewInitialState: FingerprintViewController.KeyTransparencyView.State = .readyToVerify,
    ) {
        let recipientAci = Aci.randomForTesting()
        let recipientIdentityKey = IdentityKey.forPreview()

        let fingerprintViewController = FingerprintViewController(
            recipientAci: recipientAci,
            recipientIdentity: OWSRecipientIdentity(
                uniqueId: UUID().uuidString,
                identityKey: recipientIdentityKey.publicKey.keyBytes,
                isFirstKnownKey: true,
                createdAt: Date().addingTimeInterval(-.week),
                verificationState: .default,
            ),
            recipientVerificationState: theirVerificationState,
            fingerprint: OWSFingerprint(
                myAci: .randomForTesting(),
                theirAci: recipientAci,
                myAciIdentityKey: .forPreview(),
                theirAciIdentityKey: recipientIdentityKey,
                theirName: "Boba Fett",
            ),
            keyTransparencyState: FingerprintViewController.KeyTransparencyState(
                isEnabled: keyTransparencyIsEnabled,
                checkParams: nil,
                viewInitialState: keyTransparencyViewInitialState,
            ),
            deps: nil,
        )

        super.init(rootViewController: fingerprintViewController)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("") }
}

@available(iOS 17, *)
#Preview("Not Verified") {
    FingerprintPreviewViewController(theirVerificationState: .noLongerVerified)
}

@available(iOS 17, *)
#Preview("Verified") {
    FingerprintPreviewViewController(theirVerificationState: .verified)
}

@available(iOS 17, *)
#Preview("KT Unavailable") {
    FingerprintPreviewViewController(keyTransparencyViewInitialState: .unableToVerify)
}

@available(iOS 17, *)
#Preview("KT Running") {
    FingerprintPreviewViewController(keyTransparencyViewInitialState: .verifying)
}

@available(iOS 17, *)
#Preview("KT Success") {
    FingerprintPreviewViewController(keyTransparencyViewInitialState: .verifiedSuccess)
}

@available(iOS 17, *)
#Preview("KT Failure") {
    FingerprintPreviewViewController(keyTransparencyViewInitialState: .verifiedFailure)
}

@available(iOS 17, *)
#Preview("KT Disabled") {
    FingerprintPreviewViewController(keyTransparencyIsEnabled: false)
}

#endif
