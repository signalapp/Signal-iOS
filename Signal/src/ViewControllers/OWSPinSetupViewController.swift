//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc(OWSPinSetupViewController)
public class PinSetupViewController: OWSViewController {

    private let pinTextField = UITextField()

    private var pinStrokeNormal: UIView?
    private var pinStrokeError: UIView?
    private let validationWarningLabel = UILabel()

    enum Mode {
        case creating
        case confirming(pinToMatch: String)
    }
    private let mode: Mode

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

    private let completionHandler: () -> Void

    init(mode: Mode, completionHandler: @escaping () -> Void) {
        self.mode = mode
        self.completionHandler = completionHandler
        super.init(nibName: nil, bundle: nil)
    }

    @objc
    convenience init(completionHandler: @escaping () -> Void) {
        self.init(mode: .creating, completionHandler: completionHandler)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // TODO: Maybe do this in will appear, to avoid the keyboard sliding in when the view is pushed?
        pinTextField.becomeFirstResponder()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
    }

    override public func loadView() {
        super.loadView()

        if navigationController == nil {
            owsFailDebug("This view should always be presented in a nav controller")
        }

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero

        // Back button

        let backButton = UIButton()
        let backButtonImage = CurrentAppContext().isRTL ? #imageLiteral(resourceName: "NavBarBackRTL") : #imageLiteral(resourceName: "NavBarBack")
        backButton.tintColor = Theme.secondaryColor
        backButton.setImage(backButtonImage.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.autoSetDimensions(to: CGSize(width: 40, height: 40))
        backButton.addTarget(self, action: #selector(navigateBack), for: .touchUpInside)

        let backButtonRow = UIView()
        backButtonRow.addSubview(backButton)
        backButton.autoPinEdge(toSuperviewEdge: .leading)
        backButton.autoPinHeightToSuperview()

        // Title

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("PIN_CREATION_TITLE", comment: "Title of the 'pin creation' view.")
        titleLabel.textColor = Theme.primaryColor
        titleLabel.font = UIFont.ows_dynamicTypeTitle1Clamped.ows_semiBold()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center

        // Explanation

        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.secondaryColor
        explanationLabel.font = .ows_dynamicTypeSubheadlineClamped

        switch mode {
        case .creating:
            let explanationFormat = NSLocalizedString("PIN_CREATION_EXPLANATION_FORMAT",
                                                      comment: "The explanation in the 'pin creation' view that takes in a bold string.")

            let explanationBoldText = NSLocalizedString("PIN_CREATION_BOLD_EXPLANATION",
                                                        comment: "The bold portion of the explanation in the 'pin creation' view.")

            let explanationString = String(format: explanationFormat, explanationBoldText)
            let boldRange = (explanationString as NSString).range(of: explanationBoldText)

            let attributedExplanation = NSMutableAttributedString(string: explanationString)

            attributedExplanation.addAttribute(.font, value: UIFont.ows_dynamicTypeSubheadlineClamped.ows_bold(), range: boldRange)

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
        pinTextField.keyboardType = .numberPad
        pinTextField.textColor = Theme.primaryColor
        pinTextField.font = .ows_dynamicTypeTitle2Clamped
        pinTextField.isSecureTextEntry = true
        pinTextField.defaultTextAttributes.updateValue(5, forKey: .kern)
        pinTextField.keyboardAppearance = Theme.keyboardAppearance
        pinTextField.setContentHuggingHorizontalLow()
        pinTextField.setCompressionResistanceHorizontalLow()
        pinTextField.autoSetDimension(.height, toSize: 40)
        pinTextField.accessibilityIdentifier = "pinCreation.pinTextField"

        pinStrokeNormal = pinTextField.addBottomStroke()
        pinStrokeError = pinTextField.addBottomStroke(color: .ows_destructiveRed, strokeWidth: 2)

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
        // Button height should be 48pt if the font is 17pt.
        let buttonHeight = font.pointSize * 48 / 17
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

        let stackView = UIStackView(arrangedSubviews: [
            backButtonRow,
            titleLabel,
            UIView.spacer(withHeight: 10),
            explanationLabel,
            topSpacer,
            pinStackRow,
            bottomSpacer,
            UIView.spacer(withHeight: 10),
            nextButton
        ])
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

        navigationController?.popViewController(animated: true)
    }

    @objc func nextPressed() {
        Logger.info("")

        tryToContinue()
    }

    private func tryToContinue() {
        Logger.info("")

        guard let pin = pinTextField.text?.ows_stripped(), pin.count > 3 else {
            validationState = .tooShort
            return
        }

        if case .confirming(let pinToMatch) = mode, pinToMatch != pin {
            validationState = .mismatch
            return
        }

        switch mode {
        case .creating:
            let confirmingVC = PinSetupViewController(mode: .confirming(pinToMatch: pin), completionHandler: completionHandler)
            navigationController?.pushViewController(confirmingVC, animated: true)
        case .confirming:
            enable2FAAndContinue(withPin: pin)
        }
    }

    private func updateValidationWarnings() {
        AssertIsOnMainThread()

        pinStrokeNormal?.isHidden = validationState.isInvalid
        pinStrokeError?.isHidden = !validationState.isInvalid
        validationWarningLabel.isHidden = !validationState.isInvalid

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

    private func enable2FAAndContinue(withPin pin: String) {
        Logger.debug("")

        pinTextField.resignFirstResponder()

        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modalVC in
            OWS2FAManager.shared().requestEnable2FA(withPin: pin, success: { [weak self] in
                modalVC.dismiss {
                    self?.completionHandler()
                }
            }, failure: { error in
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
        let newString = string.digitsOnly
        var oldText = ""
        if let textFieldText = textField.text {
            oldText = textFieldText
        }
        let left = oldText.substring(to: range.location)
        let right = oldText.substring(from: range.location + range.length)
        textField.text = left + newString + right

        // Reset the validation state to clear errors, since the user is trying again
        validationState = .valid

        // Inform our caller that we took care of performing the change.
        return false
    }
}
