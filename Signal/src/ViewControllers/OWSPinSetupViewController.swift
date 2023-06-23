//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalCoreKit
import SignalMessaging
import SignalServiceKit
import SignalUI

public class PinSetupViewController: OWSViewController, OWSNavigationChildController {

    lazy private var titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.primaryTextColor
        label.font = UIFont.dynamicTypeTitle1Clamped.semibold()
        label.textAlignment = .center
        label.text = titleText
        return label
    }()

    lazy private var explanationLabel: LinkingTextView = {
        let explanationLabel = LinkingTextView()
        let explanationText: String
        let addLearnMoreLink: Bool
        switch mode {
        case .deprecated_onboardingCreating, .creating:
            explanationText = OWSLocalizedString(
                "PIN_CREATION_EXPLANATION",
                comment: "The explanation in the 'pin creation' view."
            )
            addLearnMoreLink = true
        case .changing:
            explanationText = OWSLocalizedString(
                "PIN_CREATION_RECREATION_EXPLANATION",
                comment: "The re-creation explanation in the 'pin creation' view."
            )
            addLearnMoreLink = true
        case .confirming:
            explanationText = OWSLocalizedString(
                "PIN_CREATION_CONFIRMATION_EXPLANATION",
                comment: "The explanation of confirmation in the 'pin creation' view."
            )
            addLearnMoreLink = false
        }

        // The font is too long to fit with dynamic type. Design is looking into
        // how to design this page to fit dynamic type. In the meantime, we have
        // to pin the font size.
        let explanationLabelFont = UIFont.systemFont(ofSize: 15)

        let attributedString = NSMutableAttributedString(
            string: explanationText,
            attributes: [
                .font: explanationLabelFont,
                .foregroundColor: Theme.secondaryTextAndIconColor
            ]
        )

        if addLearnMoreLink {
            explanationLabel.isUserInteractionEnabled = true
            attributedString.append("  ")
            attributedString.append(
                CommonStrings.learnMore,
                attributes: [
                    .link: URL(string: "https://support.signal.org/hc/articles/360007059792")!,
                    .font: explanationLabelFont
                ]
            )
        }
        explanationLabel.attributedText = attributedString
        explanationLabel.textAlignment = .center
        explanationLabel.accessibilityIdentifier = "pinCreation.explanationLabel"
        return explanationLabel
    }()

    private let topSpacer = UIView.vStretchingSpacer()
    private var proportionalSpacerConstraint: NSLayoutConstraint?

    private let pinTextField: UITextField = {
        let pinTextField = UITextField()
        pinTextField.textAlignment = .center
        pinTextField.textColor = Theme.primaryTextColor

        let font = UIFont.systemFont(ofSize: 17)
        pinTextField.font = font
        pinTextField.autoSetDimension(.height, toSize: font.lineHeight + 2 * 8.0)

        pinTextField.textContentType = .password
        pinTextField.isSecureTextEntry = true
        pinTextField.defaultTextAttributes.updateValue(5, forKey: .kern)
        pinTextField.keyboardAppearance = Theme.keyboardAppearance
        pinTextField.accessibilityIdentifier = "pinCreation.pinTextField"
        return pinTextField
    }()

    private lazy var pinTypeToggle: OWSFlatButton = {
        let pinTypeToggle = OWSFlatButton()
        pinTypeToggle.setTitle(font: .dynamicTypeSubheadlineClamped, titleColor: Theme.accentBlueColor)
        pinTypeToggle.setBackgroundColors(upColor: .clear)

        pinTypeToggle.enableMultilineLabel()
        pinTypeToggle.button.clipsToBounds = true
        pinTypeToggle.button.layer.cornerRadius = 8
        pinTypeToggle.contentEdgeInsets = UIEdgeInsets(hMargin: 4, vMargin: 8)

        pinTypeToggle.addTarget(target: self, selector: #selector(togglePinType))
        pinTypeToggle.accessibilityIdentifier = "pinCreation.pinTypeToggle"
        return pinTypeToggle
    }()

    private lazy var nextButton: OWSFlatButton = {
        let nextButton = OWSFlatButton()
        nextButton.setTitle(
            title: CommonStrings.nextButton,
            font: UIFont.dynamicTypeBodyClamped.semibold(),
            titleColor: .white)
        nextButton.setBackgroundColors(upColor: .ows_accentBlue)

        nextButton.button.clipsToBounds = true
        nextButton.button.layer.cornerRadius = 14
        nextButton.contentEdgeInsets = UIEdgeInsets(hMargin: 4, vMargin: 14)

        nextButton.addTarget(target: self, selector: #selector(nextPressed))
        nextButton.accessibilityIdentifier = "pinCreation.nextButton"
        return nextButton
    }()

    private let validationWarningLabel: UILabel = {
        let validationWarningLabel = UILabel()
        validationWarningLabel.textColor = .ows_accentRed
        validationWarningLabel.textAlignment = .center
        validationWarningLabel.font = UIFont.dynamicTypeFootnoteClamped
        validationWarningLabel.numberOfLines = 0
        validationWarningLabel.accessibilityIdentifier = "pinCreation.validationWarningLabel"
        return validationWarningLabel
    }()

    private let recommendationLabel: UILabel = {
        let recommendationLabel = UILabel()
        recommendationLabel.textColor = Theme.secondaryTextAndIconColor
        recommendationLabel.textAlignment = .center
        recommendationLabel.font = UIFont.dynamicTypeFootnoteClamped
        recommendationLabel.numberOfLines = 0
        recommendationLabel.accessibilityIdentifier = "pinCreation.recommendationLabel"
        return recommendationLabel
    }()

    private lazy var backButton: UIButton = {
        let backButton = UIButton.withTemplateImage(
            UIImage(imageLiteralResourceName: "NavBarBack"),
            tintColor: Theme.secondaryTextAndIconColor
        )
        backButton.autoSetDimensions(to: CGSize(square: 40))
        backButton.addTarget(self, action: #selector(navigateBack), for: .touchUpInside)
        return backButton
    }()

    private lazy var moreButton: UIButton = {
        let moreButton = UIButton.withTemplateImage(Theme.iconImage(.buttonMore), tintColor: Theme.primaryIconColor)
        moreButton.autoSetDimensions(to: CGSize(square: 40))
        moreButton.addTarget(self, action: #selector(didTapMoreButton), for: .touchUpInside)
        return moreButton
    }()

    private lazy var pinStrokeNormal = pinTextField.addBottomStroke()
    private lazy var pinStrokeError = pinTextField.addBottomStroke(color: .ows_accentRed, strokeWidth: 2)

    enum Mode: Equatable {
        case deprecated_onboardingCreating
        case creating
        case changing
        case confirming(pinToMatch: String)

        var isConfirming: Bool {
            switch self {
            case .confirming:
                return true
            case .creating, .changing, .deprecated_onboardingCreating:
                return false
            }
        }
    }
    private let mode: Mode

    private let initialMode: Mode

    enum ValidationState {
        case valid
        case tooShort
        case mismatch
        case weak

        var isInvalid: Bool {
            return self != .valid
        }
    }
    private var validationState: ValidationState = .valid {
        didSet {
            updateValidationWarnings()
        }
    }

    private var pinType: SVR.PinType {
        didSet {
            updatePinType()
        }
    }

    private let hideNavigationBar: Bool

    private let showCancelButton: Bool

    private let showDisablePinButton: Bool

    // Called once pin setup has finished. Error will be nil upon success
    private let completionHandler: (PinSetupViewController, Error?) -> Void

    private let enableRegistrationLock: Bool

    private let context: ViewControllerContext

    convenience init(
        mode: Mode,
        hideNavigationBar: Bool,
        showCancelButton: Bool = false,
        showDisablePinButton: Bool = false,
        enableRegistrationLock: Bool = OWS2FAManager.shared.isRegistrationLockEnabled,
        completionHandler: @escaping (PinSetupViewController, Error?) -> Void
    ) {
        self.init(
            mode: mode,
            initialMode: mode,
            pinType: .numeric,
            hideNavigationBar: hideNavigationBar,
            showCancelButton: showCancelButton,
            showDisablePinButton: showDisablePinButton,
            enableRegistrationLock: enableRegistrationLock,
            completionHandler: completionHandler
        )
    }

    private init(
        mode: Mode,
        initialMode: Mode,
        pinType: SVR.PinType,
        hideNavigationBar: Bool,
        showCancelButton: Bool,
        showDisablePinButton: Bool,
        enableRegistrationLock: Bool,
        completionHandler: @escaping (PinSetupViewController, Error?) -> Void
    ) {
        assert(TSAccountManager.shared.isRegisteredPrimaryDevice)
        self.mode = mode
        self.initialMode = initialMode
        self.pinType = pinType
        self.hideNavigationBar = hideNavigationBar
        self.showCancelButton = showCancelButton
        self.showDisablePinButton = showDisablePinButton
        self.enableRegistrationLock = enableRegistrationLock
        self.completionHandler = completionHandler
        // TODO[ViewContextPiping]
        self.context = ViewControllerContext.shared
        super.init()

        if case .confirming = self.initialMode {
            owsFailDebug("pin setup flow should never start in the confirming state")
        }

        super.keyboardObservationBehavior = .whileLifecycleVisible
    }

    class func onboardingCreating(completionHandler: @escaping (PinSetupViewController, Error?) -> Void) -> PinSetupViewController {
        return .init(
            mode: .deprecated_onboardingCreating,
            hideNavigationBar: true,
            showDisablePinButton: true,
            completionHandler: completionHandler
        )
    }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .solid
    }

    public var navbarBackgroundColorOverride: UIColor? {
        return backgroundColor
    }

    public var prefersNavigationBarHidden: Bool { hideNavigationBar }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let topMargin: CGFloat = self.prefersNavigationBarHidden ? 32 : 0
        let hMargin: CGFloat = UIDevice.current.isIPhone5OrShorter ? 13 : 26
        view.layoutMargins = UIEdgeInsets(top: topMargin, leading: hMargin, bottom: 0, trailing: hMargin)
        view.layoutIfNeeded()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // TODO: Maybe do this in will appear, to avoid the keyboard sliding in when the view is pushed?
        pinTextField.becomeFirstResponder()
    }

    private var backgroundColor: UIColor {
        presentingViewController == nil ? Theme.backgroundColor : Theme.tableView2PresentedBackgroundColor
    }

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
    }

    override public func loadView() {
        owsAssertDebug(navigationController != nil, "This view should always be presented in a nav controller")
        view = UIView()
        view.backgroundColor = backgroundColor

        view.addSubview(backButton)
        backButton.autoPinEdge(toSuperviewSafeArea: .top)
        backButton.autoPinEdge(toSuperviewSafeArea: .leading)

        view.addSubview(moreButton)
        moreButton.autoPinEdge(toSuperviewSafeArea: .top)
        moreButton.autoPinEdge(toSuperviewSafeArea: .trailing)

        let titleSpacer = SpacerView(preferredHeight: 12)
        let pinFieldSpacer = SpacerView(preferredHeight: 11)
        let bottomSpacer = SpacerView(preferredHeight: 10)
        let pinToggleSpacer = SpacerView(preferredHeight: 24)
        let buttonSpacer = SpacerView(preferredHeight: 32)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            titleSpacer,
            explanationLabel,
            topSpacer,
            pinTextField,
            pinFieldSpacer,
            validationWarningLabel,
            recommendationLabel,
            bottomSpacer,
            pinTypeToggle,
            pinToggleSpacer,
            Deprecated_OnboardingBaseViewController.horizontallyWrap(primaryButton: nextButton),
            buttonSpacer
        ])
        stackView.axis = .vertical
        stackView.alignment = .center
        view.addSubview(stackView)

        stackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)
        stackView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        [pinTextField, validationWarningLabel, recommendationLabel].forEach {
            $0.autoSetDimension(.width, toSize: 227)
        }

        [titleLabel, explanationLabel, pinTextField, validationWarningLabel, recommendationLabel, pinTypeToggle, nextButton]
            .forEach { $0.setCompressionResistanceVerticalHigh() }

        // Reduce priority of compression resistance for the spacer views
        // The array index serves as an ambiguous layout tiebreaker
        [titleSpacer, pinFieldSpacer, bottomSpacer, pinToggleSpacer, buttonSpacer].enumerated().forEach {
            $0.element.setContentCompressionResistancePriority(.defaultHigh - .init($0.offset), for: .vertical)
        }

        // Bottom spacer is the stack view item that grows when there's extra space
        // Ensure whitespace is balanced, so inputs are vertically centered.
        bottomSpacer.setContentHuggingPriority(.init(100), for: .vertical)
        proportionalSpacerConstraint = topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
        updateValidationWarnings()
        updatePinType()

        // Pin text field
        pinTextField.delegate = self
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = titleText

        let isNavigationBarVisible = !self.prefersNavigationBarHidden
        titleLabel.isHidden = isNavigationBarVisible
        backButton.isHidden = isNavigationBarVisible || mode == .deprecated_onboardingCreating
        moreButton.isHidden = isNavigationBarVisible || !showDisablePinButton

        if isNavigationBarVisible, showDisablePinButton {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: Theme.iconImage(.buttonMore),
                style: .plain,
                target: self,
                action: #selector(didTapMoreButton(_:))
            )
        }

        if showCancelButton {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(didTapCancel)
            )
        }

        OWSTableViewController2.removeBackButtonText(viewController: self)

        // Don't allow interactive dismissal.
        isModalInPresentation = true
    }

    var titleText: String {
        switch mode {
        case .confirming:
            return OWSLocalizedString("PIN_CREATION_CONFIRM_TITLE", comment: "Title of the 'pin creation' confirmation view.")
        case .changing:
            return OWSLocalizedString("PIN_CREATION_CHANGING_TITLE", comment: "Title of the 'pin creation' recreation view.")
        case .creating, .deprecated_onboardingCreating:
            return OWSLocalizedString("PIN_CREATION_TITLE", comment: "Title of the 'pin creation' view.")
        }
    }

    // MARK: - Events

    @objc
    private func navigateBack() {
        Logger.info("")

        navigationController?.popViewController(animated: true)
    }

    @objc
    private func didTapCancel() {
        dismiss(animated: true)
    }

    @objc
    private func didTapMoreButton(_ sender: UIButton) {
        let actionSheet = ActionSheetController()
        actionSheet.addAction(OWSActionSheets.cancelAction)

        proportionalSpacerConstraint?.isActive = false
        let pinnedHeightConstraint = topSpacer.autoSetDimension(.height, toSize: topSpacer.height)

        let learnMoreAction = ActionSheetAction(
            title: OWSLocalizedString(
                "PIN_CREATION_LEARN_MORE",
                comment: "Learn more action on the pin creation view"
            )
        ) { [weak self] _ in
            guard let self = self else { return }
            let vc = SFSafariViewController(url: URL(string: "https://support.signal.org/hc/articles/360007059792")!)
            self.present(vc, animated: true) {
                pinnedHeightConstraint.isActive = false
                self.proportionalSpacerConstraint?.isActive = true
            }
        }
        actionSheet.addAction(learnMoreAction)

        let skipAction = ActionSheetAction(
            title: OWSLocalizedString(
                "PIN_CREATION_SKIP",
                comment: "Skip action on the pin creation view"
            )
        ) { [weak self] _ in
            guard let self = self else { return }
            Self.disablePinWithConfirmation(fromViewController: self).done { [weak self] pinDisabled in
                guard pinDisabled, let self = self else { return }
                self.completionHandler(self, nil)
                pinnedHeightConstraint.isActive = false
                self.proportionalSpacerConstraint?.isActive = true
            }.catch { [weak self] error in
                guard let self = self else { return }
                OWSActionSheets.showActionSheet(
                    title: OWSLocalizedString("PIN_DISABLE_ERROR_TITLE",
                                             comment: "Error title indicating that the attempt to disable a PIN failed."),
                    message: OWSLocalizedString("PIN_DISABLE_ERROR_MESSAGE",
                                               comment: "Error body indicating that the attempt to disable a PIN failed.")
                ) { _ in
                    self.completionHandler(self, error)
                    pinnedHeightConstraint.isActive = false
                    self.proportionalSpacerConstraint?.isActive = true
                }
            }
        }
        actionSheet.addAction(skipAction)

        presentActionSheet(actionSheet)
    }

    @objc
    private func nextPressed() {
        Logger.info("")

        tryToContinue()
    }

    private func tryToContinue() {
        Logger.info("")

        guard let pin = pinTextField.text?.ows_stripped(), pin.count >= kMin2FAv2PinLength else {
            validationState = .tooShort
            return
        }

        if case .confirming(let pinToMatch) = mode, pinToMatch != pin {
            validationState = .mismatch
            return
        }

        if OWS2FAManager.isWeakPin(pin) {
            validationState = .weak
            return
        }

        switch mode {
        case .deprecated_onboardingCreating, .changing, .creating:
            let confirmingVC = PinSetupViewController(
                mode: .confirming(pinToMatch: pin),
                initialMode: initialMode,
                pinType: pinType,
                hideNavigationBar: hideNavigationBar,
                showCancelButton: false, // we're pushing, so we never need a cancel button
                showDisablePinButton: false, // we never show this button on the second screen
                enableRegistrationLock: enableRegistrationLock,
                completionHandler: completionHandler
            )
            navigationController?.pushViewController(confirmingVC, animated: true)
        case .confirming:
            enable2FAAndContinue(withPin: pin)
        }
    }

    private func updateValidationWarnings() {
        AssertIsOnMainThread()

        pinStrokeNormal.isHidden = validationState.isInvalid
        pinStrokeError.isHidden = !validationState.isInvalid
        validationWarningLabel.isHidden = !validationState.isInvalid
        recommendationLabel.isHidden = validationState.isInvalid

        switch validationState {
        case .tooShort:
            switch pinType {
            case .numeric:
                validationWarningLabel.text = OWSLocalizedString("PIN_CREATION_NUMERIC_HINT",
                                                                comment: "Label indicating the user must use at least 4 digits")
            case .alphanumeric:
                validationWarningLabel.text = OWSLocalizedString("PIN_CREATION_ALPHANUMERIC_HINT",
                                                                comment: "Label indicating the user must use at least 4 characters")
            }
        case .mismatch:
            validationWarningLabel.text = OWSLocalizedString("PIN_CREATION_MISMATCH_ERROR",
                                                            comment: "Label indicating that the attempted PIN does not match the first PIN")
        case .weak:
            validationWarningLabel.text = OWSLocalizedString("PIN_CREATION_WEAK_ERROR",
                                                            comment: "Label indicating that the attempted PIN is too weak")
        default:
            break
        }
    }

    private func updatePinType() {
        AssertIsOnMainThread()

        pinTextField.text = nil
        validationState = .valid

        let recommendationLabelText: String

        switch pinType {
        case .numeric:
            pinTypeToggle.setTitle(title: OWSLocalizedString("PIN_CREATION_CREATE_ALPHANUMERIC",
                                                            comment: "Button asking if the user would like to create an alphanumeric PIN"))
            pinTextField.keyboardType = .asciiCapableNumberPad
            recommendationLabelText = OWSLocalizedString("PIN_CREATION_NUMERIC_HINT",
                                                         comment: "Label indicating the user must use at least 4 digits")
        case .alphanumeric:
            pinTypeToggle.setTitle(title: OWSLocalizedString("PIN_CREATION_CREATE_NUMERIC",
                                                            comment: "Button asking if the user would like to create an numeric PIN"))
            pinTextField.keyboardType = .default
            recommendationLabelText = OWSLocalizedString("PIN_CREATION_ALPHANUMERIC_HINT",
                                                        comment: "Label indicating the user must use at least 4 characters")
        }

        pinTextField.reloadInputViews()

        if mode.isConfirming {
            pinTypeToggle.isHidden = true
            recommendationLabel.text = OWSLocalizedString("PIN_CREATION_PIN_CONFIRMATION_HINT",
                                                         comment: "Label indication the user must confirm their PIN.")
        } else {
            pinTypeToggle.isHidden = false
            recommendationLabel.text = recommendationLabelText
        }
    }

    @objc
    private func togglePinType() {
        switch pinType {
        case .numeric:
            pinType = .alphanumeric
        case .alphanumeric:
            pinType = .numeric
        }
    }

    private func enable2FAAndContinue(withPin pin: String) {
        Logger.debug("")

        pinTextField.resignFirstResponder()

        let progressView = AnimatedProgressView(
            loadingText: OWSLocalizedString("PIN_CREATION_PIN_PROGRESS",
                                           comment: "Indicates the work we are doing while creating the user's pin")
        )
        view.addSubview(progressView)
        progressView.autoPinWidthToSuperview()
        progressView.autoVCenterInSuperview()

        progressView.startAnimating {
            self.view.isUserInteractionEnabled = false
            self.nextButton.alpha = 0.5
            self.pinTextField.alpha = 0
            self.validationWarningLabel.alpha = 0
            self.recommendationLabel.alpha = 0
        }

        enum PinSetupError: Error {
            case networkFailure
            case enable2FA
            case enableRegistrationLock
        }

        firstly { () -> Promise<Void> in
            OWS2FAManager.shared.requestEnable2FA(withPin: pin, mode: .V2)
        }.recover { error in
            // If we have a network failure before even requesting to enable 2FA, we
            // can just ask the user to retry without altering any state. We can be
            // confident nothing has changed on the server.
            if case OWSHTTPError.networkFailure = error {
                // We only want to stop for network errors if we're past onboarding.
                // During onboarding, we want to let the user continue even when
                // a network issue is encountered during PIN creation.
                if self.initialMode != .deprecated_onboardingCreating {
                    throw PinSetupError.networkFailure
                }
            }

            owsFailDebug("Failed to enable 2FA with error: \(error)")

            // The client may have fallen out of sync with the service.
            // Try to get back to a known good state by disabling 2FA
            // whenever enabling it fails.
            OWS2FAManager.shared.disable2FA(success: nil, failure: nil)

            throw PinSetupError.enable2FA
        }.then { () -> Promise<Void> in
            if self.enableRegistrationLock {
                return OWS2FAManager.shared.enableRegistrationLockV2()
            } else {
                return Promise.value(())
            }
        }.recover { error -> Promise<Void> in
            if error is PinSetupError { throw error }

            owsFailDebug("Failed to enable registration lock with error: \(error)")

            // If the registration lock wasn't already enabled, we have to notify
            // the user of the failure and not attempt to enable it later. Otherwise,
            // they would be left thinking they have registration lock enabled when
            // they do not for some window of time.
            guard OWS2FAManager.shared.isRegistrationLockV2Enabled else {
                throw PinSetupError.enableRegistrationLock
            }
            return Promise.value(())
        }
        .done {
            // Always attempt to update our account attributes. This may fail,
            // but if it does it will flag our attributes as dirty so we upload them
            // ASAP (when we have the ability to talk to the service) and get the user
            // switched over to their new PIN for registration lock and the new
            // registration recovery password.
            // We might have already done this in the steps above, but re-upload to be sure.
            // Just kick it off, don't wait on the result.
            _ = TSAccountManager.shared.updateAccountAttributes().cauterize()
        }
        .done {
            AssertIsOnMainThread()

            // The completion handler always dismisses this view, so we don't want to animate anything.
            progressView.stopAnimatingImmediately()
            self.completionHandler(self, nil)

            // Clear the experience upgrade if it was pending.
            SDSDatabaseStorage.shared.asyncWrite { transaction in
                ExperienceUpgradeManager.clearExperienceUpgrade(.introducingPins, transaction: transaction.unwrapGrdbWrite)
            }
        }.catch { error in
            AssertIsOnMainThread()

            progressView.stopAnimating(success: false) {
                self.nextButton.alpha = 1
                self.pinTextField.alpha = 1
                self.validationWarningLabel.alpha = 1
                self.recommendationLabel.alpha = 1
            } completion: {
                self.view.isUserInteractionEnabled = true
                progressView.removeFromSuperview()

                guard let error = error as? PinSetupError else {
                    return owsFailDebug("Unexpected error during PIN setup \(error)")
                }

                // Show special reglock themed error message.
                switch error {
                case .enableRegistrationLock:
                    OWSActionSheets.showActionSheet(
                        title: OWSLocalizedString(
                            "PIN_CREATION_REGLOCK_ERROR_TITLE",
                            comment: "Error title indicating that the attempt to create a PIN succeeded but enabling reglock failed."),
                        message: OWSLocalizedString(
                            "PIN_CREATION_REGLOCK_ERROR_MESSAGE",
                            comment: "Error body indicating that the attempt to create a PIN succeeded but enabling reglock failed.")
                    ) { _ in
                        self.completionHandler(self, error)
                    }
                case .networkFailure:
                    OWSActionSheets.showActionSheet(
                        title: OWSLocalizedString(
                            "PIN_CREATION_NO_NETWORK_ERROR_TITLE",
                            comment: "Error title indicating that the attempt to create a PIN failed due to network issues."),
                        message: OWSLocalizedString(
                            "PIN_CREATION_NO_NETWORK_ERROR_MESSAGE",
                            comment: "Error body indicating that the attempt to create a PIN failed due to network issues.")
                    )
                case .enable2FA:
                    switch self.initialMode {
                    case .deprecated_onboardingCreating:
                        OWSActionSheets.showActionSheet(
                            title: OWSLocalizedString(
                                "PIN_CREATION_ERROR_TITLE",
                                comment: "Error title indicating that the attempt to create a PIN failed."),
                            message: OWSLocalizedString(
                                "PIN_CREATION_ERROR_MESSAGE",
                                comment: "Error body indicating that the attempt to create a PIN failed.")
                        ) { _ in
                            self.completionHandler(self, error)
                        }
                    case .changing:
                        OWSActionSheets.showActionSheet(
                            title: OWSLocalizedString(
                                "PIN_CHANGE_ERROR_TITLE",
                                comment: "Error title indicating that the attempt to change a PIN failed."),
                            message: OWSLocalizedString(
                                "PIN_CHANGE_ERROR_MESSAGE",
                                comment: "Error body indicating that the attempt to change a PIN failed.")
                        ) { _ in
                            self.completionHandler(self, error)
                        }
                    case .creating:
                        OWSActionSheets.showActionSheet(
                            title: OWSLocalizedString(
                                "PIN_RECREATION_ERROR_TITLE",
                                comment: "Error title indicating that the attempt to recreate a PIN failed."),
                            message: OWSLocalizedString(
                                "PIN_RECRETION_ERROR_MESSAGE",
                                comment: "Error body indicating that the attempt to recreate a PIN failed.")
                        ) { _ in
                            self.completionHandler(self, error)
                        }
                    case .confirming:
                        owsFailDebug("Unexpected initial mode")
                    }
                }
            }
        }
    }
}

// MARK: -

extension PinSetupViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let hasPendingChanges: Bool
        if pinType == .numeric {
            TextFieldFormatting.ows2FAPINTextField(textField, changeCharactersIn: range, replacementString: string)
            hasPendingChanges = false
        } else {
            hasPendingChanges = true
        }

        // Reset the validation state to clear errors, since the user is trying again
        validationState = .valid

        // Inform our caller whether we took care of performing the change.
        return hasPendingChanges
    }
}

extension PinSetupViewController {
    public class func disablePinWithConfirmation(fromViewController: UIViewController) -> Promise<Bool> {
        guard !OWS2FAManager.shared.isRegistrationLockV2Enabled else {
            return showRegistrationLockConfirmation(fromViewController: fromViewController)
        }

        let (promise, future) = Promise<Bool>.pending()

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString("PIN_CREATION_DISABLE_CONFIRMATION_TITLE",
                                     comment: "Title of the 'pin disable' action sheet."),
            message: OWSLocalizedString("PIN_CREATION_DISABLE_CONFIRMATION_MESSAGE",
                                       comment: "Message of the 'pin disable' action sheet.")
        )

        let cancelAction = ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel) { _ in
            future.resolve(false)
        }
        actionSheet.addAction(cancelAction)

        let disableAction = ActionSheetAction(
            title: OWSLocalizedString("PIN_CREATION_DISABLE_CONFIRMATION_ACTION",
                                     comment: "Action of the 'pin disable' action sheet."),
            style: .destructive
        ) { _ in
            ModalActivityIndicatorViewController.present(
                fromViewController: fromViewController,
                canCancel: false
            ) { modal in
                SDSDatabaseStorage.shared.asyncWrite { transaction in
                    // TODO[ViewContextPiping]
                    ViewControllerContext.shared.svr.useDeviceLocalMasterKey(
                        authedAccount: .implicit(),
                        transaction: transaction.asV2Write
                    )

                    transaction.addAsyncCompletionOnMain {
                        modal.dismiss { future.resolve(true) }
                    }
                }
            }
        }
        actionSheet.addAction(disableAction)

        fromViewController.presentActionSheet(actionSheet)

        return promise
    }

    private class func showRegistrationLockConfirmation(fromViewController: UIViewController) -> Promise<Bool> {
        let (promise, future) = Promise<Bool>.pending()

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString("PIN_CREATION_REGLOCK_CONFIRMATION_TITLE",
                                     comment: "Title of the 'pin disable' reglock action sheet."),
            message: OWSLocalizedString("PIN_CREATION_REGLOCK_CONFIRMATION_MESSAGE",
                                       comment: "Message of the 'pin disable' reglock action sheet.")
        )

        let cancelAction = ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel) { _ in
            future.resolve(false)
        }
        actionSheet.addAction(cancelAction)

        let disableAction = ActionSheetAction(
            title: OWSLocalizedString("PIN_CREATION_REGLOCK_CONFIRMATION_ACTION",
                                     comment: "Action of the 'pin disable' reglock action sheet."),
            style: .destructive
        ) { _ in
            ModalActivityIndicatorViewController.present(
                fromViewController: fromViewController,
                canCancel: false
            ) { modal in
                OWS2FAManager.shared.disableRegistrationLockV2().then {
                    Guarantee { resolve in
                        modal.dismiss { resolve(()) }
                    }
                }.then { () -> Promise<Bool> in
                    disablePinWithConfirmation(fromViewController: fromViewController)
                }.done { success in
                    future.resolve(success)
                }.catch { error in
                    modal.dismiss { future.reject(error) }
                }
            }
        }
        actionSheet.addAction(disableAction)

        fromViewController.presentActionSheet(actionSheet)

        return promise
    }
}
