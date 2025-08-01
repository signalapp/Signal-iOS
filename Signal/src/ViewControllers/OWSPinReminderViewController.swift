//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class PinReminderViewController: OWSViewController {

    enum PinReminderResult {
        case canceled(didGuessWrong: Bool)
        case changedOrRemovedPin
        case succeeded
    }

    private let completionHandler: ((PinReminderResult) -> Void)?

    private let containerView = UIView()
    private let pinTextField = UITextField()

    private lazy var pinStrokeNormal = pinTextField.addBottomStroke()
    private lazy var pinStrokeError = pinTextField.addBottomStroke(color: .ows_accentRed, strokeWidth: 2)
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

    private let context: ViewControllerContext

    init(completionHandler: ((PinReminderResult) -> Void)? = nil) {
        // TODO[ViewContextPiping]
        self.context = ViewControllerContext.shared
        self.completionHandler = completionHandler
        super.init()
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pinTextField.becomeFirstResponder()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // For now, the design only allows for portrait layout on non-iPads
        if !UIDevice.current.isIPad && view.window?.windowScene?.interfaceOrientation != .portrait {
            UIDevice.current.ows_setOrientation(.portrait)
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pinTextField.resignFirstResponder()
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    override public func loadView() {
        view = UIView()
        view.backgroundColor = .clear

        containerView.backgroundColor = Theme.backgroundColor

        view.addSubview(containerView)
        containerView.autoPinWidthToSuperview()
        containerView.autoPin(toTopLayoutGuideOf: self, withInset: 0, relation: .greaterThanOrEqual)
        containerView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        // We want the background to extend to the bottom of the screen
        // behind the safe area, so we add that inset to our bottom inset
        // instead of pinning this view to the safe area
        let safeAreaBackdrop = UIView()
        safeAreaBackdrop.backgroundColor = Theme.backgroundColor
        view.addSubview(safeAreaBackdrop)
        safeAreaBackdrop.autoPinEdge(.top, to: .bottom, of: containerView)
        safeAreaBackdrop.autoPinWidthToSuperview()
        // We don't know the safe area insets, so just guess a big number that will extend off screen
        safeAreaBackdrop.autoSetDimension(.height, toSize: 150)

        // Title

        let titleLabel = UILabel()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = UIFont.dynamicTypeTitle3Clamped.semibold()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        titleLabel.text = OWSLocalizedString("PIN_REMINDER_TITLE", comment: "The title for the 'pin reminder' dialog.")

        // Explanation

        let explanationLabel = UILabel()
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.font = .dynamicTypeSubheadlineClamped
        explanationLabel.accessibilityIdentifier = "pinReminder.explanationLabel"
        explanationLabel.text = OWSLocalizedString("PIN_REMINDER_EXPLANATION", comment: "The explanation for the 'pin reminder' dialog.")

        // Pin text field

        pinTextField.delegate = self
        let currentPinType = context.db.read { tx in
            context.svr.currentPinType(transaction: tx)
        }
        pinTextField.keyboardType = currentPinType == .alphanumeric ? .default : .asciiCapableNumberPad
        pinTextField.textColor = Theme.primaryTextColor
        pinTextField.font = .dynamicTypeBodyClamped
        pinTextField.textAlignment = .center
        pinTextField.isSecureTextEntry = true
        pinTextField.defaultTextAttributes.updateValue(5, forKey: .kern)
        pinTextField.keyboardAppearance = Theme.keyboardAppearance
        pinTextField.setContentHuggingHorizontalLow()
        pinTextField.setCompressionResistanceHorizontalLow()
        pinTextField.autoSetDimension(.height, toSize: 40)
        pinTextField.accessibilityIdentifier = "pinReminder.pinTextField"

        // Every time the text changes, try and verify the pin
        pinTextField.addTarget(self, action: #selector(verifySilently), for: .editingChanged)

        validationWarningLabel.textColor = .ows_accentRed
        validationWarningLabel.font = UIFont.dynamicTypeCaption1Clamped
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

        let font = UIFont.dynamicTypeBodyClamped.semibold()
        let buttonHeight = OWSFlatButton.heightForFont(font)
        let submitButton = OWSFlatButton.button(
            title: OWSLocalizedString("BUTTON_SUBMIT",
                                     comment: "Label for the 'submit' button."),
            font: font,
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: self,
            selector: #selector(submitPressed)
        )
        submitButton.autoSetDimension(.height, toSize: buttonHeight)
        submitButton.accessibilityIdentifier = "pinReminder.submitButton"

        // Secondary button
        let forgotButton = UIButton()
        forgotButton.setTitle(OWSLocalizedString("PIN_REMINDER_FORGOT_PIN", comment: "Text asking if the user forgot their pin for the 'pin reminder' dialog."), for: .normal)
        forgotButton.setTitleColor(Theme.accentBlueColor, for: .normal)
        forgotButton.titleLabel?.font = .dynamicTypeSubheadlineClamped
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
        stackView.distribution = .equalCentering
        stackView.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 16, right: 32)
        stackView.isLayoutMarginsRelativeArrangement = true

        let scrollView = UIScrollView()
        scrollView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        // Make sure this is a real width pin; a scroll view's edge anchors are different from its width.
        stackView.autoPinWidth(toWidthOf: scrollView)

        // The scroll view should never be *smaller* than the stack view...
        scrollView.autoMatch(.height, to: .height, of: stackView, withOffset: 0, relation: .lessThanOrEqual)
        // ...and if the stack view is smaller than the screen, the scroll view should shrink to match.
        NSLayoutConstraint.autoSetPriority(.defaultLow - 2) {
            scrollView.autoPinHeight(toHeightOf: stackView)
        }
        // But the stack view shouldn't *stretch* to fill the scroll view; it should shrink as much as possible after
        // all other constraints have been fulfilled.
        NSLayoutConstraint.autoSetPriority(.defaultLow - 1) {
            stackView.autoSetDimension(.height, toSize: 0)
        }

        containerView.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()

        // Ensure whitespace is balanced, so inputs are vertically centered.
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
        topSpacer.autoSetDimension(.height, toSize: 20, relation: .greaterThanOrEqual)

        let dismissButton = UIButton()
        dismissButton.setTemplateImage(Theme.iconImage(.buttonX), tintColor: Theme.primaryIconColor)
        dismissButton.addTarget(self, action: #selector(dismissPressed), for: .touchUpInside)
        containerView.addSubview(dismissButton)
        dismissButton.autoSetDimensions(to: CGSize(square: 44))
        dismissButton.autoPinEdge(toSuperviewEdge: .leading, withInset: 8)
        dismissButton.autoPinEdge(toSuperviewEdge: .top, withInset: 8)

        updateValidationWarnings()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let cornerRadius: CGFloat = 16
        let path = UIBezierPath(
            roundedRect: containerView.bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(square: cornerRadius)
        )
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        containerView.layer.mask = shapeLayer
    }

    // MARK: - Events

    @objc
    private func forgotPressed() {
        Logger.info("")

        let viewController = PinSetupViewController(
            mode: .creating,
            hideNavigationBar: false,
            showCancelButton: true,
            showDisablePinButton: true,
            completionHandler: { [weak self] _, _ in self?.completionHandler?(.changedOrRemovedPin) }
        )
        present(OWSNavigationController(rootViewController: viewController), animated: true)
    }

    @objc
    private func dismissPressed() {
        Logger.info("")

        // If the user tried and guessed wrong, we'll dismiss the megaphone and
        // decrease their reminder interval so the next reminder comes sooner.
        // If they didn't try and enter a PIN, we do nothing and leave the megaphone.
        if hasGuessedWrong { SSKEnvironment.shared.ows2FAManagerRef.reminderCompleted(incorrectAttempts: true) }

        self.completionHandler?(.canceled(didGuessWrong: hasGuessedWrong))
    }

    @objc
    private func submitPressed() {
        verifyAndDismissOnSuccess(pinTextField.text)
    }

    @objc
    private func verifySilently() {
        verifyAndDismissOnSuccess(pinTextField.text, silent: true)
    }

    private func verifyAndDismissOnSuccess(_ pin: String?, silent: Bool = false) {
        Logger.info("")

        // We only check > 0 here rather than > 3 because legacy pins may be less than 4 characters
        guard let pin = pin?.ows_stripped(), !pin.isEmpty else {
            if !silent { validationState = .tooShort }
            return
        }

        SSKEnvironment.shared.ows2FAManagerRef.verifyPin(pin) { success in
            guard success else {
                guard SSKEnvironment.shared.ows2FAManagerRef.needsLegacyPinMigration, pin.count > kLegacyTruncated2FAv1PinLength else {
                    if !silent { self.validationState = .mismatch }
                    return
                }
                // We have a legacy pin that may have been truncated to 16 characters.
                let truncatedPinCode = String(pin.prefix(Int(kLegacyTruncated2FAv1PinLength)))
                self.verifyAndDismissOnSuccess(truncatedPinCode, silent: silent)
                return
            }

            SSKEnvironment.shared.ows2FAManagerRef.reminderCompleted(incorrectAttempts: self.hasGuessedWrong)
            self.completionHandler?(.succeeded)
        }
    }

    private func updateValidationWarnings() {
        AssertIsOnMainThread()

        pinStrokeNormal.isHidden = validationState.isInvalid
        pinStrokeError.isHidden = !validationState.isInvalid
        validationWarningLabel.isHidden = !validationState.isInvalid

        switch validationState {
        case .tooShort:
            validationWarningLabel.text = OWSLocalizedString("PIN_REMINDER_TOO_SHORT_ERROR",
                                                            comment: "Label indicating that the attempted PIN is too short")
        case .mismatch:
            validationWarningLabel.text = OWSLocalizedString("PIN_REMINDER_MISMATCH_ERROR",
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

        backdropView.alpha = 0
        containerView.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()
        containerView.layoutIfNeeded()

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

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard let presentedView = presentedView else { return }
        coordinator.animate(alongsideTransition: { _ in
            presentedView.frame = self.frameOfPresentedViewInContainerView
            presentedView.layoutIfNeeded()
        }, completion: nil)
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
        let hasPendingChanges: Bool
        let currentPinType = context.db.read { tx in
            context.svr.currentPinType(transaction: tx)
        }
        if currentPinType == .alphanumeric {
            hasPendingChanges = true
        } else {
            TextFieldFormatting.ows2FAPINTextField(textField, changeCharactersIn: range, replacementString: string)
            hasPendingChanges = false

            // Every time the text changes, try and verify the pin
            verifySilently()
        }

        validationState = .valid

        // Inform our caller that we took care of performing the change.
        return hasPendingChanges
    }
}
