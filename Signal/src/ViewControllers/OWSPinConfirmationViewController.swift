//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

@objc(OWSPinConfirmationViewController)
public class PinConfirmationViewController: OWSViewController {

    private let completionHandler: ((Bool) -> Void)
    private let titleText: String
    private let explanationText: String
    private let actionText: String

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

    @objc
    init(title: String, explanation: String, actionText: String, completionHandler: @escaping (Bool) -> Void) {
        self.titleText = title
        self.explanationText = explanation
        self.actionText = actionText
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
        if !UIDevice.current.isIPad && CurrentAppContext().interfaceOrientation != .portrait {
            UIDevice.current.ows_setOrientation(.portrait)
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pinTextField.resignFirstResponder()
    }

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
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
        autoPinView(toBottomOfViewControllerOrKeyboard: containerView, avoidNotch: true)

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
        titleLabel.font = UIFont.ows_dynamicTypeTitle3Clamped.ows_semibold
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        titleLabel.text = titleText

        // Explanation

        let explanationLabel = UILabel()
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.font = .ows_dynamicTypeSubheadlineClamped
        explanationLabel.accessibilityIdentifier = "pinConfirmation.explanationLabel"
        explanationLabel.text = explanationText

        // Pin text field

        pinTextField.delegate = self
        pinTextField.keyboardType = KeyBackupService.currentPinType == .alphanumeric ? .default : .asciiCapableNumberPad
        pinTextField.textColor = Theme.primaryTextColor
        pinTextField.font = .ows_dynamicTypeBodyClamped
        pinTextField.textAlignment = .center
        pinTextField.isSecureTextEntry = true
        pinTextField.defaultTextAttributes.updateValue(5, forKey: .kern)
        pinTextField.keyboardAppearance = Theme.keyboardAppearance
        pinTextField.setContentHuggingHorizontalLow()
        pinTextField.setCompressionResistanceHorizontalLow()
        pinTextField.autoSetDimension(.height, toSize: 40)
        pinTextField.accessibilityIdentifier = "pinConfirmation.pinTextField"

        validationWarningLabel.textColor = .ows_accentRed
        validationWarningLabel.textAlignment = .center
        validationWarningLabel.font = UIFont.ows_dynamicTypeCaption1Clamped
        validationWarningLabel.accessibilityIdentifier = "pinConfirmation.validationWarningLabel"

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

        let font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        let buttonHeight = OWSFlatButton.heightForFont(font)
        let submitButton = OWSFlatButton.button(
            title: actionText,
            font: font,
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: self,
            selector: #selector(submitPressed)
        )
        submitButton.autoSetDimension(.height, toSize: buttonHeight)
        submitButton.accessibilityIdentifier = "pinConfirmation.submitButton"

        // Cancel button
        let cancelButton = UIButton()
        cancelButton.setTitle(CommonStrings.cancelButton, for: .normal)
        cancelButton.setTitleColor(Theme.accentBlueColor, for: .normal)
        cancelButton.titleLabel?.font = .ows_dynamicTypeSubheadlineClamped
        cancelButton.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
        cancelButton.accessibilityIdentifier = "pinConfirmation.cancelButton"

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 10),
            explanationLabel,
            topSpacer,
            pinStackRow,
            bottomSpacer,
            submitButton,
            UIView.spacer(withHeight: 10),
            cancelButton
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
            cornerRadii: CGSize(square: cornerRadius)
        )
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        containerView.layer.mask = shapeLayer
    }

    // MARK: - Events

    @objc
    func cancelPressed() {
        Logger.info("")

        dismiss(animated: true) { self.completionHandler(false) }
    }

    @objc
    func submitPressed() {
        verifyAndDismissOnSuccess(pinTextField.text)
    }

    private func verifyAndDismissOnSuccess(_ pin: String?) {
        Logger.info("")

        // We only check > 0 here rather than > 3 because legacy pins may be less than 4 characters
        guard let pin = pin?.ows_stripped(), !pin.isEmpty else {
            validationState = .tooShort
            return
        }

        OWS2FAManager.shared.verifyPin(pin) { success in
            guard success else {
                guard OWS2FAManager.shared.needsLegacyPinMigration(), pin.count > kLegacyTruncated2FAv1PinLength else {
                    self.validationState = .mismatch
                    return
                }
                // We have a legacy pin that may have been truncated to 16 characters.
                let truncatedPinCode = pin.substring(to: Int(kLegacyTruncated2FAv1PinLength))
                self.verifyAndDismissOnSuccess(truncatedPinCode)
                return
            }

            self.dismiss(animated: true) { self.completionHandler(true) }
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

private class PinConfirmationPresentationController: UIPresentationController {
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

extension PinConfirmationViewController: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return PinConfirmationPresentationController(presentedViewController: presented, presenting: presenting)
    }
}

// MARK: -

extension PinConfirmationViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let hasPendingChanges: Bool
        if KeyBackupService.currentPinType == .alphanumeric {
            hasPendingChanges = true
        } else {
            ViewControllerUtils.ows2FAPINTextField(textField, shouldChangeCharactersIn: range, replacementString: string)
            hasPendingChanges = false
        }

        validationState = .valid

        // Inform our caller that we took care of performing the change.
        return hasPendingChanges
    }
}
