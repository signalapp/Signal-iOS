//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

import Lottie
import PureLayout
import SafariServices
import SignalMessaging
import SignalServiceKit
import UIKit

public class FingerprintViewController: OWSViewController, OWSNavigationChildController {

    public class func present(
        from viewController: UIViewController,
        address theirAddress: SignalServiceAddress
    ) {
        owsAssertBeta(theirAddress.isValid)

        let identityManager = DependenciesBridge.shared.identityManager
        guard let theirRecipientIdentity = databaseStorage.read(block: { tx in
            identityManager.recipientIdentity(for: theirAddress, tx: tx.asV2Read)
        }) else {
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString(
                    "CANT_VERIFY_IDENTITY_ALERT_TITLE",
                    comment: "Title for alert explaining that a user cannot be verified."
                ),
                message: OWSLocalizedString(
                    "CANT_VERIFY_IDENTITY_ALERT_MESSAGE",
                    comment: "Message for alert explaining that a user cannot be verified."
                )
            )
            return
        }

        guard let fingerprintResult = databaseStorage.read(block: { tx in
            return OWSFingerprintBuilder(
                contactsManager: contactsManager,
                identityManager: identityManager,
                tsAccountManager: DependenciesBridge.shared.tsAccountManager
            ).fingerprints(
                theirAddress: theirAddress,
                theirRecipientIdentity: theirRecipientIdentity,
                tx: tx
            )
        }) else {
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
            fingerprints: fingerprintResult.fingerprints,
            initialDisplayIndex: fingerprintResult.initialDisplayIndex,
            recipientAddress: theirAddress,
            recipientIdentity: theirRecipientIdentity
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

    private let recipientAddress: SignalServiceAddress
    private let recipientIdentity: OWSRecipientIdentity
    private let contactName: String
    private let identityKey: Data
    private let fingerprints: [OWSFingerprint]
    private var selectedIndex: Int

    public init(
        fingerprints: [OWSFingerprint],
        initialDisplayIndex: Int,
        recipientAddress: SignalServiceAddress,
        recipientIdentity: OWSRecipientIdentity
    ) {
        self.recipientAddress = recipientAddress
        self.contactName = SSKEnvironment.shared.contactsManagerRef.displayName(for: recipientAddress)
        // By capturing the identity key when we enter these views, we prevent the edge case
        // where the user verifies a key that we learned about while this view was open.
        self.recipientIdentity = recipientIdentity
        self.identityKey = recipientIdentity.identityKey
        self.fingerprints = fingerprints
        self.selectedIndex = initialDisplayIndex

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

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // TODO: This doesn't seem to work, maybe because the views haven't been sized yet. When we build with Xcode 15, we can use `viewIsAppearing()`.
        if #available(iOS 17, *) { owsFailDebug("Canary to fix this when we're building with Xcode 15!") }
        fingerprintCarouselPageControl.currentPage = selectedIndex
        scrollToSelectedIndex(animated: false)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !DependenciesBridge.shared.db.read(block: self.hasShownTransitionSheet) {
            // Its fine to not re-read the value in the write tx; stakes are low.
            DependenciesBridge.shared.db.write(block: self.showTransitionSheet)
        }
    }

    public override func themeDidChange() {
        super.themeDidChange()
        view.backgroundColor = Self.backgroundColor

        updateVerificationStateLabel()
        setSafetyNumbersUpdateTextViewText()
        setCarouselPageControlColors()
        setInstructionsText()
        setVerifyUnverifyButtonColors()
    }

    // MARK: UI

    private lazy var safetyNumbersUpdateTextView: LinkingTextView = {
        let textView = LinkingTextView()
        textView.delegate = self
        return textView
    }()

    private func setSafetyNumbersUpdateTextViewText() {
        // Link doesn't matter, we will override tap behavior.
        let learnMoreString = CommonStrings.learnMore.styled(with: .link(URL(string: Constants.transitionLearnMoreUrl)!))
        safetyNumbersUpdateTextView.attributedText = NSAttributedString.composed(of: [
            OWSLocalizedString(
                "SAFETY_NUMBER_TRANSITION_HEADER_ALERT",
                comment: "Header informing the user about the transition from phone number to user identifier based."
            ),
            "\n",
            learnMoreString
        ]).styled(
            with: .font(.dynamicTypeFootnote),
            .color(Theme.secondaryTextAndIconColor)
        )
        safetyNumbersUpdateTextView.linkTextAttributes = [
            .foregroundColor: Theme.primaryTextColor,
            .underlineColor: UIColor.clear,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private lazy var safetyNumbersUpdateView: UIView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fill
        stackView.alignment = .center
        stackView.spacing = 16

        let imageView = UIImageView(image: UIImage(named: "safety_number_transition"))
        imageView.autoSetDimensions(to: .square(48))
        stackView.addArrangedSubview(imageView)

        stackView.addArrangedSubview(safetyNumbersUpdateTextView)

        return stackView
    }()

    private lazy var fingerprintCards: [FingerprintCard] = {
        return fingerprints.map { fingerprint in
            return FingerprintCard(fingerprint: fingerprint, controller: self)
        }
    }()

    private lazy var fingerprintCarousel: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isPagingEnabled = true
        scrollView.isDirectionalLockEnabled = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false

        var xOffset: CGFloat = Constants.cardHInset
        var previousView: UIView = scrollView
        var nextEdge: ALEdge = .leading
        for fingerprintCard in fingerprintCards {
            scrollView.addSubview(fingerprintCard)
            fingerprintCard.autoPinVerticalEdges(toEdgesOf: scrollView)
            scrollView.autoPinHeight(toHeightOf: fingerprintCard, relation: .greaterThanOrEqual)
            fingerprintCard.autoPinEdge(.leading, to: nextEdge, of: previousView, withOffset: xOffset)
            previousView = fingerprintCard
            xOffset = Constants.interCardSpacing
            nextEdge = .trailing
        }
        previousView.autoPinEdge(.trailing, to: .trailing, of: scrollView, withOffset: -Constants.cardHInset)

        scrollView.delegate = self

        return scrollView
    }()

    private lazy var fingerprintCarouselPageControl: UIPageControl = {
        let control = UIPageControl()
        control.numberOfPages = fingerprints.count
        control.addTarget(self, action: #selector(didUpdatePageControl), for: .valueChanged)
        return control
    }()

    private func setCarouselPageControlColors() {
        fingerprintCarouselPageControl.pageIndicatorTintColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray25
        fingerprintCarouselPageControl.currentPageIndicatorTintColor = Theme.primaryTextColor
    }

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
            String(format: instructionsFormat, contactName),
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
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        let containerView = UIView()
        view.addSubview(scrollView)
        scrollView.addSubview(containerView)

        scrollView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        containerView.autoPinEdges(toEdgesOf: scrollView)
        containerView.autoPinWidth(toWidthOf: view)

        containerView.addSubview(safetyNumbersUpdateView)
        containerView.addSubview(fingerprintCarousel)
        containerView.addSubview(fingerprintCarouselPageControl)
        containerView.addSubview(instructionsTextView)
        view.addSubview(verifyUnverifyButton)

        safetyNumbersUpdateView.autoPinEdge(.leading, to: .leading, of: containerView, withOffset: .scaleFromIPhone5To7Plus(18, 24))
        safetyNumbersUpdateView.autoPinEdge(.trailing, to: .trailing, of: containerView, withOffset: -.scaleFromIPhone5To7Plus(18, 24))
        safetyNumbersUpdateView.autoPinEdge(toSuperviewSafeArea: .top, withInset: 12)

        fingerprintCarousel.autoPinHorizontalEdges(toEdgesOf: containerView)

        fingerprintCards.forEach {
            $0.autoPinWidth(toWidthOf: containerView, offset: -.scaleFromIPhone5To7Plus(60, 105))
        }

        fingerprintCarouselPageControl.autoHCenterInSuperview()
        fingerprintCarouselPageControl.autoPinEdge(.top, to: .bottom, of: fingerprintCarousel, withOffset: 8)

        instructionsTextView.autoPinEdge(.leading, to: .leading, of: containerView, withOffset: .scaleFromIPhone5To7Plus(18, 28))
        instructionsTextView.autoPinEdge(.trailing, to: .trailing, of: containerView, withOffset: -.scaleFromIPhone5To7Plus(18, 28))
        instructionsTextView.autoPinEdge(.bottom, to: .bottom, of: scrollView)

        verifyUnverifyButton.autoHCenterInSuperview()
        verifyUnverifyButton.autoPinEdge(.top, to: .bottom, of: scrollView, withOffset: .scaleFromIPhone5To7Plus(12, 24))
        verifyUnverifyButton.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: .scaleFromIPhone5To7Plus(16, 40))

        if fingerprints.count <= 1 {
            safetyNumbersUpdateView.isHidden = true
            fingerprintCarouselPageControl.isHidden = true
            scrollView.isScrollEnabled = false

            fingerprintCarousel.autoPinEdge(toSuperviewSafeArea: .top, withInset: 56)
            instructionsTextView.autoPinEdge(.top, to: .bottom, of: fingerprintCarousel, withOffset: 24)
        } else {
            fingerprintCarousel.autoPinEdge(.top, to: .bottom, of: safetyNumbersUpdateView, withOffset: 24)
            instructionsTextView.autoPinEdge(.top, to: .bottom, of: fingerprintCarouselPageControl, withOffset: 16)
        }

        updateVerificationStateLabel()
        setSafetyNumbersUpdateTextViewText()
        setCarouselPageControlColors()
        setInstructionsText()
        setVerifyUnverifyButtonColors()
    }

    private func updateVerificationStateLabel() {
        owsAssertBeta(recipientAddress.isValid)

        let identityManager = DependenciesBridge.shared.identityManager
        let isVerified = databaseStorage.read { tx in
            return identityManager.verificationState(for: recipientAddress, tx: tx.asV2Read) == .verified
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

            self.backgroundColor = {
                switch fingerprint.source {
                case .aci: return UIColor(rgbHex: 0x506ecd)
                case .e164: return UIColor(rgbHex: 0xdeddda)
                }
            }()

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
            let tintColor: UIColor
            switch fingerprint.source {
            case .aci:
                tintColor = .white
            case .e164:
                tintColor = .black
            }
            button.setTemplateImage(
                Theme.iconImage(.buttonShare).withRenderingMode(.alwaysTemplate),
                tintColor: tintColor
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
            switch fingerprint.source {
            case .aci:
                label.textColor = .white
            case .e164:
                label.textColor = Theme.lightThemeSecondaryTextAndIconColor
            }
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

    // MARK: - Transition Sheet

    private lazy var kvStore: KeyValueStore = {
        return DependenciesBridge.shared.keyValueStoreFactory.keyValueStore(collection: "MultiFingerprintVC")
    }()

    private static let hasShownTransitionSheetKey = "hasShownTransitionSheetKey"

    private func hasShownTransitionSheet(_ tx: DBReadTransaction) -> Bool {
        return self.kvStore.getBool(Self.hasShownTransitionSheetKey, defaultValue: false, transaction: tx)
    }

    private func setHasShownTransitionSheet(_ tx: DBWriteTransaction) {
        self.kvStore.setBool(true, key: Self.hasShownTransitionSheetKey, transaction: tx)
    }

    private func showTransitionSheet(_ tx: DBWriteTransaction) {
        self.setHasShownTransitionSheet(tx)
        tx.addAsyncCompletion(on: DispatchQueue.main) {
            let sheet = TransitionSheetViewController(parent: self)
            self.present(sheet, animated: true)
        }
    }

    class TransitionSheetViewController: InteractiveSheetViewController {
        let contentScrollView = UIScrollView()
        let stackView = UIStackView()
        public override var interactiveScrollViews: [UIScrollView] { [contentScrollView] }
        public override var sheetBackgroundColor: UIColor { Theme.tableView2PresentedBackgroundColor }

        override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            return .portrait
        }

        private weak var parentVc: FingerprintViewController?

        init(parent: FingerprintViewController) {
            self.parentVc = parent
            super.init()
        }

        override public func viewDidLoad() {
            super.viewDidLoad()

            minimizedHeight = 600
            super.allowsExpansion = true

            contentView.addSubview(contentScrollView)

            stackView.axis = .vertical
            stackView.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 24)
            stackView.spacing = 16
            stackView.isLayoutMarginsRelativeArrangement = true
            contentScrollView.addSubview(stackView)
            stackView.autoPinHeightToSuperview()
            // Pin to the scroll view's viewport, not to its scrollable area
            stackView.autoPinWidth(toWidthOf: contentScrollView)

            contentScrollView.autoPinEdgesToSuperviewEdges()
            contentScrollView.alwaysBounceVertical = true

            buildContents()
        }

        override public func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)

            if !animationView.isAnimationQueued && !animationView.isAnimationPlaying {
                animationView.play { [weak self] success in
                    guard success else { return }
                    self?.loopAnimation()
                }
            }
        }

        override public func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)

            if animationView.isAnimationQueued || animationView.isAnimationPlaying {
                animationView.stop()
            }
        }

        private func loopAnimation() {
            animationView.play(fromFrame: 60, toFrame: 360, completion: { [weak self] success in
                guard success else { return }
                self?.loopAnimation()
            })
        }

        private lazy var animationView: AnimationView = {
            let animationView = AnimationView(name: "safety-numbers")
            animationView.contentMode = .scaleAspectFit
            animationView.isUserInteractionEnabled = false
            animationView.backgroundColor = .white
            animationView.layer.cornerRadius = 12
            animationView.layer.masksToBounds = true
            return animationView
        }()

        private func buildContents() {
            let titleLabel = UILabel()
            titleLabel.textAlignment = .center
            titleLabel.font = UIFont.dynamicTypeTitle2.semibold()
            titleLabel.text = OWSLocalizedString(
                "SAFETY_NUMBER_TRANSITION_SHEET_TITLE",
                comment: "Title for a sheet informing the user about the transition from phone number to user identifier based."
            )
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            stackView.addArrangedSubview(titleLabel)

            let paragraphs: [String] = [
                OWSLocalizedString(
                    "SAFETY_NUMBER_TRANSITION_SHEET_PARAGRAPH_1",
                    comment: "Informs the user about the transition from phone number to user identifier based."
                ),
                OWSLocalizedString(
                    "SAFETY_NUMBER_TRANSITION_SHEET_PARAGRAPH_2",
                    comment: "Informs the user about the transition from phone number to user identifier based."
                )
            ]
            var lastParagraphLabel: UILabel!
            for paragraph in paragraphs {
                let paragraphLabel = UILabel()
                paragraphLabel.text = paragraph
                paragraphLabel.textAlignment = .natural
                paragraphLabel.font = .dynamicTypeSubheadlineClamped
                paragraphLabel.numberOfLines = 0
                paragraphLabel.lineBreakMode = .byWordWrapping
                paragraphLabel.textColor = Theme.secondaryTextAndIconColor
                stackView.addArrangedSubview(paragraphLabel)
                lastParagraphLabel = paragraphLabel
            }
            stackView.setCustomSpacing(20, after: lastParagraphLabel)

            stackView.addArrangedSubview(animationView)
            stackView.setCustomSpacing(18, after: animationView)
            animationView.autoMatch(.height, to: .width, of: animationView, withMultiplier: 172/346)

            let learnMoreTitle = OWSLocalizedString(
                "SAFETY_NUMBER_TRANSITION_SHEET_HELP_TEXT",
                comment: "Button text for a sheet informing the user about the transition from phone number to user identifier based."
            )
            let learnMoreButton = UIButton(type: .system)
            learnMoreButton.setTitle(learnMoreTitle, for: .normal)
            learnMoreButton.titleLabel?.font = .dynamicTypeBody
            learnMoreButton.setTitleColor(Theme.isDarkThemeEnabled ? .ows_accentBlueDark : .link, for: .normal)
            learnMoreButton.addTarget(self, action: #selector(didTapLearnMore), for: .touchUpInside)
            stackView.addArrangedSubview(learnMoreButton)
            stackView.setCustomSpacing(24, after: learnMoreButton)

            let continueButton = OWSButton(
                title: OWSLocalizedString(
                    "ALERT_ACTION_ACKNOWLEDGE",
                    comment: "generic button text to acknowledge that the corresponding text was read."
                )
            ) { [weak self] in
                self?.dismiss(animated: true)
            }
            continueButton.layer.cornerRadius = 16
            continueButton.backgroundColor = .ows_accentBlue
            continueButton.dimsWhenHighlighted = true
            continueButton.titleLabel?.font = UIFont.dynamicTypeBody.semibold()
            continueButton.autoSetDimension(.height, toSize: 50, relation: .greaterThanOrEqual)
            stackView.addArrangedSubview(continueButton)
        }

        @objc
        func didTapLearnMore() {
            FingerprintViewController.showLearnMoreUrl(from: self)
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
    private func didUpdatePageControl() {
        self.selectedIndex = fingerprintCarouselPageControl.currentPage
        scrollToSelectedIndex()
    }

    @objc
    private func didTapVerifyUnverify(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .recognized else { return }

        databaseStorage.write { tx in
            let identityManager = DependenciesBridge.shared.identityManager
            let isVerified = identityManager.verificationState(for: recipientAddress, tx: tx.asV2Read) == .verified
            let newVerificationState: OWSVerificationState = isVerified ? .default : .verified
            identityManager.setVerificationState(
                newVerificationState,
                identityKey: identityKey,
                address: recipientAddress,
                isUserInitiatedChange: true,
                tx: tx.asV2Write
            )
        }

        dismiss(animated: true)
    }

    private func shareFingerprint(from fromView: UIView) {
        let fingerprint = fingerprints[selectedIndex]

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
            recipientAddress: recipientAddress,
            recipientIdentity: recipientIdentity,
            fingerprints: self.fingerprints
        )
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func scrollToSelectedIndex(animated: Bool = true) {
        let xOffset: CGFloat
        if selectedIndex == 0 {
            xOffset = 0
        } else {
            xOffset = (CGFloat(selectedIndex) * UIScreen.main.bounds.width) - (Constants.interCardSpacing + Constants.cardHInset)
        }
        fingerprintCarousel.setContentOffset(.init(x: xOffset, y: 0), animated: animated)
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
        static var interCardSpacing: CGFloat = cardHInset / 2

        // Link doesn't matter, we will override tap behavior.
        static let transitionLearnMoreUrl = "https://support.signal.org/"
        static let learnMoreUrl = "https://support.signal.org/learnMore"
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

extension FingerprintViewController: UITextViewDelegate {

    public func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if URL.absoluteString == Constants.transitionLearnMoreUrl {
            DependenciesBridge.shared.db.write {
                self.showTransitionSheet($0)
            }
        } else if URL.absoluteString == Constants.learnMoreUrl {
            self.didTapLearnMore()
        }
        return false
    }
}

extension FingerprintViewController: UIScrollViewDelegate {

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let selectedIndex = Int(scrollView.contentOffset.x / (scrollView.frame.width - (Constants.cardHInset * 2)))
        self.selectedIndex = selectedIndex
        self.fingerprintCarouselPageControl.currentPage = selectedIndex
    }
}
