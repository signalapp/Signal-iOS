//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class Onboarding2FAViewController: OnboardingBaseViewController {

    private let pinTextField = UITextField()

    private var pinStrokeNormal: UIView?
    private var pinStrokeError: UIView?
    private let validationWarningLabel = UILabel()
    private var isPinInvalid = false {
        didSet {
            updateValidationWarnings()
        }
    }

    override public func loadView() {
        super.loadView()

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero

        let titleLabel = self.titleLabel(text: NSLocalizedString("ONBOARDING_2FA_TITLE", comment: "Title of the 'onboarding 2FA' view."))

        let explanationLabel1 = self.explanationLabel(explanationText: NSLocalizedString("ONBOARDING_2FA_EXPLANATION_1",
                                                                                         comment: "The first explanation in the 'onboarding 2FA' view."))
        let explanationLabel2 = self.explanationLabel(explanationText: NSLocalizedString("ONBOARDING_2FA_EXPLANATION_2",
                                                                                         comment: "The first explanation in the 'onboarding 2FA' view."))
        explanationLabel1.font = UIFont.ows_dynamicTypeCaption1
        explanationLabel2.font = UIFont.ows_dynamicTypeCaption1
        explanationLabel1.accessibilityIdentifier = "onboarding.2fa." + "explanationLabel1"
        explanationLabel2.accessibilityIdentifier = "onboarding.2fa." + "explanationLabel2"

        pinTextField.textAlignment = .center
        pinTextField.delegate = self
        pinTextField.keyboardType = .numberPad
        pinTextField.textColor = Theme.primaryColor
        pinTextField.font = UIFont.ows_dynamicTypeBodyClamped
        pinTextField.setContentHuggingHorizontalLow()
        pinTextField.setCompressionResistanceHorizontalLow()
        pinTextField.autoSetDimension(.height, toSize: 40)
        pinTextField.accessibilityIdentifier = "onboarding.2fa." + "pinTextField"

        pinStrokeNormal = pinTextField.addBottomStroke()
        pinStrokeError = pinTextField.addBottomStroke(color: .ows_destructiveRed, strokeWidth: 2)

        validationWarningLabel.text = NSLocalizedString("ONBOARDING_PHONE_NUMBER_VALIDATION_WARNING",
                                                        comment: "Label indicating that the phone number is invalid in the 'onboarding phone number' view.")
        validationWarningLabel.textColor = .ows_destructiveRed
        validationWarningLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        validationWarningLabel.textAlignment = .center
        validationWarningLabel.accessibilityIdentifier = "onboarding.2fa." + "validationWarningLabel"

        let validationWarningRow = UIView()
        validationWarningRow.addSubview(validationWarningLabel)
        validationWarningLabel.ows_autoPinToSuperviewEdges()
        validationWarningRow.autoSetDimension(.height, toSize: validationWarningLabel.font.lineHeight)

        let forgotPinLink = self.linkButton(title: NSLocalizedString("ONBOARDING_2FA_FORGOT_PIN_LINK",
                                                                     comment: "Label for the 'forgot 2FA PIN' link in the 'onboarding 2FA' view."),
                                            selector: #selector(forgotPinLinkTapped))
        forgotPinLink.accessibilityIdentifier = "onboarding.2fa." + "forgotPinLink"

        let nextButton = self.button(title: NSLocalizedString("BUTTON_NEXT",
                                                              comment: "Label for the 'next' button."),
                                     selector: #selector(nextPressed))
        nextButton.accessibilityIdentifier = "onboarding.2fa." + "nextButton"

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 10),
            explanationLabel1,
            UIView.spacer(withHeight: 10),
            explanationLabel2,
            topSpacer,
            pinTextField,
            UIView.spacer(withHeight: 10),
            validationWarningRow,
            bottomSpacer,
            forgotPinLink,
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

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        _ = pinTextField.becomeFirstResponder()
    }

    // MARK: - Events

    @objc func forgotPinLinkTapped() {
        Logger.info("")

        OWSAlerts.showAlert(title: nil, message: NSLocalizedString("REGISTER_2FA_FORGOT_PIN_ALERT_MESSAGE",
                                                                   comment: "Alert message explaining what happens if you forget your 'two-factor auth pin'."))
    }

    @objc func nextPressed() {
        Logger.info("")

        tryToVerify()
    }

    private func tryToVerify() {
        Logger.info("")

        guard let pin = pinTextField.text?.ows_stripped(),
            pin.count > 0 else {
                isPinInvalid = true
            return
        }

        isPinInvalid = false

        onboardingController.update(twoFAPin: pin)

        onboardingController.tryToVerify(fromViewController: self, completion: { (outcome) in
            if outcome == .invalid2FAPin {
                self.isPinInvalid = true
            } else if outcome == .invalidVerificationCode {
                owsFailDebug("Invalid verification code in 2FA view.")
            }
        })
    }

    private func updateValidationWarnings() {
        AssertIsOnMainThread()

        pinStrokeNormal?.isHidden = isPinInvalid
        pinStrokeError?.isHidden = !isPinInvalid
        validationWarningLabel.isHidden = !isPinInvalid
    }
}

// MARK: -

extension Onboarding2FAViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let newString = string.digitsOnly
        var oldText = ""
        if let textFieldText = textField.text {
            oldText = textFieldText
        }
        let left = oldText.substring(to: range.location)
        let right = oldText.substring(from: range.location + range.length)
        textField.text = left + newString + right

        isPinInvalid = false

        // Inform our caller that we took care of performing the change.
        return false
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        tryToVerify()
        return false
    }
}
