//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
public import SignalUI

final public class PinSetupViewController: OWSViewController, OWSNavigationChildController {

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
        case .creating:
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
                    .link: URL.Support.pin,
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
        case creating
        case changing
        case confirming(pinToMatch: String)

        var isConfirming: Bool {
            switch self {
            case .confirming:
                return true
            case .creating, .changing:
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

    private let showCancelButton: Bool

    // Called once pin setup has finished. Error will be nil upon success
    private let completionHandler: (PinSetupViewController, Error?) -> Void

    private let context: ViewControllerContext

    convenience init(
        mode: Mode,
        showCancelButton: Bool = false,
        completionHandler: @escaping (PinSetupViewController, Error?) -> Void
    ) {
        self.init(
            mode: mode,
            initialMode: mode,
            pinType: .numeric,
            showCancelButton: showCancelButton,
            completionHandler: completionHandler
        )
    }

    private init(
        mode: Mode,
        initialMode: Mode,
        pinType: SVR.PinType,
        showCancelButton: Bool,
        completionHandler: @escaping (PinSetupViewController, Error?) -> Void
    ) {
        assert(DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice)
        self.mode = mode
        self.initialMode = initialMode
        self.pinType = pinType
        self.showCancelButton = showCancelButton
        self.completionHandler = completionHandler
        // TODO[ViewContextPiping]
        self.context = ViewControllerContext.shared
        super.init()

        if case .confirming = self.initialMode {
            owsFailDebug("pin setup flow should never start in the confirming state")
        }
    }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .solid
    }

    public var navbarBackgroundColorOverride: UIColor? {
        return backgroundColor
    }

    public var prefersNavigationBarHidden: Bool { false }

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
            ProvisioningBaseViewController.horizontallyWrap(primaryButton: nextButton),
            buttonSpacer
        ])
        stackView.axis = .vertical
        stackView.alignment = .center
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])

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
        backButton.isHidden = isNavigationBarVisible
        moreButton.isHidden = isNavigationBarVisible

        if showCancelButton {
            self.navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
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
        case .creating:
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
    private func didTapMoreButton() {
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
            let vc = SFSafariViewController(url: URL.Support.pin)
            self.present(vc, animated: true) {
                pinnedHeightConstraint.isActive = false
                self.proportionalSpacerConstraint?.isActive = true
            }
        }
        actionSheet.addAction(learnMoreAction)

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
        case .changing, .creating:
            let confirmingVC = PinSetupViewController(
                mode: .confirming(pinToMatch: pin),
                initialMode: initialMode,
                pinType: pinType,
                showCancelButton: false, // we're pushing, so we never need a cancel button
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

    private enum PinSetupError: Error {
        case networkFailure
        case enable2FA
    }

    private func enable2FAAndContinue(withPin pin: String) {
        Logger.debug("")

        pinTextField.resignFirstResponder()

        let progressView = AnimatedProgressView(
            loadingText: OWSLocalizedString(
                "PIN_CREATION_PIN_PROGRESS",
                comment: "Indicates the work we are doing while creating the user's pin"
            )
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

        Task {
            do {
                try await self._enable2FAAndContinue(withPin: pin)
                DispatchQueue.main.async {
                    // The completion handler always dismisses this view, so we don't want to animate anything.
                    progressView.stopAnimatingImmediately()
                    self.completionHandler(self, nil)
                }
            } catch {
                DispatchQueue.main.async {
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

                        switch error {
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
    }

    private func _enable2FAAndContinue(withPin pin: String) async throws {
        let accountAttributesUpdater = DependenciesBridge.shared.accountAttributesUpdater
        let ows2FAManager = SSKEnvironment.shared.ows2FAManagerRef

        Logger.warn("Setting PIN.")

        do {
            try await ows2FAManager.enablePin(pin)
        } catch {
            owsFailDebug("Failed to set PIN! \(error)")

            if error.isNetworkFailureOrTimeout {
                throw PinSetupError.networkFailure
            }

            throw PinSetupError.enable2FA
        }

        await DependenciesBridge.shared.db.awaitableWrite { tx in
            // Attempt to update account attributes. This should have been
            // handled internally when we enabled things above, but it doesn't
            // hurt to make sure.
            //
            // This just schedules an update to happen eventually; don't wait on
            // the result.
            accountAttributesUpdater.scheduleAccountAttributesUpdate(authedAccount: .implicit(), tx: tx)

            // Clear the experience upgrade if it was pending.
            ExperienceUpgradeManager.clearExperienceUpgrade(.introducingPins, transaction: tx)
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
