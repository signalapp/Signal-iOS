//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc(OWSPinSetupViewController)
public class PinSetupViewController: OWSViewController {

    private let pinTextField = UITextField()
    private let pinTypeToggle = UIButton()

    private lazy var pinStrokeNormal = pinTextField.addBottomStroke()
    private lazy var pinStrokeError = pinTextField.addBottomStroke(color: .ows_accentRed, strokeWidth: 2)
    private let validationWarningLabel = UILabel()
    private let recommendationLabel = UILabel()

    enum Mode {
        case creating
        case recreating
        case changing
        case confirming(pinToMatch: String)

        var isChanging: Bool {
            guard case .changing = self else { return false }
            return true
        }

        var isConfirming: Bool {
            guard case .confirming = self else { return false }
            return true
        }
    }
    private let mode: Mode

    private let initialMode: Mode

    enum ValidationState {
        case valid
        case tooShort
        case mismatch

        var isInvalid: Bool {
            return self != .valid
        }
    }
    private var validationState: ValidationState = .valid {
        didSet {
            updateValidationWarnings()
        }
    }

    private var pinType: KeyBackupService.PinType {
        didSet {
            updatePinType()
        }
    }

    private let completionHandler: () -> Void

    init(mode: Mode, initialMode: Mode? = nil, pinType: KeyBackupService.PinType = .numeric, completionHandler: @escaping () -> Void) {
        assert(TSAccountManager.sharedInstance().isRegisteredPrimaryDevice)
        self.mode = mode
        self.initialMode = initialMode ?? mode
        self.pinType = pinType
        self.completionHandler = completionHandler
        super.init(nibName: nil, bundle: nil)

        if case .confirming = self.initialMode {
            owsFailDebug("pin setup flow should never start in the confirming state")
        }
    }

    @objc
    convenience init(completionHandler: @escaping () -> Void) {
        self.init(mode: .creating, completionHandler: completionHandler)
    }

    @objc
    class func changing(completionHandler: @escaping () -> Void) -> PinSetupViewController {
        return .init(mode: .changing, completionHandler: completionHandler)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Don't hide the nav bar when changing
        guard !initialMode.isChanging else { return }

        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // TODO: Maybe do this in will appear, to avoid the keyboard sliding in when the view is pushed?
        pinTextField.becomeFirstResponder()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Don't hide the nav bar when changing
        guard !initialMode.isChanging else { return }

        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
    }

    override public func loadView() {
        view = UIView()

        if navigationController == nil {
            owsFailDebug("This view should always be presented in a nav controller")
        }

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero

        let topRow: UIView?
        let titleLabel: UILabel?

        // We have a nav bar and use the nav bar back button + title
        if initialMode.isChanging {
            topRow = nil
            titleLabel = nil

            title = NSLocalizedString("PIN_CREATION_CHANGING_TITLE", comment: "Title of the 'pin creation' recreation view.")

        // We have no nav bar and build our own back button + title label
        } else {
            // Back button

            let topButton = UIButton()
            let topButtonImage = CurrentAppContext().isRTL ? #imageLiteral(resourceName: "NavBarBackRTL") : #imageLiteral(resourceName: "NavBarBack")

            topButton.setTemplateImage(topButtonImage, tintColor: Theme.secondaryTextAndIconColor)
            topButton.autoSetDimensions(to: CGSize(width: 40, height: 40))
            topButton.addTarget(self, action: #selector(navigateBack), for: .touchUpInside)

            let topButtonRow = UIView()
            topButtonRow.addSubview(topButton)
            topButton.autoPinEdge(toSuperviewEdge: .leading)
            topButton.autoPinHeightToSuperview()

            // Title

            let label = UILabel()
            label.textColor = Theme.primaryTextColor
            label.font = UIFont.ows_dynamicTypeTitle1Clamped.ows_semibold()
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.textAlignment = .center

            titleLabel = label

            let arrangedSubviews: [UIView]

            // If we're in creating mode AND we're the rootViewController, don't allow going back
            if case .creating = mode, navigationController?.viewControllers.first == self {
                arrangedSubviews = [UIView.spacer(withHeight: 40), label, UIView.spacer(withHeight: 10)]
            } else {
                arrangedSubviews = [topButtonRow, label, UIView.spacer(withHeight: 10)]
            }

            let row = UIStackView(arrangedSubviews: arrangedSubviews)
            row.axis = .vertical
            row.distribution = .fill
            topRow = row
        }

        switch initialMode {
        case .recreating:
            titleLabel?.text = NSLocalizedString("PIN_CREATION_RECREATION_TITLE", comment: "Title of the 'pin creation' recreation view.")
        default:
            titleLabel?.text = NSLocalizedString("PIN_CREATION_TITLE", comment: "Title of the 'pin creation' view.")
        }

        // Explanation

        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.font = .ows_dynamicTypeSubheadlineClamped

        switch mode {
        case .creating, .changing:
            let explanationText = NSLocalizedString("PIN_CREATION_EXPLANATION",
                                                      comment: "The explanation in the 'pin creation' view.")

            let explanationBoldText = NSLocalizedString("PIN_CREATION_BOLD_EXPLANATION",
                                                        comment: "The bold portion of the explanation in the 'pin creation' view.")

            let attributedExplanation = NSAttributedString(string: explanationText) + " " + NSAttributedString(string: explanationBoldText, attributes: [.font: UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold()])

            explanationLabel.attributedText = attributedExplanation
        case .recreating:
            let explanationText = NSLocalizedString("PIN_CREATION_RECREATION_EXPLANATION",
                                                    comment: "The re-creation explanation in the 'pin creation' view.")

            let explanationBoldText = NSLocalizedString("PIN_CREATION_RECREATION_BOLD_EXPLANATION",
                                                        comment: "The bold portion of the re-creation explanation in the 'pin creation' view.")

            let attributedExplanation = NSAttributedString(string: explanationText) + " " + NSAttributedString(string: explanationBoldText, attributes: [.font: UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold()])

            explanationLabel.attributedText = attributedExplanation
        case .confirming:
            explanationLabel.text = NSLocalizedString("PIN_CREATION_CONFIRMATION_EXPLANATION",
                                                      comment: "The explanation of confirmation in the 'pin creation' view.")
        }

        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.accessibilityIdentifier = "pinCreation.explanationLabel"

        // Pin text field

        pinTextField.delegate = self
        pinTextField.textColor = Theme.primaryTextColor
        pinTextField.font = .ows_dynamicTypeBodyClamped
        pinTextField.isSecureTextEntry = true
        pinTextField.defaultTextAttributes.updateValue(5, forKey: .kern)
        pinTextField.keyboardAppearance = Theme.keyboardAppearance
        pinTextField.setContentHuggingHorizontalLow()
        pinTextField.setCompressionResistanceHorizontalLow()
        pinTextField.autoSetDimension(.height, toSize: 40)
        pinTextField.accessibilityIdentifier = "pinCreation.pinTextField"

        validationWarningLabel.textColor = .ows_accentRed
        validationWarningLabel.textAlignment = .center
        validationWarningLabel.font = UIFont.ows_dynamicTypeCaption1Clamped
        validationWarningLabel.accessibilityIdentifier = "pinCreation.validationWarningLabel"

        recommendationLabel.textColor = Theme.secondaryTextAndIconColor
        recommendationLabel.textAlignment = .center
        recommendationLabel.font = UIFont.ows_dynamicTypeCaption1Clamped
        recommendationLabel.accessibilityIdentifier = "pinCreation.recommendationLabel"

        let pinStack = UIStackView(arrangedSubviews: [
            pinTextField,
            UIView.spacer(withHeight: 10),
            validationWarningLabel,
            recommendationLabel
        ])
        pinStack.axis = .vertical
        pinStack.alignment = .fill

        let pinStackRow = UIView()
        pinStackRow.addSubview(pinStack)
        pinStack.autoHCenterInSuperview()
        pinStack.autoPinHeightToSuperview()
        pinStack.autoSetDimension(.width, toSize: 227)
        pinStackRow.setContentHuggingVerticalHigh()

        pinTypeToggle.setTitleColor(.ows_signalBlue, for: .normal)
        pinTypeToggle.titleLabel?.font = .ows_dynamicTypeSubheadlineClamped
        pinTypeToggle.addTarget(self, action: #selector(togglePinType), for: .touchUpInside)
        pinTypeToggle.accessibilityIdentifier = "pinCreation.pinTypeToggle"

        let font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold()
        let buttonHeight = OWSFlatButton.heightForFont(font)
        let nextButton = OWSFlatButton.button(
            title: CommonStrings.nextButton,
            font: font,
            titleColor: .white,
            backgroundColor: .ows_signalBlue,
            target: self,
            selector: #selector(nextPressed)
        )
        nextButton.autoSetDimension(.height, toSize: buttonHeight)
        nextButton.accessibilityIdentifier = "pinCreation.nextButton"
        let primaryButtonView = OnboardingBaseViewController.horizontallyWrap(primaryButton: nextButton)

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        var arrangedSubviews = [
            explanationLabel,
            topSpacer,
            pinStackRow,
            bottomSpacer,
            UIView.spacer(withHeight: 10),
            pinTypeToggle,
            UIView.spacer(withHeight: 10),
            primaryButtonView
        ]

        if let topRow = topRow {
            arrangedSubviews.insert(topRow, at: 0)
        }

        let stackView = UIStackView(arrangedSubviews: arrangedSubviews)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)

        // Ensure whitespace is balanced, so inputs are vertically centered.
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        updateValidationWarnings()
        updatePinType()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Don't allow interactive dismissal.
        if #available(iOS 13, *) {
            isModalInPresentation = true
        }
    }

    // MARK: - Events

    @objc func navigateBack() {
        Logger.info("")

        if case .recreating = mode {
            dismiss(animated: true, completion: nil)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc func nextPressed() {
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

        switch mode {
        case .creating, .changing, .recreating:
            let confirmingVC = PinSetupViewController(
                mode: .confirming(pinToMatch: pin),
                initialMode: initialMode,
                pinType: pinType,
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
            validationWarningLabel.text = NSLocalizedString("PIN_CREATION_TOO_SHORT_ERROR",
                                                            comment: "Label indicating that the attempted PIN is too short")
        case .mismatch:
            validationWarningLabel.text = NSLocalizedString("PIN_CREATION_MISMATCH_ERROR",
                                                            comment: "Label indicating that the attempted PIN does not match the first PIN")
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
            pinTypeToggle.setTitle(NSLocalizedString("PIN_CREATION_CREATE_ALPHANUMERIC",
                                                     comment: "Button asking if the user would like to create an alphanumeric PIN"), for: .normal)
            pinTextField.keyboardType = .asciiCapableNumberPad
            recommendationLabelText = NSLocalizedString("PIN_CREATION_NUMERIC_HINT",
                                                         comment: "Label indicating the user must use at least 6 digits")
        case .alphanumeric:
            pinTypeToggle.setTitle(NSLocalizedString("PIN_CREATION_CREATE_NUMERIC",
                                                     comment: "Button asking if the user would like to create an numeric PIN"), for: .normal)
            pinTextField.keyboardType = .default
            recommendationLabelText = NSLocalizedString("PIN_CREATION_ALPHANUMERIC_HINT",
                                                         comment: "Label indicating the user must use at least 6 characters")
        }

        pinTextField.reloadInputViews()

        if mode.isConfirming {
            pinTypeToggle.isHidden = true
            recommendationLabel.text = NSLocalizedString("PIN_CREATION_PIN_CONFIRMATION_HINT",
                                                         comment: "Label indication the user must confirm their PIN.")
        } else {
            pinTypeToggle.isHidden = false
            recommendationLabel.text = recommendationLabelText
        }
    }

    @objc func togglePinType() {
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

        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modalVC in
            OWS2FAManager.shared().requestEnable2FA(withPin: pin, success: { [weak self] in
                AssertIsOnMainThread()

                modalVC.dismiss {
                    self?.completionHandler()
                }
            }, failure: { error in
                AssertIsOnMainThread()

                Logger.error("Failed to enable 2FA with error: \(error)")

                // The client may have fallen out of sync with the service.
                // Try to get back to a known good state by disabling 2FA
                // whenever enabling it fails.
                OWS2FAManager.shared().disable2FA(success: nil, failure: nil)

                modalVC.dismiss {
                    // If this is the first time the user is trying to create a PIN, it's a blocking flow.
                    // If for some reason they hit an error, notify them that we'll try again later and
                    // dismiss the flow so they aren't stuck.
                    if case .creating = self.initialMode {
                        OWSActionSheets.showActionSheet(
                            title: NSLocalizedString("PIN_CREATION_ERROR_TITLE",
                                                     comment: "Error title indicating that the attempt to create a PIN failed."),
                            message: NSLocalizedString("PIN_CREATION_ERROR_MESSAGE",
                                                       comment: "Error body indicating that the attempt to create a PIN failed.")
                        ) { _ in
                            self.dismiss(animated: true, completion: nil)
                        }
                    } else {
                        OWSActionSheets.showErrorAlert(message: NSLocalizedString("ENABLE_2FA_VIEW_COULD_NOT_ENABLE_2FA", comment: "Error indicating that attempt to enable 'two-factor auth' failed."))
                    }
                }
            })
        }
    }
}

// MARK: -

extension PinSetupViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let hasPendingChanges: Bool
        if pinType == .numeric {
            ViewControllerUtils.ows2FAPINTextField(textField, shouldChangeCharactersIn: range, replacementString: string)
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
