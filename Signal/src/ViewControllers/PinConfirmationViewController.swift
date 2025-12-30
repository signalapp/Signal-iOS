//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class PinConfirmationViewController: OWSViewController {

    private let completionHandler: (Bool) -> Void
    private let titleText: String
    private let explanationText: String
    private let actionText: String

    private lazy var contentView = UIView()
    private var contentViewConstraints = [NSLayoutConstraint]()

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
        textField.accessibilityIdentifier = "pinConfirmation.pinTextField"
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
        label.accessibilityIdentifier = "pinConfirmation.validationWarningLabel"
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

    init(title: String, explanation: String, actionText: String, completionHandler: @escaping (Bool) -> Void) {
        // TODO[ViewContextPiping]
        self.context = ViewControllerContext.shared
        self.titleText = title
        self.explanationText = explanation
        self.actionText = actionText
        self.completionHandler = completionHandler
        super.init()
        modalPresentationStyle = .custom
        transitioningDelegate = self
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
        contentViewConstraints = [
            contentView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor, constant: -16),
        ]
        view.addConstraints(contentViewConstraints)

        view.addConstraints([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 32),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // UI Elements

        // Title
        let titleLabel = UILabel()
        titleLabel.textColor = .Signal.label
        titleLabel.font = UIFont.dynamicTypeHeadlineClamped.semibold()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        titleLabel.text = titleText

        // Explanation
        let explanationLabel = UILabel()
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.textColor = .Signal.secondaryLabel
        explanationLabel.font = .dynamicTypeSubheadlineClamped
        explanationLabel.accessibilityIdentifier = "pinConfirmation.explanationLabel"
        explanationLabel.text = explanationText

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
            configuration: .largePrimary(title: actionText),
            primaryAction: UIAction { [weak self] _ in
                self?.submitPressed()
            },
        )
        submitButton.accessibilityIdentifier = "pinConfirmation.submitButton"

        let cancelButton = UIButton(
            configuration: .mediumBorderless(title: CommonStrings.cancelButton),
            primaryAction: UIAction { [weak self] _ in
                self?.cancelPressed()
            },
        )
        cancelButton.accessibilityIdentifier = "pinConfirmation.cancelButton"

        let buttonContainer = UIView.container()
        buttonContainer.addSubview(submitButton)
        submitButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(cancelButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            submitButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            submitButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor, constant: 12),
            submitButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),

            cancelButton.topAnchor.constraint(equalTo: submitButton.bottomAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(greaterThanOrEqualTo: submitButton.leadingAnchor),
            cancelButton.centerXAnchor.constraint(equalTo: submitButton.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
        ])

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            pinTextFieldContainer,
            buttonContainer,
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12
        stackView.setCustomSpacing(24, after: explanationLabel)
        stackView.setCustomSpacing(24, after: pinTextFieldContainer)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        updateValidationWarnings()
    }

    // See comment in `viewDidLoad`.
    private func pinContentView() {
        view.removeConstraints(contentViewConstraints)
        view.addConstraints([
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

    private func cancelPressed() {
        Logger.info("")

        dismiss(animated: true) { self.completionHandler(false) }
    }

    private func submitPressed() {
        verifyAndDismissOnSuccess(pinTextField.text)
    }

    private func verifyAndDismissOnSuccess(_ pin: String?) {
        Logger.info("")

        // We only check > 0 here rather than > 3 because legacy pins may be less than 4 characters
        guard let pin = pin?.ows_stripped(), !pin.isEmpty else {
            validationState = .tooShort
            return
        }

        SSKEnvironment.shared.ows2FAManagerRef.verifyPin(pin) { success in
            if success {
                self.dismiss(animated: true) { self.completionHandler(true) }
            } else {
                self.validationState = .mismatch
            }
        }
    }

    private func updateValidationWarnings() {
        AssertIsOnMainThread()

        validationWarningLabel.isHidden = !validationState.isInvalid

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

private class PinConfirmationPresentationController: UIPresentationController {
    private let backdropView = UIView()

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        backdropView.backgroundColor = .Signal.backdrop
    }

    override func presentationTransitionWillBegin() {
        guard let containerView else { return }

        backdropView.alpha = 0
        backdropView.frame = containerView.bounds
        backdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(backdropView)

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView.alpha = 1
        })
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(
            alongsideTransition: { _ in
                self.backdropView.alpha = 0
            },
            completion: { _ in
                self.backdropView.removeFromSuperview()
            },
        )
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        guard let presentedView else { return }

        coordinator.animate(alongsideTransition: { _ in
            presentedView.frame = self.frameOfPresentedViewInContainerView
            presentedView.layoutIfNeeded()
        })
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
        let currentPinType = context.db.read { tx in
            context.svr.currentPinType(transaction: tx)
        }
        if currentPinType == .alphanumeric {
            hasPendingChanges = true
        } else {
            TextFieldFormatting.ows2FAPINTextField(textField, changeCharactersIn: range, replacementString: string)
            hasPendingChanges = false
        }

        validationState = .valid

        // Inform our caller that we took care of performing the change.
        return hasPendingChanges
    }
}
