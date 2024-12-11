//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - RegistrationPhoneNumberPresenter

protocol RegistrationPhoneNumberPresenter: AnyObject {
    func goToNextStep(withE164: E164)

    func exitRegistration()
}

// MARK: - RegistrationPhoneNumberViewController

class RegistrationPhoneNumberViewController: OWSViewController {
    public init(
        state: RegistrationPhoneNumberViewState.RegistrationMode,
        presenter: RegistrationPhoneNumberPresenter
    ) {
        self.state = state
        self.presenter = presenter

        self.phoneNumberInput = RegistrationPhoneNumberInputView(initialPhoneNumber: {
            switch state {
            case let .initialRegistration(state):
                if let e164 = state.previouslyEnteredE164, let result = RegistrationPhoneNumberParser(phoneNumberUtil: SSKEnvironment.shared.phoneNumberUtilRef).parseE164(e164) {
                    return result
                }
                return RegistrationPhoneNumber(
                    country: .defaultValue,
                    nationalNumber: ""
                )
            case let .reregistration(state):
                guard let result = RegistrationPhoneNumberParser(phoneNumberUtil: SSKEnvironment.shared.phoneNumberUtilRef).parseE164(state.e164) else {
                    owsFail("Could not parse re-registration E164")
                }
                return result
            }
        }())

        super.init()

        self.phoneNumberInput.delegate = self
    }

    public func updateState(_ state: RegistrationPhoneNumberViewState.RegistrationMode) {
        self.state = state
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    deinit {
        nowTimer?.invalidate()
        nowTimer = nil
    }

    // MARK: Internal state

    private var state: RegistrationPhoneNumberViewState.RegistrationMode {
        didSet { render() }
    }
    private weak var presenter: RegistrationPhoneNumberPresenter?

    private var now = Date() {
        didSet { render() }
    }
    private var nowTimer: Timer?

    private var nationalNumber: String { phoneNumberInput.nationalNumber }

    private var countryCode: String {
        return phoneNumberInput.country.countryCode
    }

    private var localValidationError: RegistrationPhoneNumberViewState.ValidationError? {
        didSet { render() }
    }

    private var validationError: RegistrationPhoneNumberViewState.ValidationError? {
        switch state {
        case .initialRegistration(let initialRegistration):
            return initialRegistration.validationError ?? localValidationError
        case .reregistration(let reregistration):
            return reregistration.validationError ?? localValidationError
        }
    }

    private var canChangePhoneNumber: Bool {
        switch state {
        case .initialRegistration:
            return true
        case .reregistration:
            return false
        }
    }

    private func canSubmit(isBlockedByValidationError: Bool) -> Bool {
        if phoneNumberInput.nationalNumber.isEmpty {
            return false
        }

        switch state {
        case .initialRegistration:
            return !isBlockedByValidationError
        case .reregistration:
            return true
        }
    }

    // MARK: Rendering

    private lazy var contextButton: ContextMenuButton = {
        let result = ContextMenuButton(empty: ())
        result.autoSetDimensions(to: .square(40))
        return result
    }()

    private lazy var contextBarButton = UIBarButtonItem(
        customView: contextButton,
        accessibilityIdentifier: "registration.verificationCode.contextButton"
    )

    private lazy var nextBarButton = UIBarButtonItem(
        title: CommonStrings.nextButton,
        style: .done,
        target: self,
        action: #selector(didTapNext),
        accessibilityIdentifier: "registration.phonenumber.nextButton"
    )

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_PHONE_NUMBER_TITLE",
            comment: "During registration, users are asked to enter their phone number. This is the title on that screen."
        ))
        result.accessibilityIdentifier = "registration.phonenumber.titleLabel"
        return result
    }()

    private lazy var explanationLabel: UILabel = {
        let result = UILabel.explanationLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_PHONE_NUMBER_SUBTITLE",
            comment: "During registration, users are asked to enter their phone number. This is the subtitle on that screen, which gives users some instructions."
        ))
        result.accessibilityIdentifier = "registration.phonenumber.explanationLabel"
        return result
    }()

    private let phoneNumberInput: RegistrationPhoneNumberInputView

    private var phoneStrokeNormal: UIView?
    private var phoneStrokeError: UIView?

    private lazy var validationWarningLabel: UILabel = {
        let result = UILabel()
        result.textColor = .ows_accentRed
        result.numberOfLines = 0
        result.font = UIFont.dynamicTypeSubheadlineClamped
        result.accessibilityIdentifier = "registration.phonenumber.validationWarningLabel"
        return result
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()

        initialRender()

        // We only need this timer if the user has been rate limited, but it's simpler to always
        // start it.
        nowTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Logger.info("")

        let shouldBecomeFirstResponder: Bool = {
            switch validationError {
            case .rateLimited:
                return false
            case nil, .invalidInput, .invalidE164:
                break
            }

            switch state {
            case .reregistration:
                return false
            case .initialRegistration:
                return true
            }
        }()
        if shouldBecomeFirstResponder {
            phoneNumberInput.becomeFirstResponder()
        }
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    private func initialRender() {
        let stackView = UIStackView()

        stackView.axis = .vertical
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(12, after: titleLabel)

        stackView.addArrangedSubview(explanationLabel)
        stackView.setCustomSpacing(24, after: explanationLabel)

        stackView.addArrangedSubview(phoneNumberInput)
        stackView.setCustomSpacing(11, after: phoneNumberInput)

        stackView.addArrangedSubview(validationWarningLabel)

        stackView.addArrangedSubview(UIView.vStretchingSpacer())

        render()
    }

    private func render() {
        var actions: [UIAction] = [
            UIAction(
                title: OWSLocalizedString(
                    "USE_PROXY_BUTTON",
                    comment: "Button to activate the signal proxy"
                ),
                handler: { [weak self] _ in
                    guard let self else { return }
                    let vc = ProxySettingsViewController(validationMethod: .restGetRegistrationSession)
                    self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
                }
            )
        ]
        let canExitRegistration: Bool
        switch state {
        case .initialRegistration(let subState):
            canExitRegistration = subState.canExitRegistration
        case .reregistration(let subState):
            canExitRegistration = subState.canExitRegistration
        }
        if canExitRegistration {
            actions.append(UIAction(
                title: OWSLocalizedString(
                    "EXIT_REREGISTRATION",
                    comment: "Button to exit re-registration, shown in context menu."
                ),
                handler: { [weak self] _ in
                    self?.presenter?.exitRegistration()
                }
            ))
        }
        contextButton.setActions(actions: actions)
        navigationItem.leftBarButtonItem = contextBarButton

        contextButton.setImage(Theme.iconImage(.buttonMore), for: .normal)
        contextButton.tintColor = Theme.accentBlueColor

        let now = Date()

        let isBlockedByValidationError = { () -> Bool in
            switch validationError {
            case let .invalidInput(error):
                return !error.canSubmit(countryCode: countryCode, nationalNumber: nationalNumber)
            case let .invalidE164(error):
                return !error.canSubmit(e164: parseE164())
            case let .rateLimited(error):
                return !error.canSubmit(e164: parseE164(), dateProvider: { now })
            case nil:
                return false
            }
        }()

        navigationItem.rightBarButtonItem = canSubmit(isBlockedByValidationError: isBlockedByValidationError) ? nextBarButton : nil

        phoneNumberInput.isEnabled = canChangePhoneNumber
        phoneNumberInput.render()

        // We always render the warning label but sometimes invisibly. This avoids UI jumpiness.
        if isBlockedByValidationError, let validationError {
            validationWarningLabel.alpha = 1
            validationWarningLabel.text = validationError.warningLabelText(dateProvider: { now })
        } else {
            validationWarningLabel.alpha = 0
        }
        switch validationError {
        case nil, .rateLimited:
            break
        case let .invalidInput(error):
            showInvalidPhoneNumberAlertIfNecessary(for: .invalidInput(countryCode: error.invalidCountryCode, nationalNumber: error.invalidNationalNumber))
        case let .invalidE164(error):
            showInvalidPhoneNumberAlertIfNecessary(for: .invalidE164(error.invalidE164))
        }

        view.backgroundColor = Theme.backgroundColor
        nextBarButton.tintColor = Theme.accentBlueColor
        titleLabel.textColor = .colorForRegistrationTitleLabel
        explanationLabel.textColor = .colorForRegistrationExplanationLabel

        // In some cases, the safe area insets will change unexpectedly after presenting a view
        // controller. This causes layout jumpiness.
        //
        // After several of us investigated, we believe it to be an iOS bug with Dynamic Island
        // devices, but we aren't sure. In any case, forcing a relayout fixes the bug and seems to
        // keep the safe area insets from changing.
        view.layoutSubviews()
    }

    private enum InvalidNumberError: Equatable {
        case invalidInput(countryCode: String, nationalNumber: String)
        case invalidE164(E164)
    }

    private var previousInvalidNumberError: InvalidNumberError?

    private func showInvalidPhoneNumberAlertIfNecessary(for invalidNumberError: InvalidNumberError) {
        let shouldShowAlert = invalidNumberError != previousInvalidNumberError
        if shouldShowAlert {
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString(
                    "REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_TITLE",
                    comment: "Title of alert indicating that users needs to enter a valid phone number to register."
                ),
                message: OWSLocalizedString(
                    "REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_MESSAGE",
                    comment: "Message of alert indicating that users needs to enter a valid phone number to register."
                )
            )
        }

        previousInvalidNumberError = invalidNumberError
    }

    // MARK: Events

    @objc
    private func didTapNext() {
        goToNextStep()
    }

    private func parseE164() -> E164? {
        let phoneNumberUtil = SSKEnvironment.shared.phoneNumberUtilRef
        return E164(phoneNumberUtil.parsePhoneNumber(countryCode: countryCode, nationalNumber: nationalNumber)?.e164)
    }

    private func goToNextStep() {
        Logger.info("")

        phoneNumberInput.resignFirstResponder()

        guard let e164 = parseE164() else {
            localValidationError = .invalidInput(.init(invalidCountryCode: countryCode, invalidNationalNumber: nationalNumber))
            return
        }
        guard PhoneNumberValidator().isValidForRegistration(phoneNumber: e164) else {
            localValidationError = .invalidE164(.init(invalidE164: e164))
            return
        }
        localValidationError = nil

        presentActionSheet(.forRegistrationVerificationConfirmation(
            mode: .sms,
            e164: e164.stringValue,
            didConfirm: { [weak self] in self?.presenter?.goToNextStep(withE164: e164) },
            didRequestEdit: { [weak self] in self?.phoneNumberInput.becomeFirstResponder() }
        ))
    }
}

// MARK: - RegistrationPhoneNumberInputViewDelegate

extension RegistrationPhoneNumberViewController: RegistrationPhoneNumberInputViewDelegate {
    func present(_ countryCodeViewController: CountryCodeViewController) {
        let navController = OWSNavigationController(rootViewController: countryCodeViewController)
        present(navController, animated: true)
    }

    func didChange() {
        render()
    }

    func didPressReturn() {
        goToNextStep()
    }
}
