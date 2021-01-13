//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class Onboarding2FAViewController: OnboardingBaseViewController {

    // When the users attempts remaining falls below this number,
    // we will show an alert with more detail about the risks.
    private let attemptsAlertThreshold = 4

    private let pinTextField = UITextField()
    private let pinTypeToggle = UIButton()
    private lazy var nextButton = self.primaryButton(title: CommonStrings.nextButton,
                                                     selector: #selector(nextPressed))

    private lazy var pinStrokeNormal = pinTextField.addBottomStroke()
    private lazy var pinStrokeError = pinTextField.addBottomStroke(color: .ows_accentRed, strokeWidth: 2)
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

    private let isUsingKBS: Bool
    private var pinType: KeyBackupService.PinType = .numeric {
        didSet {
            updatePinType()
        }
    }

    private var hasPendingRestoration: Bool {
        databaseStorage.read { KeyBackupService.hasPendingRestoration(transaction: $0) }
    }

    public init(onboardingController: OnboardingController, isUsingKBS: Bool) {
        self.isUsingKBS = isUsingKBS
        super.init(onboardingController: onboardingController)
    }

    var needHelpLink: OWSFlatButton!

    override public func loadView() {
        view = UIView()

        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleText = NSLocalizedString("ONBOARDING_PIN_TITLE", comment: "Title of the 'onboarding PIN' view.")
        let explanationText = NSLocalizedString("ONBOARDING_PIN_EXPLANATION", comment: "Title of the 'onboarding PIN' view.")

        let titleLabel = self.titleLabel(text: titleText)
        let explanationLabel = self.explanationLabel(explanationText: explanationText)
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.accessibilityIdentifier = "onboarding.2fa." + "explanationLabel"

        pinTextField.delegate = self
        pinTextField.isSecureTextEntry = true
        pinTextField.textColor = Theme.primaryTextColor
        pinTextField.textAlignment = .center
        pinTextField.font = .ows_dynamicTypeBodyClamped
        pinTextField.isSecureTextEntry = true
        pinTextField.defaultTextAttributes.updateValue(5, forKey: .kern)
        pinTextField.keyboardAppearance = Theme.keyboardAppearance
        pinTextField.setContentHuggingHorizontalLow()
        pinTextField.setCompressionResistanceHorizontalLow()
        pinTextField.autoSetDimension(.height, toSize: 40)
        pinTextField.accessibilityIdentifier = "onboarding.2fa.pinTextField"

        validationWarningLabel.textColor = .ows_accentRed
        validationWarningLabel.textAlignment = .center
        validationWarningLabel.font = UIFont.ows_dynamicTypeCaption1Clamped
        validationWarningLabel.accessibilityIdentifier = "onboarding.2fa.validationWarningLabel"
        validationWarningLabel.numberOfLines = 0
        validationWarningLabel.setCompressionResistanceHigh()

        self.needHelpLink = self.linkButton(title: NSLocalizedString("ONBOARDING_2FA_FORGOT_PIN_LINK",
                                                                     comment: "Label for the 'forgot 2FA PIN' link in the 'onboarding 2FA' view."),
                                            selector: #selector(needHelpLinkWasTapped))
        needHelpLink.accessibilityIdentifier = "onboarding.2fa." + "forgotPinLink"

        let pinStack = UIStackView(arrangedSubviews: [
            pinTextField,
            UIView.spacer(withHeight: 10),
            validationWarningLabel,
            UIView.spacer(withHeight: 10),
            needHelpLink
        ])
        pinStack.axis = .vertical
        pinStack.alignment = .fill

        let pinStackRow = UIView()
        pinStackRow.addSubview(pinStack)
        pinStack.autoHCenterInSuperview()
        pinStack.autoPinHeightToSuperview()
        pinStack.autoSetDimension(.width, toSize: 227)
        pinStackRow.setContentHuggingVerticalHigh()

        pinTypeToggle.setTitleColor(Theme.accentBlueColor, for: .normal)
        pinTypeToggle.titleLabel?.font = .ows_dynamicTypeSubheadlineClamped
        pinTypeToggle.addTarget(self, action: #selector(togglePinType), for: .touchUpInside)
        pinTypeToggle.accessibilityIdentifier = "pinCreation.pinTypeToggle"

        nextButton.accessibilityIdentifier = "onboarding.2fa." + "nextButton"
        let primaryButtonView = OnboardingBaseViewController.horizontallyWrap(primaryButton: nextButton)

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()
        let compressableBottomMargin = UIView.vStretchingSpacer(minHeight: 16, maxHeight: primaryLayoutMargins.bottom)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 10),
            explanationLabel,
            topSpacer,
            pinStackRow,
            bottomSpacer,
            pinTypeToggle,
            UIView.spacer(withHeight: 10),
            primaryButtonView,
            compressableBottomMargin
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        primaryView.addSubview(stackView)

        // Because of the keyboard, vertical spacing can get pretty cramped,
        // so we have custom spacer logic.
        stackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)
        autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)

        // Ensure whitespace is balanced, so inputs are vertically centered.
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        updateValidationWarnings()
        updatePinType()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        shouldBottomViewReserveSpaceForKeyboard = false
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        _ = pinTextField.becomeFirstResponder()
    }

    // MARK: - Events

    @objc func needHelpLinkWasTapped() {
        Logger.info("")
        let title = NSLocalizedString("REGISTER_2FA_FORGOT_PIN_ALERT_TITLE",
                                      comment: "Alert title explaining what happens if you forget your 'two-factor auth pin'.")

        let message: String
        let emailSupportFilter: String
        var additionalActions = [ActionSheetAction]()
        if isUsingKBS {
            if hasPendingRestoration {
                message = NSLocalizedString("REGISTER_2FA_FORGOT_SVR_PIN_WITHOUT_REGLOCK_ALERT_MESSAGE",
                                            comment: "Alert body for a forgotten SVR (V2) PIN when the user doesn't have reglock")
                emailSupportFilter = "Signal PIN - iOS (V2 PIN without RegLock)"

                let createNewPinAction = ActionSheetAction(
                    title: NSLocalizedString("ONBOARDING_2FA_CREATE_NEW_PIN",
                                             comment: "Label for the 'create new pin' button when reglock is disabled during onboarding.")
                ) { [weak self] _ in
                    let actionSheet = ActionSheetController(
                        title: NSLocalizedString("ONBOARDING_2FA_SKIP_PIN_ENTRY_TITLE",
                                                 comment: "Title for the skip pin entry action sheet during onboarding."),
                        message: NSLocalizedString("ONBOARDING_2FA_SKIP_PIN_ENTRY_MESSAGE",
                                                   comment: "Explanation for the skip pin entry action sheet during onboarding.")
                    )
                    let skipAndCreateNew = ActionSheetAction(
                        title: NSLocalizedString("ONBOARDING_2FA_SKIP_AND_CREATE_NEW_PIN",
                                                 comment: "Label for the 'skip and create new pin' button when reglock is disabled during onboarding."),
                        style: .destructive
                    ) { [weak self] _ in
                        self?.showNextMilestone(wasSuccessful: false)
                    }
                    actionSheet.addAction(skipAndCreateNew)
                    actionSheet.addAction(OWSActionSheets.cancelAction)
                    self?.presentActionSheet(actionSheet)
                }
                additionalActions.append(createNewPinAction)
            } else {
                message = NSLocalizedString("REGISTER_2FA_FORGOT_SVR_PIN_ALERT_MESSAGE",
                                            comment: "Alert body for a forgotten SVR (V2) PIN")
                emailSupportFilter = "Signal PIN - iOS (V2 PIN)"
            }
        } else {
            message = NSLocalizedString("REGISTER_2FA_FORGOT_V1_PIN_ALERT_MESSAGE",
                                        comment: "Alert body for a forgotten V1 PIN")
            emailSupportFilter = "Signal PIN - iOS (V1 PIN)"
        }

        ContactSupportAlert.presentAlert(title: title, message: message, emailSupportFilter: emailSupportFilter, fromViewController: self, additionalActions: additionalActions)
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

        pinTextField.resignFirstResponder()

        let progressView = PinProgressView(
            loadingText: NSLocalizedString("REGISTER_2FA_PIN_PROGRESS",
                                           comment: "Indicates the work we are doing while verifying the user's pin")
        )
        view.addSubview(progressView)
        progressView.autoPinWidthToSuperview()
        progressView.autoVCenterInSuperview()

        progressView.startLoading {
            self.view.isUserInteractionEnabled = false
            self.nextButton.alpha = 0.5
            self.pinTypeToggle.alpha = 0.5
        }

        func animateProgressFail() {
            progressView.loadingComplete(success: false, animateAlongside: {
                self.nextButton.alpha = 1
                self.pinTypeToggle.alpha = 1
            }) {
                self.view.isUserInteractionEnabled = true
                progressView.removeFromSuperview()
            }
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
                animateProgressFail()
            case .invalidV2RegistrationLockPin(let remainingAttempts):
                self.attemptState = .invalid(remainingAttempts: remainingAttempts)
                animateProgressFail()
            case .exhaustedV2RegistrationLockAttempts:
                self.attemptState = .exhausted

                progressView.loadingComplete(success: false, animated: false) { [weak self] in
                    guard let self = self else { return }

                    self.nextButton.alpha = 1
                    self.pinTypeToggle.alpha = 1

                    self.view.isUserInteractionEnabled = true
                    progressView.removeFromSuperview()

                    self.showAttemptsExhausted()
                }
            case .success:
                self.attemptState = .valid

                // The completion handler always dismisses this view, so we don't want to animate anything.
                progressView.loadingComplete(success: true, animated: false) { [weak self] in
                    guard let self = self else { return }

                    self.nextButton.alpha = 1
                    self.pinTypeToggle.alpha = 1

                    self.view.isUserInteractionEnabled = true
                    progressView.removeFromSuperview()

                    // If we have success while pending restoration, show the next onboarding milestone.
                    if self.hasPendingRestoration { self.showNextMilestone(wasSuccessful: true) }
                }

            case .invalidVerificationCode:
                owsFailDebug("Invalid verification code in 2FA view.")
                animateProgressFail()
            }
        })
    }

    private func showAttemptsExhausted() {
        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        let vc = OnboardingPinAttemptsExhaustedViewController(onboardingController: onboardingController)
        navigationController.pushViewController(vc, animated: true)
    }

    private func showNextMilestone(wasSuccessful: Bool) {
        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        guard let pinToUse = self.pinTextField.text?.ows_stripped() else {
            return owsFailDebug("Missing 2FA pin")
        }

        databaseStorage.write { transaction in
            // Clear any pending restoration before moving on. At this point we've either
            // successfully restored the user's PIN or the user chose to re-create their PIN.
            KeyBackupService.clearPendingRestoration(transaction: transaction)

            // If we were successful, also mark the user as having a PIN
            // They're a returning user, so we can skip the welcome banner
            if wasSuccessful {
                OWS2FAManager.shared().markEnabled(pin: pinToUse, transaction: transaction)
                GetStartedBannerViewController.dismissAllCards(writeTx: transaction)
            }
        }

        onboardingController.showNextMilestone(navigationController: navigationController)
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
            guard let remaining = remainingAttempts, remaining <= 5 else {
                validationWarningLabel.text = NSLocalizedString("ONBOARDING_2FA_INVALID_PIN",
                                                                comment: "Label indicating that the 2fa pin is invalid in the 'onboarding 2fa' view.")
                break
            }

            // If there are less than the threshold attempts remaining, also show an alert with more detail.
            if remaining < attemptsAlertThreshold {
                let formatMessage: String
                if remaining == 1 {
                    formatMessage = hasPendingRestoration
                        ? NSLocalizedString("REGISTER_2FA_INVALID_PIN_ALERT_MESSAGE_SINGLE",
                                            comment: "Alert message explaining what happens if you get your pin wrong and have one attempt remaining 'two-factor auth pin' with reglock disabled.")
                        : NSLocalizedString("REGISTER_2FA_INVALID_PIN_ALERT_MESSAGE_REGLOCK_SINGLE",
                                            comment: "Alert message explaining what happens if you get your pin wrong and have one attempt remaining 'two-factor auth pin' with reglock enabled.")
                } else {
                    formatMessage = hasPendingRestoration
                        ? NSLocalizedString("REGISTER_2FA_INVALID_PIN_ALERT_MESSAGE_PLURAL_FORMAT",
                                            comment: "Alert message explaining what happens if you get your pin wrong and have multiple attempts remaining 'two-factor auth pin' with reglock disabled.")
                        : NSLocalizedString("REGISTER_2FA_INVALID_PIN_ALERT_MESSAGE_REGLOCK_PLURAL_FORMAT",
                                            comment: "Alert message explaining what happens if you get your pin wrong and have multiple attempts remaining 'two-factor auth pin' with reglock enabled.")
                }

                OWSActionSheets.showActionSheet(
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

    private func updatePinType() {
        AssertIsOnMainThread()

        pinTextField.text = nil
        attemptState = .unattempted

        pinTypeToggle.isHidden = !isUsingKBS

        switch pinType {
        case .numeric:
            pinTypeToggle.setTitle(NSLocalizedString("ONBOARDING_2FA_ENTER_ALPHANUMERIC",
                                                     comment: "Button asking if the user would like to enter an alphanumeric PIN"), for: .normal)
            pinTextField.keyboardType = .asciiCapableNumberPad
        case .alphanumeric:
            pinTypeToggle.setTitle(NSLocalizedString("ONBOARDING_2FA_ENTER_NUMERIC",
                                                     comment: "Button asking if the user would like to enter an numeric PIN"), for: .normal)
            pinTextField.keyboardType = .default
        }

        pinTextField.reloadInputViews()
    }

    @objc func togglePinType() {
        guard isUsingKBS else {
            return owsFailDebug("unexpectedly tried to toggle PIN type when not using KBS")
        }

        switch pinType {
        case .numeric:
            pinType = .alphanumeric
        case .alphanumeric:
            pinType = .numeric
        }
    }
}

// MARK: -

extension Onboarding2FAViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let hasPendingChanges: Bool
        if pinType == .numeric {
            ViewControllerUtils.ows2FAPINTextField(textField, shouldChangeCharactersIn: range, replacementString: string)
            hasPendingChanges = false
        } else {
            hasPendingChanges = true
        }

        // Reset the attempt state to clear errors, since the user is trying again
        attemptState = .unattempted

        return hasPendingChanges
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        tryToVerify()
        return false
    }
}
