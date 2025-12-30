//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
public import SignalUI

public class PinSetupViewController: OWSViewController, OWSNavigationChildController {

    private lazy var explanationLabel: LinkingTextView = {
        let explanationLabel = LinkingTextView()
        let explanationText: String
        let addLearnMoreLink: Bool
        switch mode {
        case .creating:
            explanationText = OWSLocalizedString(
                "PIN_CREATION_EXPLANATION",
                comment: "The explanation in the 'pin creation' view.",
            )
            addLearnMoreLink = true
        case .changing:
            explanationText = OWSLocalizedString(
                "PIN_CREATION_RECREATION_EXPLANATION",
                comment: "The re-creation explanation in the 'pin creation' view.",
            )
            addLearnMoreLink = true
        case .confirming:
            explanationText = OWSLocalizedString(
                "PIN_CREATION_CONFIRMATION_EXPLANATION",
                comment: "The explanation of confirmation in the 'pin creation' view.",
            )
            addLearnMoreLink = false
        }

        let font = UIFont.dynamicTypeSubheadlineClamped
        let attributedString = NSMutableAttributedString(
            string: explanationText,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.Signal.secondaryLabel,
            ],
        )

        if addLearnMoreLink {
            let linkFont: UIFont
            let linkColor: UIColor
            if #available(iOS 26, *) {
                linkFont = font.semibold()
                linkColor = .Signal.label
            } else {
                linkFont = font
                linkColor = UIColor.Signal.link
            }
            explanationLabel.isUserInteractionEnabled = true
            attributedString.append("  ")
            attributedString.append(
                CommonStrings.learnMore,
                attributes: [
                    .link: URL.Support.pin,
                    .font: linkFont,
                ],
            )

            explanationLabel.tintColor = linkColor
        }
        explanationLabel.attributedText = attributedString
        explanationLabel.textAlignment = .center
        explanationLabel.accessibilityIdentifier = "pinCreation.explanationLabel"
        return explanationLabel
    }()

    private lazy var pinTextField: UITextField = {
        let textField = UITextField()
        textField.textAlignment = .center
        textField.textColor = .Signal.label
        if #available(iOS 26, *) {
            textField.tintColor = .Signal.label
        }
        textField.backgroundColor = .Signal.secondaryGroupedBackground
        textField.font = .systemFont(ofSize: 22)
        textField.textContentType = .password
        textField.isSecureTextEntry = true
        textField.defaultTextAttributes.updateValue(5, forKey: .kern)
        textField.accessibilityIdentifier = "pinCreation.pinTextField"
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            textField.cornerConfiguration = .capsule()
        } else {
            textField.layer.cornerRadius = 10
        }
#else
        textField.layer.cornerRadius = 10
#endif
        textField.delegate = self
        return textField
    }()

    private lazy var pinTypeToggleButton: UIButton = {
        let button = UIButton(
            configuration: .mediumBorderless(title: ""),
            primaryAction: UIAction { [weak self] _ in
                self?.togglePinType()
            },
        )
        button.enableMultilineLabel()
        button.accessibilityIdentifier = "pinCreation.pinTypeToggle"
        return button
    }()

    private lazy var continueButton: UIButton = {
        let button = UIButton(
            configuration: .largePrimary(title: CommonStrings.continueButton),
            primaryAction: UIAction { [weak self] _ in
                self?.continuePressed()
            },
        )
        button.accessibilityIdentifier = "pinCreation.nextButton"
        return button
    }()

    private let validationWarningLabel: UILabel = {
        let validationWarningLabel = UILabel()
        validationWarningLabel.textColor = .ows_accentRed
        validationWarningLabel.textAlignment = .center
        validationWarningLabel.font = .dynamicTypeFootnoteClamped
        validationWarningLabel.numberOfLines = 0
        validationWarningLabel.accessibilityIdentifier = "pinCreation.validationWarningLabel"
        return validationWarningLabel
    }()

    private let recommendationLabel: UILabel = {
        let recommendationLabel = UILabel()
        recommendationLabel.textColor = .Signal.secondaryLabel
        recommendationLabel.textAlignment = .center
        recommendationLabel.font = .dynamicTypeFootnoteClamped
        recommendationLabel.numberOfLines = 0
        recommendationLabel.accessibilityIdentifier = "pinCreation.recommendationLabel"
        return recommendationLabel
    }()

    enum Mode: Equatable {
        case creating
        case changing
        case confirming(pinToMatch: String)

        var isConfirming: Bool {
            switch self {
            case .confirming:
                return true
            case .creating, .changing:
                return false
            }
        }
    }

    private let mode: Mode

    private let initialMode: Mode

    enum ValidationState {
        case valid
        case tooShort
        case mismatch
        case weak

        var isInvalid: Bool {
            return self != .valid
        }
    }

    private var validationState: ValidationState = .valid {
        didSet {
            updateValidationWarnings()
        }
    }

    private var pinType: SVR.PinType {
        didSet {
            updatePinType()
        }
    }

    private let showCancelButton: Bool

    // Called once pin setup has finished. Error will be nil upon success
    private let completionHandler: (PinSetupViewController, Error?) -> Void

    private let context: ViewControllerContext

    convenience init(
        mode: Mode,
        showCancelButton: Bool = false,
        completionHandler: @escaping (PinSetupViewController, Error?) -> Void,
    ) {
        self.init(
            mode: mode,
            initialMode: mode,
            pinType: .numeric,
            showCancelButton: showCancelButton,
            completionHandler: completionHandler,
        )
    }

    private init(
        mode: Mode,
        initialMode: Mode,
        pinType: SVR.PinType,
        showCancelButton: Bool,
        completionHandler: @escaping (PinSetupViewController, Error?) -> Void,
    ) {
        assert(DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice)
        self.mode = mode
        self.initialMode = initialMode
        self.pinType = pinType
        self.showCancelButton = showCancelButton
        self.completionHandler = completionHandler
        // TODO[ViewContextPiping]
        self.context = ViewControllerContext.shared
        super.init()

        if case .confirming = self.initialMode {
            owsFailDebug("pin setup flow should never start in the confirming state")
        }
    }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .solid
    }

    public var navbarBackgroundColorOverride: UIColor? {
        return .Signal.groupedBackground
    }

    private var titleText: String {
        switch mode {
        case .confirming:
            return OWSLocalizedString("PIN_CREATION_CONFIRM_TITLE", comment: "Title of the 'pin creation' confirmation view.")
        case .changing:
            return OWSLocalizedString("PIN_CREATION_CHANGING_TITLE", comment: "Title of the 'pin creation' recreation view.")
        case .creating:
            return OWSLocalizedString("PIN_CREATION_TITLE", comment: "Title of the 'pin creation' view.")
        }
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        // Don't allow interactive dismissal.
        isModalInPresentation = true

        view.backgroundColor = .Signal.groupedBackground

        navigationItem.title = titleText
        if showCancelButton {
            navigationItem.rightBarButtonItem = .cancelButton(dismissingFrom: self)
        }
        OWSTableViewController2.removeBackButtonText(viewController: self)

        let buttonContainer = UIStackView(arrangedSubviews: [pinTypeToggleButton, continueButton])
        buttonContainer.axis = .vertical
        buttonContainer.spacing = 16
        buttonContainer.isLayoutMarginsRelativeArrangement = true
        buttonContainer.directionalLayoutMargins = .init(top: 0, leading: 12, bottom: 16, trailing: 12)

        let stackView = UIStackView(arrangedSubviews: [
            explanationLabel,
            pinTextField,
            recommendationLabel,
            validationWarningLabel,
            .vStretchingSpacer(),
            buttonContainer,
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 16
        stackView.setCustomSpacing(24, after: explanationLabel)
        stackView.preservesSuperviewLayoutMargins = true
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        pinTextField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pinTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),

            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])

        updateValidationWarnings()
        updatePinType()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let topMargin: CGFloat = self.prefersNavigationBarHidden ? 32 : 0
        let hMargin: CGFloat = UIDevice.current.isIPhone5OrShorter ? 13 : 26
        view.layoutMargins = UIEdgeInsets(top: topMargin, leading: hMargin, bottom: 0, trailing: hMargin)
        view.layoutIfNeeded()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // TODO: Maybe do this in will appear, to avoid the keyboard sliding in when the view is pushed?
        pinTextField.becomeFirstResponder()
    }

    // MARK: - Events

    private func continuePressed() {
        Logger.info("")

        tryToContinue()
    }

    private func tryToContinue() {
        Logger.info("")

        guard let pin = pinTextField.text?.ows_stripped(), pin.count >= kMin2FAv2PinLength else {
            validationState = .tooShort
            return
        }

        if case .confirming(let pinToMatch) = mode, pinToMatch != pin {
            validationState = .mismatch
            return
        }

        if OWS2FAManager.isWeakPin(pin) {
            validationState = .weak
            return
        }

        switch mode {
        case .changing, .creating:
            let confirmingVC = PinSetupViewController(
                mode: .confirming(pinToMatch: pin),
                initialMode: initialMode,
                pinType: pinType,
                showCancelButton: false, // we're pushing, so we never need a cancel button
                completionHandler: completionHandler,
            )
            navigationController?.pushViewController(confirmingVC, animated: true)
        case .confirming:
            enable2FAAndContinue(withPin: pin)
        }
    }

    private func updateValidationWarnings() {
        AssertIsOnMainThread()

        validationWarningLabel.isHidden = !validationState.isInvalid
        recommendationLabel.isHidden = validationState.isInvalid

        switch validationState {
        case .tooShort:
            switch pinType {
            case .numeric:
                validationWarningLabel.text = OWSLocalizedString(
                    "PIN_CREATION_NUMERIC_HINT",
                    comment: "Label indicating the user must use at least 4 digits",
                )
            case .alphanumeric:
                validationWarningLabel.text = OWSLocalizedString(
                    "PIN_CREATION_ALPHANUMERIC_HINT",
                    comment: "Label indicating the user must use at least 4 characters",
                )
            }
        case .mismatch:
            validationWarningLabel.text = OWSLocalizedString(
                "PIN_CREATION_MISMATCH_ERROR",
                comment: "Label indicating that the attempted PIN does not match the first PIN",
            )
        case .weak:
            validationWarningLabel.text = OWSLocalizedString(
                "PIN_CREATION_WEAK_ERROR",
                comment: "Label indicating that the attempted PIN is too weak",
            )
        default:
            break
        }
    }

    private func updatePinType() {
        AssertIsOnMainThread()

        pinTextField.text = nil
        validationState = .valid

        let recommendationLabelText: String

        switch pinType {
        case .numeric:
            pinTypeToggleButton.configuration?.title = OWSLocalizedString(
                "PIN_CREATION_CREATE_ALPHANUMERIC",
                comment: "Button asking if the user would like to create an alphanumeric PIN",
            )
            pinTextField.keyboardType = .asciiCapableNumberPad
            recommendationLabelText = OWSLocalizedString(
                "PIN_CREATION_NUMERIC_HINT",
                comment: "Label indicating the user must use at least 4 digits",
            )
        case .alphanumeric:
            pinTypeToggleButton.configuration?.title = OWSLocalizedString(
                "PIN_CREATION_CREATE_NUMERIC",
                comment: "Button asking if the user would like to create an numeric PIN",
            )
            pinTextField.keyboardType = .default
            recommendationLabelText = OWSLocalizedString(
                "PIN_CREATION_ALPHANUMERIC_HINT",
                comment: "Label indicating the user must use at least 4 characters",
            )
        }

        pinTextField.reloadInputViews()

        if mode.isConfirming {
            pinTypeToggleButton.isHidden = true
            recommendationLabel.text = OWSLocalizedString(
                "PIN_CREATION_PIN_CONFIRMATION_HINT",
                comment: "Label indication the user must confirm their PIN.",
            )
        } else {
            pinTypeToggleButton.isHidden = false
            recommendationLabel.text = recommendationLabelText
        }
    }

    private func togglePinType() {
        switch pinType {
        case .numeric:
            pinType = .alphanumeric
        case .alphanumeric:
            pinType = .numeric
        }
    }

    private enum PinSetupError: Error {
        case networkFailure
        case enable2FA
    }

    private func enable2FAAndContinue(withPin pin: String) {
        Logger.debug("")

        pinTextField.resignFirstResponder()

        let progressView = AnimatedProgressView(
            loadingText: OWSLocalizedString(
                "PIN_CREATION_PIN_PROGRESS",
                comment: "Indicates the work we are doing while creating the user's pin",
            ),
        )
        view.addSubview(progressView)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            progressView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        progressView.startAnimating {
            self.view.isUserInteractionEnabled = false
            self.explanationLabel.alpha = 0
            self.pinTextField.alpha = 0
            self.validationWarningLabel.alpha = 0
            self.recommendationLabel.alpha = 0
        }

        Task {
            do {
                try await self._enable2FAAndContinue(withPin: pin)
                DispatchQueue.main.async {
                    // The completion handler always dismisses this view, so we don't want to animate anything.
                    progressView.stopAnimatingImmediately()
                    self.completionHandler(self, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    progressView.stopAnimating(success: false) {
                        self.explanationLabel.alpha = 1
                        self.pinTextField.alpha = 1
                        self.validationWarningLabel.alpha = 1
                        self.recommendationLabel.alpha = 1
                    } completion: {
                        self.view.isUserInteractionEnabled = true
                        progressView.removeFromSuperview()

                        guard let error = error as? PinSetupError else {
                            return owsFailDebug("Unexpected error during PIN setup \(error)")
                        }

                        switch error {
                        case .networkFailure:
                            OWSActionSheets.showActionSheet(
                                title: OWSLocalizedString(
                                    "PIN_CREATION_NO_NETWORK_ERROR_TITLE",
                                    comment: "Error title indicating that the attempt to create a PIN failed due to network issues.",
                                ),
                                message: OWSLocalizedString(
                                    "PIN_CREATION_NO_NETWORK_ERROR_MESSAGE",
                                    comment: "Error body indicating that the attempt to create a PIN failed due to network issues.",
                                ),
                            )
                        case .enable2FA:
                            switch self.initialMode {
                            case .changing:
                                OWSActionSheets.showActionSheet(
                                    title: OWSLocalizedString(
                                        "PIN_CHANGE_ERROR_TITLE",
                                        comment: "Error title indicating that the attempt to change a PIN failed.",
                                    ),
                                    message: OWSLocalizedString(
                                        "PIN_CHANGE_ERROR_MESSAGE",
                                        comment: "Error body indicating that the attempt to change a PIN failed.",
                                    ),
                                ) { _ in
                                    self.completionHandler(self, error)
                                }
                            case .creating:
                                OWSActionSheets.showActionSheet(
                                    title: OWSLocalizedString(
                                        "PIN_RECREATION_ERROR_TITLE",
                                        comment: "Error title indicating that the attempt to recreate a PIN failed.",
                                    ),
                                    message: OWSLocalizedString(
                                        "PIN_RECRETION_ERROR_MESSAGE",
                                        comment: "Error body indicating that the attempt to recreate a PIN failed.",
                                    ),
                                ) { _ in
                                    self.completionHandler(self, error)
                                }
                            case .confirming:
                                owsFailDebug("Unexpected initial mode")
                            }
                        }
                    }
                }
            }
        }
    }

    private func _enable2FAAndContinue(withPin pin: String) async throws {
        let accountAttributesUpdater = DependenciesBridge.shared.accountAttributesUpdater
        let ows2FAManager = SSKEnvironment.shared.ows2FAManagerRef

        Logger.warn("Setting PIN.")

        do {
            try await ows2FAManager.enablePin(pin)
        } catch {
            owsFailDebug("Failed to set PIN! \(error)")

            if error.isNetworkFailureOrTimeout {
                throw PinSetupError.networkFailure
            }

            throw PinSetupError.enable2FA
        }

        await DependenciesBridge.shared.db.awaitableWrite { tx in
            // Attempt to update account attributes. This should have been
            // handled internally when we enabled things above, but it doesn't
            // hurt to make sure.
            //
            // This just schedules an update to happen eventually; don't wait on
            // the result.
            accountAttributesUpdater.scheduleAccountAttributesUpdate(authedAccount: .implicit(), tx: tx)

            // Clear the experience upgrade if it was pending.
            ExperienceUpgradeManager.clearExperienceUpgrade(.introducingPins, transaction: tx)
        }
    }
}

// MARK: -

extension PinSetupViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let hasPendingChanges: Bool
        if pinType == .numeric {
            TextFieldFormatting.ows2FAPINTextField(textField, changeCharactersIn: range, replacementString: string)
            hasPendingChanges = false
        } else {
            hasPendingChanges = true
        }

        // Reset the validation state to clear errors, since the user is trying again
        validationState = .valid

        // Inform our caller whether we took care of performing the change.
        return hasPendingChanges
    }
}
