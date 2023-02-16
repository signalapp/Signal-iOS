//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalMessaging

// MARK: - RegistrationPhoneNumberValidationError

enum RegistrationPhoneNumberValidationError {
    case invalidNumber(invalidE164: String)
    case rateLimited(expiration: Date)
}

// MARK: - RegistrationPhoneNumberState

struct RegistrationPhoneNumberState {
    enum RegistrationPhoneNumberMode {
        case initialRegistration(
            defaultCountryState: RegistrationCountryState,
            previouslyEnteredE164: String?
        )
        case reregistration(e164: String)
        case changingPhoneNumber(oldE164: String)
    }

    let mode: RegistrationPhoneNumberMode
    let validationError: RegistrationPhoneNumberValidationError?
}

// MARK: - RegistrationPhoneNumberPresenter

protocol RegistrationPhoneNumberPresenter: AnyObject {
    func goToNextStep(withE164: String)
}

// MARK: - RegistrationPhoneNumberViewController

class RegistrationPhoneNumberViewController: OWSViewController {
    public init(
        state: RegistrationPhoneNumberState,
        presenter: RegistrationPhoneNumberPresenter
    ) {
        self.state = state
        self.presenter = presenter

        self.phoneNumberInput = RegistrationPhoneNumberInputView(initialPhoneNumber: {
            switch state.mode {
            case let .initialRegistration(defaultCountryState, previouslyEnteredE164):
                if let e164 = previouslyEnteredE164, let result = RegistrationPhoneNumber(e164: e164) {
                    return result
                }
                return RegistrationPhoneNumber(
                    countryState: defaultCountryState,
                    nationalNumber: ""
                )
            case let .reregistration(e164):
                guard let result = RegistrationPhoneNumber(e164: e164) else {
                    owsFail("Could not parse re-registration E164")
                }
                return result
            case let .changingPhoneNumber(e164):
                guard let result = RegistrationPhoneNumber(e164: e164) else {
                    owsFailBeta("Could not parse re-registration E164. Using fallback")
                    return RegistrationPhoneNumber(countryState: .defaultValue, nationalNumber: "")
                }
                return result
            }
        }())

        super.init()

        self.phoneNumberInput.delegate = self
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

    private var state: RegistrationPhoneNumberState {
        didSet { render() }
    }
    private weak var presenter: RegistrationPhoneNumberPresenter?

    private var now = Date() {
        didSet { render() }
    }
    private var nowTimer: Timer?

    private var nationalNumber: String { phoneNumberInput.nationalNumber }
    private var e164: String { phoneNumberInput.e164 }

    private var localValidationError: RegistrationPhoneNumberValidationError? {
        didSet { render() }
    }

    private var validationError: RegistrationPhoneNumberValidationError? {
        return state.validationError ?? localValidationError
    }

    private var canChangePhoneNumber: Bool {
        switch state.mode {
        case .initialRegistration, .changingPhoneNumber:
            return true
        case .reregistration:
            return false
        }
    }

    private var canSubmit: Bool {
        guard !nationalNumber.isEmpty, e164.isStructurallyValidE164 else {
            return false
        }

        switch state.mode {
        case .initialRegistration:
            break
        case .reregistration:
            return false
        case let .changingPhoneNumber(oldE164):
            if e164 == oldE164 { return false }
        }

        switch validationError {
        case nil:
            break
        case let .invalidNumber(invalidE164):
            if e164 == invalidE164 { return false }
        case let .rateLimited(expiration):
            if expiration > now { return false }
        }

        return true
    }

    // MARK: Rendering

    private lazy var proxyButton: UIButton = {
        let result = ContextMenuButton(contextMenu: .init([
            .init(
                title: OWSLocalizedString(
                    "USE_PROXY_BUTTON",
                    comment: "Button to activate the signal proxy"
                ),
                handler: { [weak self] _ in
                    guard let self else { return }
                    let vc = ProxySettingsViewController()
                    self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
                }
            )
        ]))
        result.showsContextMenuAsPrimaryAction = true
        result.autoSetDimensions(to: .square(40))
        return result
    }()

    private lazy var proxyBarButton = UIBarButtonItem(
        customView: proxyButton,
        accessibilityIdentifier: "registration.phonenumber.proxyButton"
    )

    private lazy var nextBarButton = UIBarButtonItem(
        title: CommonStrings.nextButton,
        style: .done,
        target: self,
        action: #selector(didTapNext),
        accessibilityIdentifier: "registration.phonenumber.nextButton"
    )

    private lazy var titleLabel: UILabel = {
        // TODO[Registration] Localize this text.
        let result = UILabel.titleLabelForRegistration(text: "Your Phone Number")
        result.accessibilityIdentifier = "registration.phonenumber.titleLabel"
        return result
    }()

    private lazy var explanationLabel: UILabel = {
        // TODO[Registration] Localize this text.
        let result = UILabel.explanationLabelForRegistration(text: "Enter your phone number to get started.")
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
        result.font = UIFont.ows_dynamicTypeSubheadlineClamped
        result.accessibilityIdentifier = "registration.phonenumber.validationWarningLabel"
        return result
    }()

    private lazy var retryAfterFormatter: DateFormatter = {
        let result = DateFormatter()
        result.dateFormat = "m:ss"
        result.timeZone = TimeZone(identifier: "UTC")!
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

        let shouldBecomeFirstResponder: Bool = {
            switch validationError {
            case .rateLimited:
                return false
            case nil, .invalidNumber:
                break
            }

            switch state.mode {
            case .reregistration:
                return false
            case .initialRegistration, .changingPhoneNumber:
                break
            }

            return true
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
        navigationItem.leftBarButtonItem = proxyBarButton

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
        navigationItem.rightBarButtonItem = canSubmit ? nextBarButton : nil

        phoneNumberInput.isEnabled = canChangePhoneNumber
        phoneNumberInput.render()

        // We always render the warning label but sometimes invisibly. This avoids UI jumpiness.
        switch validationError {
        case nil:
            validationWarningLabel.alpha = 0
            validationWarningLabel.text = OWSLocalizedString(
                "ONBOARDING_PHONE_NUMBER_VALIDATION_WARNING",
                comment: "Label indicating that the phone number is invalid in the 'onboarding phone number' view."
            )
        case .invalidNumber:
            validationWarningLabel.alpha = 1
            validationWarningLabel.text = OWSLocalizedString(
                "ONBOARDING_PHONE_NUMBER_VALIDATION_WARNING",
                comment: "Label indicating that the phone number is invalid in the 'onboarding phone number' view."
            )
        case let .rateLimited(expiration):
            validationWarningLabel.alpha = expiration > now ? 1 : 0
            let rateLimitFormat = OWSLocalizedString(
                "ONBOARDING_PHONE_NUMBER_RATE_LIMIT_WARNING_FORMAT",
                comment: "Label indicating that registration has been ratelimited. Embeds {{remaining time string}}."
            )
            let timeRemaining = max(expiration.timeIntervalSince(now), 0)
            let durationString = retryAfterFormatter.string(from: Date(timeIntervalSinceReferenceDate: timeRemaining))
            validationWarningLabel.text = String(format: rateLimitFormat, durationString)
        }

        view.backgroundColor = Theme.backgroundColor
        proxyButton.setImage(Theme.iconImage(.more24), for: .normal)
        proxyButton.tintColor = Theme.accentBlueColor
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

    // MARK: Events

    @objc
    private func didTapNext() {
        goToNextStep()
    }

    private func goToNextStep() {
        Logger.info("")

        phoneNumberInput.resignFirstResponder()

        let e164 = self.e164

        guard
            let phoneNumber = PhoneNumber(fromE164: e164),
            PhoneNumberValidator().isValidForRegistration(phoneNumber: phoneNumber)
        else {
            localValidationError = .invalidNumber(invalidE164: e164)
            return
        }
        localValidationError = nil

        presentActionSheet(.forRegistrationVerificationConfirmation(
            mode: .sms,
            e164: e164,
            didConfirm: { [weak self] in self?.presenter?.goToNextStep(withE164: e164) },
            didRequestEdit: { [weak self] in self?.phoneNumberInput.becomeFirstResponder() }
        ))
    }

    @objc
    private func didTimeAdvance() {
        now = Date()
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
