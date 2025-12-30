//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class PinReminderViewController: OWSViewController {

    enum PinReminderResult {
        case canceled(didGuessWrong: Bool)
        case changedPin
        case succeeded
    }

    private let completionHandler: ((PinReminderResult) -> Void)?

    private let contentView = UIView()
    private var contentViewBottomEdgeConstraint: NSLayoutConstraint?

    private lazy var backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = .Signal.groupedBackground
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            view.cornerConfiguration = .corners(
                topLeftRadius: .containerConcentric(minimum: 40),
                topRightRadius: .containerConcentric(minimum: 40),
                bottomLeftRadius: .none,
                bottomRightRadius: .none,
            )
        }
#endif
        return view
    }()

    private lazy var pinTextField: UITextField = {
        let textField = UITextField()
        textField.textColor = .Signal.label
        if #available(iOS 26, *) {
            textField.tintColor = .Signal.label
        }
        textField.font = .systemFont(ofSize: 22)
        textField.textAlignment = .center
        textField.isSecureTextEntry = true
        textField.backgroundColor = .Signal.secondaryGroupedBackground
        textField.defaultTextAttributes.updateValue(5, forKey: .kern)
        textField.accessibilityIdentifier = "pinReminder.pinTextField"
        textField.delegate = self
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            textField.cornerConfiguration = .capsule()
        } else {
            textField.layer.cornerRadius = 10
        }
#else
        textField.layer.cornerRadius = 10
#endif
        let currentPinType = context.db.read { tx in
            context.svr.currentPinType(transaction: tx)
        }
        textField.keyboardType = currentPinType == .alphanumeric ? .default : .asciiCapableNumberPad
        return textField
    }()

    private lazy var validationWarningLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.red
        label.textAlignment = .center
        label.font = .dynamicTypeFootnoteClamped
        label.text = " "
        label.accessibilityIdentifier = "pinReminder.validationWarningLabel"
        return label
    }()

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
        self.context = ViewControllerContext.shared
        self.completionHandler = completionHandler
        super.init()
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        // Final layout frame of the keyboardLayoutGuide` when the VC is dismissed, is `CGRect.zero`.
        // That causes the entire content to jump above the top edge of the screen and then animate all the way down.
        // The workaround is in `viewWillDisappear` to:
        //  • remove constraint to `keyboardLayoutGuide`.
        //  • constrain bottom edge of the `contentView` to bottom edge of view controller's view using current offset.
        // All this works as long as view controller is presented modally
        // and `viewWillDisappear` is guaranteed to be only called once.
        contentViewBottomEdgeConstraint = contentView.bottomAnchor.constraint(
            equalTo: keyboardLayoutGuide.topAnchor,
            constant: -16,
        )

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentViewBottomEdgeConstraint!,
        ])

        // UI Elements

        // Title

        let titleLabel = UILabel()
        titleLabel.textColor = .Signal.label
        titleLabel.font = UIFont.dynamicTypeHeadlineClamped.semibold()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        titleLabel.text = OWSLocalizedString("PIN_REMINDER_TITLE", comment: "The title for the 'pin reminder' dialog.")

        // Explanation

        let explanationLabel = UILabel()
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.textColor = .Signal.secondaryLabel
        explanationLabel.font = .dynamicTypeSubheadlineClamped
        explanationLabel.accessibilityIdentifier = "pinReminder.explanationLabel"
        explanationLabel.text = OWSLocalizedString("PIN_REMINDER_EXPLANATION", comment: "The explanation for the 'pin reminder' dialog.")

        // Pin text field

        // Pin text field and warning text
        let pinStack = UIStackView(arrangedSubviews: [pinTextField, validationWarningLabel])
        pinStack.axis = .vertical
        pinStack.alignment = .fill
        pinStack.spacing = 16

        let pinTextFieldContainer = UIView()
        pinTextFieldContainer.addSubview(pinStack)
        pinStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pinTextField.heightAnchor.constraint(equalToConstant: 50),

            pinStack.topAnchor.constraint(equalTo: pinTextFieldContainer.topAnchor),
            pinStack.leadingAnchor.constraint(equalTo: pinTextFieldContainer.leadingAnchor),
            pinStack.centerXAnchor.constraint(equalTo: pinTextFieldContainer.centerXAnchor),
            pinStack.bottomAnchor.constraint(equalTo: pinTextFieldContainer.bottomAnchor),
        ])

        // Buttons
        let submitButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "BUTTON_SUBMIT",
                comment: "Label for the 'submit' button.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.submitPressed()
            },
        )
        submitButton.accessibilityIdentifier = "pinReminder.submitButton"

        let forgotPINButton = UIButton(
            configuration: .mediumBorderless(title: OWSLocalizedString(
                "PIN_REMINDER_FORGOT_PIN",
                comment: "Text asking if the user forgot their pin for the 'pin reminder' dialog.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.forgotPressed()
            },
        )
        forgotPINButton.accessibilityIdentifier = "pinReminder.forgotButton"

        let buttonContainer = UIView.container()
        buttonContainer.addSubview(submitButton)
        submitButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(forgotPINButton)
        forgotPINButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            forgotPINButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            forgotPINButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            forgotPINButton.leadingAnchor.constraint(greaterThanOrEqualTo: submitButton.leadingAnchor),

            submitButton.topAnchor.constraint(equalTo: forgotPINButton.bottomAnchor, constant: 12),
            submitButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor, constant: 12),
            submitButton.centerXAnchor.constraint(equalTo: forgotPINButton.centerXAnchor),
            submitButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
        ])

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            pinTextFieldContainer,
            .vStretchingSpacer(minHeight: 8),
            buttonContainer,
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.setCustomSpacing(35, after: titleLabel)
        stackView.setCustomSpacing(24, after: explanationLabel)
        stackView.preservesSuperviewLayoutMargins = true
        stackView.isLayoutMarginsRelativeArrangement = true
        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // top edge of the stack view will be defined later in relation to ( X ) button.
            stackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // Close button at the top.
        let buttonConfiguration: UIButton.Configuration
        var buttonImageColor = UIColor(dynamicProvider: { traits in
            if traits.userInterfaceStyle == .light {
                return .ows_gray75
            } else {
                return .ows_gray15
            }
        })
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            buttonConfiguration = .prominentClearGlass()
            buttonImageColor = .Signal.label
        } else {
            buttonConfiguration = .plain()
        }
#else
        buttonConfiguration = .plain()
#endif
        let dismissButton = UIButton(
            configuration: buttonConfiguration,
            primaryAction: UIAction { [weak self] _ in
                self?.dismissPressed()
            },
        )
        dismissButton.configuration?.image = Theme.iconImage(.buttonX)
        dismissButton.configuration?.imageColorTransformer = .init { _ in buttonImageColor }
        contentView.addSubview(dismissButton)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        // 16 or 20 depending on device
        // We want to aling trailing edge of the (X) button with the trailing edge or the text field
        // and have identical margin on the top and on the side.
        let dismissButtonMargin = OWSTableViewController2.cellHInnerMargin
        NSLayoutConstraint.activate([
            dismissButton.widthAnchor.constraint(equalToConstant: 44),
            dismissButton.heightAnchor.constraint(equalToConstant: 44),
            dismissButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: dismissButtonMargin),
            dismissButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -dismissButtonMargin),
            dismissButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])

        // Every time the text changes, try and verify the pin
        pinTextField.addTarget(self, action: #selector(verifySilently), for: .editingChanged)

        updateValidationWarnings()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pinTextField.becomeFirstResponder()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // For now, the design only allows for portrait layout on non-iPads
        if !UIDevice.current.isIPad, view.window?.windowScene?.interfaceOrientation != .portrait {
            UIDevice.current.ows_setOrientation(.portrait)
        }
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pinContentView()
        pinTextField.resignFirstResponder()
    }

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    // See comment in `viewDidLoad`.
    private func pinContentView() {
        contentViewBottomEdgeConstraint?.isActive = false
        NSLayoutConstraint.activate([
            contentView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: contentView.frame.maxY - view.bounds.maxY,
            ),
        ])
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if #unavailable(iOS 26) {
            updateBackgroundCornerRadius()
        }
    }

    @available(iOS, deprecated: 26.0)
    private func updateBackgroundCornerRadius() {
        let cornerRadius: CGFloat = 16
        let path = UIBezierPath(
            roundedRect: backgroundView.bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(square: cornerRadius),
        )
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        backgroundView.layer.mask = shapeLayer
    }

    // MARK: - Events

    private func forgotPressed() {
        Logger.info("")

        let viewController = PinSetupViewController(
            mode: .creating,
            showCancelButton: true,
            completionHandler: { [weak self] _, _ in self?.completionHandler?(.changedPin) },
        )
        present(OWSNavigationController(rootViewController: viewController), animated: true)
    }

    private func dismissPressed() {
        Logger.info("")

        // If the user tried and guessed wrong, we'll dismiss the megaphone and
        // decrease their reminder interval so the next reminder comes sooner.
        // If they didn't try and enter a PIN, we do nothing and leave the megaphone.
        if hasGuessedWrong { SSKEnvironment.shared.ows2FAManagerRef.reminderCompleted(incorrectAttempts: true) }

        self.completionHandler?(.canceled(didGuessWrong: hasGuessedWrong))
    }

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
            if success {
                SSKEnvironment.shared.ows2FAManagerRef.reminderCompleted(incorrectAttempts: self.hasGuessedWrong)
                self.completionHandler?(.succeeded)
            } else if !silent {
                self.validationState = .mismatch
            }
        }
    }

    private func updateValidationWarnings() {
        AssertIsOnMainThread()

        validationWarningLabel.alpha = validationState.isInvalid ? 1 : 0

        switch validationState {
        case .tooShort:
            validationWarningLabel.text = OWSLocalizedString(
                "PIN_REMINDER_TOO_SHORT_ERROR",
                comment: "Label indicating that the attempted PIN is too short",
            )
        case .mismatch:
            validationWarningLabel.text = OWSLocalizedString(
                "PIN_REMINDER_MISMATCH_ERROR",
                comment: "Label indicating that the attempted PIN does not match the user's PIN",
            )
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
        backdropView.backgroundColor = .Signal.backdrop
    }

    override func presentationTransitionWillBegin() {
        guard let containerView else { return }

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
        guard let presentedView else { return }
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
