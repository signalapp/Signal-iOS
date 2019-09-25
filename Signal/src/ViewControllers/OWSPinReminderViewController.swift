//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc(OWSPinReminderViewController)
public class PinReminderViewController: OWSViewController {

    private let recreatePinURL = "signal-pin://recreate"

    private let containerView = UIView()
    private let pinTextField = UITextField()

    private lazy var pinStrokeNormal = pinTextField.addBottomStroke()
    private lazy var pinStrokeError = pinTextField.addBottomStroke(color: .ows_destructiveRed, strokeWidth: 2)
    private let validationWarningLabel = UILabel()

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

            if validationState.isInvalid {
                hasGuessedWrong = true
            }
        }
    }
    private var hasGuessedWrong = false

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pinTextField.becomeFirstResponder()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pinTextField.resignFirstResponder()
    }

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
    }

    override public func loadView() {
        view = UIView()
        view.backgroundColor = .clear

        containerView.backgroundColor = Theme.backgroundColor

        view.addSubview(containerView)
        containerView.autoPinWidthToSuperview()
        autoPinView(toBottomOfViewControllerOrKeyboard: containerView, avoidNotch: true)

        // Title

        let titleLabel = UILabel()
        titleLabel.textColor = Theme.primaryColor
        titleLabel.font = UIFont.ows_dynamicTypeTitle3Clamped.ows_semiBold()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        titleLabel.text = NSLocalizedString("PIN_REMINDER_TITLE", comment: "The title for the 'pin reminder' dialog.")

        // Explanation

        let explanationLabel = UILabel()
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.textColor = Theme.secondaryColor
        explanationLabel.font = .ows_dynamicTypeSubheadlineClamped
        explanationLabel.accessibilityIdentifier = "pinReminder.explanationLabel"
        explanationLabel.text = NSLocalizedString("PIN_REMINDER_EXPLANATION", comment: "The explanation for the 'pin reminder' dialog.")

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
        pinTextField.accessibilityIdentifier = "pinReminder.pinTextField"

        validationWarningLabel.textColor = .ows_destructiveRed
        validationWarningLabel.font = UIFont.ows_dynamicTypeCaption1Clamped
        validationWarningLabel.accessibilityIdentifier = "pinReminder.validationWarningLabel"

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
        let submitButton = OWSFlatButton.button(
            title: NSLocalizedString("BUTTON_SUBMIT",
                                     comment: "Label for the 'submit' button."),
            font: font,
            titleColor: .white,
            backgroundColor: .ows_materialBlue,
            target: self,
            selector: #selector(submitPressed)
        )
        submitButton.autoSetDimension(.height, toSize: buttonHeight)
        submitButton.accessibilityIdentifier = "pinReminder.submitButton"

        // Secondary button
        let forgotButton = UIButton()
        forgotButton.setTitle(NSLocalizedString("PIN_REMINDER_FORGOT_PIN", comment: "Text asking if the user forgot their pin for the 'pin reminder' dialog."), for: .normal)
        forgotButton.setTitleColor(.ows_materialBlue, for: .normal)
        forgotButton.titleLabel?.font = .ows_dynamicTypeSubheadlineClamped
        forgotButton.addTarget(self, action: #selector(forgotPressed), for: .touchUpInside)
        forgotButton.accessibilityIdentifier = "pinReminder.forgotButton"

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            topSpacer,
            pinStackRow,
            UIView.spacer(withHeight: 10),
            explanationLabel,
            bottomSpacer,
            submitButton,
            UIView.spacer(withHeight: 10),
            forgotButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 16, right: 32)
        stackView.isLayoutMarginsRelativeArrangement = true
        containerView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()

        // Ensure whitespace is balanced, so inputs are vertically centered.
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
        topSpacer.autoSetDimension(.height, toSize: 20, relation: .greaterThanOrEqual)

        updateValidationWarnings()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let cornerRadius: CGFloat = 16
        let path = UIBezierPath(
            roundedRect: containerView.bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
        )
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        containerView.layer.mask = shapeLayer
    }

    // MARK: - Events

    @objc func forgotPressed() {
        Logger.info("")

        let vc = PinSetupViewController(mode: .recreating) { [weak self] in
            self?.presentingViewController?.dismiss(animated: true, completion: nil)
        }
        present(OWSNavigationController(rootViewController: vc), animated: true, completion: nil)
    }

    @objc func submitPressed() {
        verifyAndDismissOnSuccess(pinTextField.text)
    }

    private func verifySilently() {
        verifyAndDismissOnSuccess(pinTextField.text, silent: true)
    }

    private func verifyAndDismissOnSuccess(_ pin: String?, silent: Bool = false) {
        Logger.info("")

        // We only check > 0 here rather than > 3 because legacy pins may be less than 4 characters
        guard let pin = pin?.ows_stripped(), pin.count > 0 else {
            if !silent { validationState = .tooShort }
            return
        }

        OWS2FAManager.shared().verifyPin(pin) { success in
            guard success else {
                guard OWS2FAManager.shared().needsLegacyPinMigration(), pin.count > kLegacyTruncated2FAv1PinLength else {
                    if !silent { self.validationState = .mismatch }
                    return
                }
                // We have a legacy pin that may have been truncated to 16 characters.
                let truncatedPinCode = pin.substring(to: Int(kLegacyTruncated2FAv1PinLength))
                self.verifyAndDismissOnSuccess(truncatedPinCode, silent: silent)
                return
            }

            self.dismissAndUpdateRepetitionInterval()
        }
    }

    private func dismissAndUpdateRepetitionInterval() {
        OWS2FAManager.shared().updateRepetitionInterval(withWasSuccessful: !hasGuessedWrong)

        // Migrate to 2FA v2 if they've proved they know their pin
        if let pinCode = OWS2FAManager.shared().pinCode, FeatureFlags.registrationLockV2, OWS2FAManager.shared().mode == .V1 {
            // enabling 2fa v2 automatically disables v1 on the server
            OWS2FAManager.shared().enable2FAPromise(with: pinCode)
                .ensure {
                    self.dismiss(animated: true)
                }.catch { error in
                    // We don't need to bubble this up to the user, since they
                    // don't know / care that something is changing in this moment.
                    // We can try and migrate them again during their next reminder.
                    owsFailDebug("Unexpected error \(error) while migrating to reg lock v2")
                }.retainUntilComplete()
        } else {
            dismiss(animated: true)
        }
    }

    private func updateValidationWarnings() {
        AssertIsOnMainThread()

        pinStrokeNormal.isHidden = validationState.isInvalid
        pinStrokeError.isHidden = !validationState.isInvalid
        validationWarningLabel.isHidden = !validationState.isInvalid

        switch validationState {
        case .tooShort:
            validationWarningLabel.text = NSLocalizedString("PIN_REMINDER_TOO_SHORT_ERROR",
                                                            comment: "Label indicating that the attempted PIN is too short")
        case .mismatch:
            validationWarningLabel.text = NSLocalizedString("PIN_REMINDER_MISMATCH_ERROR",
                                                            comment: "Label indicating that the attempted PIN does not match the user's PIN")
        default:
            break
        }
    }
}

// MARK: -

private class PinReminderPresentationController: UIPresentationController {
    let backdropView = UIView()

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)

        let alpha: CGFloat = Theme.isDarkThemeEnabled ? 0.7 : 0.6
        backdropView.backgroundColor = UIColor.black.withAlphaComponent(alpha)
    }

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView else { return }
        backdropView.frame = containerView.frame
        backdropView.alpha = 0
        containerView.insertSubview(backdropView, at: 0)

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView.alpha = 1
        }, completion: nil)
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView.alpha = 0
        }, completion: { _ in
            self.backdropView.removeFromSuperview()
        })
    }
}

extension PinReminderViewController: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return PinReminderPresentationController(presentedViewController: presented, presenting: presenting)
    }
}

// MARK: -

extension PinReminderViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        ViewControllerUtils.ows2FAPINTextField(textField, shouldChangeCharactersIn: range, replacementString: string)

        validationState = .valid

        // Every time the text changes, try and verify the pin
        verifySilently()

        // Inform our caller that we took care of performing the change.
        return false
    }
}
