//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc(OWSPinSetupViewController)
public class PinSetupViewController: OWSViewController {

    private let pinTextField = UITextField()

    private lazy var pinStrokeNormal = pinTextField.addBottomStroke()
    private lazy var pinStrokeError = pinTextField.addBottomStroke(color: .ows_destructiveRed, strokeWidth: 2)
    private let validationWarningLabel = UILabel()

    enum Mode {
        case creating
        case recreating
        case changing
        case confirming(pinToMatch: String)

        var isChanging: Bool {
            guard case .changing = self else { return false }
            return true
        }
    }
    private let mode: Mode

    private let initialMode: Mode

    enum ValidationState {
        case valid
        case tooShort
        case tooLong
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

    private let completionHandler: () -> Void

    init(mode: Mode, initialMode: Mode? = nil, completionHandler: @escaping () -> Void) {
        self.mode = mode
        self.initialMode = initialMode ?? mode
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

            topButton.setTemplateImage(topButtonImage, tintColor: Theme.secondaryColor)
            topButton.autoSetDimensions(to: CGSize(width: 40, height: 40))
            topButton.addTarget(self, action: #selector(navigateBack), for: .touchUpInside)

            let topButtonRow = UIView()
            topButtonRow.addSubview(topButton)
            topButton.autoPinEdge(toSuperviewEdge: .leading)
            topButton.autoPinHeightToSuperview()

            // Title

            let label = UILabel()
            label.textColor = Theme.primaryColor
            label.font = UIFont.ows_dynamicTypeTitle1Clamped.ows_semiBold()
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
        explanationLabel.textColor = Theme.secondaryColor
        explanationLabel.font = .ows_dynamicTypeSubheadlineClamped

        let placeholderText: String

        switch mode {
        case .creating, .changing:
            let explanationText = NSLocalizedString("PIN_CREATION_EXPLANATION",
                                                      comment: "The explanation in the 'pin creation' view.")

            let explanationBoldText = NSLocalizedString("PIN_CREATION_BOLD_EXPLANATION",
                                                        comment: "The bold portion of the explanation in the 'pin creation' view.")

            let attributedExplanation = NSAttributedString(string: explanationText) + " " + NSAttributedString(string: explanationBoldText, attributes: [.font: UIFont.ows_dynamicTypeSubheadlineClamped.ows_semiBold()])

            explanationLabel.attributedText = attributedExplanation

            placeholderText = NSLocalizedString("PIN_CREATION_PIN_CREATION_PLACEHOLDER", comment: "The placeholder when creating a pin in the 'pin creation' view.")
        case .recreating:
            let explanationText = NSLocalizedString("PIN_CREATION_RECREATION_EXPLANATION",
                                                    comment: "The re-creation explanation in the 'pin creation' view.")

            let explanationBoldText = NSLocalizedString("PIN_CREATION_RECREATION_BOLD_EXPLANATION",
                                                        comment: "The bold portion of the re-creation explanation in the 'pin creation' view.")

            let attributedExplanation = NSAttributedString(string: explanationText) + " " + NSAttributedString(string: explanationBoldText, attributes: [.font: UIFont.ows_dynamicTypeSubheadlineClamped.ows_semiBold()])

            explanationLabel.attributedText = attributedExplanation

            placeholderText = NSLocalizedString("PIN_CREATION_PIN_CREATION_PLACEHOLDER", comment: "The placeholder when creating a pin in the 'pin creation' view.")
        case .confirming:
            explanationLabel.text = NSLocalizedString("PIN_CREATION_CONFIRMATION_EXPLANATION",
                                                      comment: "The explanation of confirmation in the 'pin creation' view.")

            placeholderText = NSLocalizedString("PIN_CREATION_PIN_CONFIRMATION_PLACEHOLDER", comment: "The placeholder when confirming a pin in the 'pin creation' view.")
        }

        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.accessibilityIdentifier = "pinCreation.explanationLabel"

        // Pin text field

        pinTextField.delegate = self
        pinTextField.keyboardType = .numberPad
        pinTextField.textColor = Theme.primaryColor
        pinTextField.font = .ows_dynamicTypeBodyClamped
        pinTextField.isSecureTextEntry = true
        pinTextField.defaultTextAttributes.updateValue(5, forKey: .kern)
        pinTextField.keyboardAppearance = Theme.keyboardAppearance
        pinTextField.setContentHuggingHorizontalLow()
        pinTextField.setCompressionResistanceHorizontalLow()
        pinTextField.autoSetDimension(.height, toSize: 40)
        pinTextField.attributedPlaceholder = NSAttributedString(string: placeholderText, attributes: [.foregroundColor: Theme.placeholderColor])
        pinTextField.accessibilityIdentifier = "pinCreation.pinTextField"

        validationWarningLabel.textColor = .ows_destructiveRed
        validationWarningLabel.font = UIFont.ows_dynamicTypeCaption1Clamped
        validationWarningLabel.accessibilityIdentifier = "pinCreation.validationWarningLabel"

        let pinStack = UIStackView(arrangedSubviews: [
            pinTextField,
            UIView.spacer(withHeight: 10),
            validationWarningLabel
        ])
        pinStack.axis = .vertical
        pinStack.alignment = .fill

        let pinStackRow = UIView()
        pinStackRow.addSubview(pinStack)
        pinStack.autoHCenterInSuperview()
        pinStack.autoPinHeightToSuperview()
        pinStack.autoSetDimension(.width, toSize: 227)
        pinStackRow.setContentHuggingVerticalHigh()

        let font = UIFont.ows_dynamicTypeBodyClamped.ows_mediumWeight()
        let buttonHeight = OWSFlatButton.heightForFont(font)
        let nextButton = OWSFlatButton.button(
            title: NSLocalizedString("BUTTON_NEXT",
                                     comment: "Label for the 'next' button."),
            font: font,
            titleColor: .white,
            backgroundColor: .ows_materialBlue,
            target: self,
            selector: #selector(nextPressed)
        )
        nextButton.autoSetDimension(.height, toSize: buttonHeight)
        nextButton.accessibilityIdentifier = "pinCreation.nextButton"

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        var arrangedSubviews = [
            explanationLabel,
            topSpacer,
            pinStackRow,
            bottomSpacer,
            UIView.spacer(withHeight: 10),
            nextButton
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

        guard let pin = pinTextField.text?.ows_stripped(), pin.count >= kMin2FAPinLength else {
            validationState = .tooShort
            return
        }

        guard FeatureFlags.registrationLockV2 || pin.count <= kMax2FAv1PinLength else {
            validationState = .tooLong
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

        switch validationState {
        case .tooShort:
            validationWarningLabel.text = NSLocalizedString("PIN_CREATION_TOO_SHORT_ERROR",
                                                            comment: "Label indicating that the attempted PIN is too short")
        case .tooLong:
            validationWarningLabel.text = NSLocalizedString("PIN_CREATION_TOO_LONG_ERROR",
                                                            comment: "Label indicating that the attempted PIN is too long")
        case .mismatch:
            validationWarningLabel.text = NSLocalizedString("PIN_CREATION_MISMATCH_ERROR",
                                                            comment: "Label indicating that the attempted PIN does not match the first PIN")
        default:
            break
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
                    OWSAlerts.showErrorAlert(message: NSLocalizedString("ENABLE_2FA_VIEW_COULD_NOT_ENABLE_2FA", comment: "Error indicating that attempt to enable 'two-factor auth' failed."))
                }
            })
        }
    }
}

// MARK: -

extension PinSetupViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        ViewControllerUtils.ows2FAPINTextField(textField, shouldChangeCharactersIn: range, replacementString: string)

        // Reset the validation state to clear errors, since the user is trying again
        validationState = .valid

        // Inform our caller that we took care of performing the change.
        return false
    }
}
