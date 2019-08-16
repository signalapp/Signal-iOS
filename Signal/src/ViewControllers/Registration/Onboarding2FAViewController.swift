//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class Onboarding2FAViewController: OnboardingBaseViewController {

    // When the users attempts remaining falls below this number,
    // we will show an alert with more detail about the risks.
    private let attemptsAlertThreshold = 4

    private let pinTextField = UITextField()

    private lazy var pinStrokeNormal = pinTextField.addBottomStroke()
    private lazy var pinStrokeError = pinTextField.addBottomStroke(color: .ows_destructiveRed, strokeWidth: 2)
    private let validationWarningLabel = UILabel()

    enum PinAttemptState {
        case unattempted
        case invalid(remainingAttempts: UInt32?)
        case exhausted
        case valid

        var isInvalid: Bool {
            switch self {
            case .unattempted, .valid:
                return false
            case .invalid, .exhausted:
                return true
            }
        }
    }
    private var attemptState: PinAttemptState = .unattempted {
        didSet {
            updateValidationWarnings()
        }
    }

    override public func loadView() {
        super.loadView()

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero

        let titleText: String
        let explanationText: String

        if (FeatureFlags.pinsForEveryone) {
            titleText = NSLocalizedString("ONBOARDING_PIN_TITLE", comment: "Title of the 'onboarding PIN' view.")
            explanationText = NSLocalizedString("ONBOARDING_PIN_EXPLANATION", comment: "Title of the 'onboarding PIN' view.")
        } else {
            titleText = NSLocalizedString("ONBOARDING_2FA_TITLE", comment: "Title of the 'onboarding 2FA' view.")
            let explanationText1 = NSLocalizedString("ONBOARDING_2FA_EXPLANATION_1",
                                                     comment: "The first explanation in the 'onboarding 2FA' view.")
            let explanationText2 = NSLocalizedString("ONBOARDING_2FA_EXPLANATION_2",
                                                     comment: "The first explanation in the 'onboarding 2FA' view.")

            explanationText = explanationText1 + "\n\n" + explanationText2
        }

        let titleLabel = self.titleLabel(text: titleText)
        let explanationLabel = self.explanationLabel(explanationText: explanationText)
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.accessibilityIdentifier = "onboarding.2fa." + "explanationLabel"

        pinTextField.delegate = self
        pinTextField.isSecureTextEntry = true
        pinTextField.keyboardType = .numberPad
        pinTextField.textColor = Theme.primaryColor
        pinTextField.font = .ows_dynamicTypeBodyClamped
        pinTextField.isSecureTextEntry = true
        pinTextField.defaultTextAttributes.updateValue(5, forKey: .kern)
        pinTextField.keyboardAppearance = Theme.keyboardAppearance
        pinTextField.setContentHuggingHorizontalLow()
        pinTextField.setCompressionResistanceHorizontalLow()
        pinTextField.autoSetDimension(.height, toSize: 40)
        pinTextField.accessibilityIdentifier = "onboarding.2fa.pinTextField"

        validationWarningLabel.textColor = .ows_destructiveRed
        validationWarningLabel.font = UIFont.ows_dynamicTypeCaption1Clamped
        validationWarningLabel.accessibilityIdentifier = "onboarding.2fa.validationWarningLabel"
        validationWarningLabel.numberOfLines = 0
        validationWarningLabel.setCompressionResistanceHigh()

        let forgotPinLink = self.linkButton(title: NSLocalizedString("ONBOARDING_2FA_FORGOT_PIN_LINK",
                                                                     comment: "Label for the 'forgot 2FA PIN' link in the 'onboarding 2FA' view."),
                                            selector: #selector(forgotPinLinkTapped))
        forgotPinLink.accessibilityIdentifier = "onboarding.2fa." + "forgotPinLink"

        let pinStack = UIStackView(arrangedSubviews: [
            pinTextField,
            UIView.spacer(withHeight: 10),
            validationWarningLabel,
            UIView.spacer(withHeight: 10),
            forgotPinLink
        ])
        pinStack.axis = .vertical
        pinStack.alignment = .fill

        let pinStackRow = UIView()
        pinStackRow.addSubview(pinStack)
        pinStack.autoHCenterInSuperview()
        pinStack.autoPinHeightToSuperview()
        pinStack.autoSetDimension(.width, toSize: 227)
        pinStackRow.setContentHuggingVerticalHigh()

        let nextButton = self.button(title: NSLocalizedString("BUTTON_NEXT",
                                                              comment: "Label for the 'next' button."),
                                     selector: #selector(nextPressed))
        nextButton.accessibilityIdentifier = "onboarding.2fa." + "nextButton"

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 10),
            explanationLabel,
            topSpacer,
            pinStackRow,
            bottomSpacer,
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

        OWSAlerts.showAlert(
            title: NSLocalizedString("REGISTER_2FA_FORGOT_PIN_ALERT_TITLE",
                                     comment: "Alert title explaining what happens if you forget your 'two-factor auth pin'."),
            message: NSLocalizedString("REGISTER_2FA_FORGOT_PIN_ALERT_MESSAGE",
                                       comment: "Alert message explaining what happens if you forget your 'two-factor auth pin'.")
        )
    }

    @objc func nextPressed() {
        Logger.info("")

        tryToVerify()
    }

    private func tryToVerify(testTruncatedPin: Bool = false) {
        Logger.info("")

        var pinToUse = pinTextField.text

        // If true, we're doing a fallback verification to test if this is a
        // legacy pin that was created with >16 characters and then truncated.
        if testTruncatedPin {
            assert((pinToUse?.count ?? 0) > kLegacyTruncated2FAv1PinLength)
            pinToUse = pinToUse?.substring(to: Int(kLegacyTruncated2FAv1PinLength))
        }

        guard let pin = pinToUse?.ows_stripped(), pin.count >= kMin2FAPinLength else {
            // Check if we're already in an invalid state, if so we can do nothing
            guard !attemptState.isInvalid else { return }
            attemptState = .invalid(remainingAttempts: nil)
            return
        }

        // v1 pins also have a max length, but we'll rely on the server to verify that
        // since we do not know if this is a v1 or a v2 pin at registration time.

        onboardingController.update(twoFAPin: pin)

        onboardingController.submitVerification(fromViewController: self, completion: { (outcome) in
            switch outcome {
            case .invalid2FAPin:
                // In the past, we used to truncate pins. To support legacy users,
                // also attempt the truncated version of the pin if the original
                // did not match. This error only occurs for v1 registration locks,
                // the variant that includes remaining attempts is used for v2 locks
                // which should not have this problem.
                guard pin.count <= kLegacyTruncated2FAv1PinLength || testTruncatedPin else {
                    return self.tryToVerify(testTruncatedPin: true)
                }

                self.attemptState = .invalid(remainingAttempts: nil)
            case .invalidV2RegistrationLockPin(let remainingAttempts):
                self.attemptState = .invalid(remainingAttempts: remainingAttempts)
            case .exhaustedV2RegistrationLockAttempts:
                self.attemptState = .exhausted
                self.showAccountLocked()
            case .success:
                self.attemptState = .valid
            case .invalidVerificationCode:
                owsFailDebug("Invalid verification code in 2FA view.")
            }
        })
    }

    private func showAccountLocked() {
        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        let vc = OnboardingAccountLockedViewController(onboardingController: onboardingController)
        navigationController.pushViewController(vc, animated: true)
    }

    private func updateValidationWarnings() {
        AssertIsOnMainThread()

        pinStrokeNormal.isHidden = attemptState.isInvalid
        pinStrokeError.isHidden = !attemptState.isInvalid
        validationWarningLabel.isHidden = !attemptState.isInvalid

        switch attemptState {
        case .exhausted:
            validationWarningLabel.text = NSLocalizedString("ONBOARDING_2FA_ATTEMPTS_EXHAUSTED",
                                                            comment: "Label indicating that the 2fa pin is exhausted in the 'onboarding 2fa' view.")
        case .invalid(let remainingAttempts):
            guard let remaining = remainingAttempts else {
                validationWarningLabel.text = NSLocalizedString("ONBOARDING_2FA_INVALID_PIN",
                                                                comment: "Label indicating that the 2fa pin is invalid in the 'onboarding 2fa' view.")
                break
            }

            // If there are less than the threshold attempts remaining, also show an alert with more detail.
            if remaining < attemptsAlertThreshold {
                let formatMessage: String
                if remaining == 1 {
                    formatMessage = NSLocalizedString("REGISTER_2FA_INVALID_PIN_ALERT_MESSAGE_SINGLE",
                                                      comment: "Alert message explaining what happens if you get your pin wrong and have one attempt remaining 'two-factor auth pin'.")
                } else {
                    formatMessage = NSLocalizedString("REGISTER_2FA_INVALID_PIN_ALERT_MESSAGE_PLURAL_FORMAT",
                                                      comment: "Alert message explaining what happens if you get your pin wrong and have multiple attempts remaining 'two-factor auth pin'.")
                }

                OWSAlerts.showAlert(
                    title: NSLocalizedString("REGISTER_2FA_INVALID_PIN_ALERT_TITLE",
                                             comment: "Alert title explaining what happens if you forget your 'two-factor auth pin'."),
                    message: String(format: formatMessage, remaining)
                )
            }

            let formatMessage: String
            if remaining == 1 {
                formatMessage = NSLocalizedString("ONBOARDING_2FA_INVALID_PIN_SINGLE",
                                                  comment: "Label indicating that the 2fa pin is invalid with a retry count of one in the 'onboarding 2fa' view.")
            } else {
                formatMessage = NSLocalizedString("ONBOARDING_2FA_INVALID_PIN_PLURAL_FORMAT",
                                                  comment: "Label indicating that the 2fa pin is invalid with a retry count other than one in the 'onboarding 2fa' view.")
            }

            validationWarningLabel.text = String(format: formatMessage, remaining)

        default:
            break
        }
    }
}

// MARK: -

extension Onboarding2FAViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        ViewControllerUtils.ows2FAPINTextField(textField, shouldChangeCharactersIn: range, replacementString: string)

        // Reset the attempt state to clear errors, since the user is trying again
        attemptState = .unattempted

        return false
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        tryToVerify()
        return false
    }
}
