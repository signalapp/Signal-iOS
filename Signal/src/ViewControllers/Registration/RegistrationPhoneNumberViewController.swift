//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalMessaging

// MARK: - RegistrationPhoneNumberPresenter

protocol RegistrationPhoneNumberPresenter: AnyObject {
    func goToNextStep(withE164: E164)
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
                if let e164 = state.previouslyEnteredE164, let result = RegistrationPhoneNumber(e164: e164) {
                    return result
                }
                return RegistrationPhoneNumber(
                    countryState: .defaultValue,
                    nationalNumber: ""
                )
            case let .reregistration(state):
                guard let result = RegistrationPhoneNumber(e164: state.e164) else {
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
    private var e164: E164? { phoneNumberInput.e164 }

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

    private var canSubmit: Bool {
        guard !nationalNumber.isEmpty, let e164 else {
            return false
        }

        switch state {
        case .initialRegistration:
            break
        case .reregistration:
            return true
        }

        if validationError?.canSubmit(e164: e164) == false {
            return false
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
        result.font = UIFont.ows_dynamicTypeSubheadlineClamped
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

        let shouldBecomeFirstResponder: Bool = {
            switch validationError {
            case .rateLimited:
                return false
            case nil, .invalidNumber:
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
        if let warningLabelText = validationError?.warningLabelText() {
            validationWarningLabel.alpha = 1
            validationWarningLabel.text = warningLabelText
        } else {
            validationWarningLabel.alpha = 0
        }
        switch validationError {
        case nil, .rateLimited:
            break
        case let .invalidNumber(error):
            showInvalidPhoneNumberAlertIfNecessary(for: error.invalidE164.stringValue)
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

    private var previousInvalidE164: String?

    private func showInvalidPhoneNumberAlertIfNecessary(for e164: String) {
        let shouldShowAlert = e164 != previousInvalidE164
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

        previousInvalidE164 = e164
    }

    // MARK: Events

    @objc
    private func didTapNext() {
        goToNextStep()
    }

    private func goToNextStep() {
        Logger.info("")

        phoneNumberInput.resignFirstResponder()

        guard let e164 = self.e164 else {
            return
        }

        guard
            let phoneNumber = PhoneNumber(fromE164: e164.stringValue),
            PhoneNumberValidator().isValidForRegistration(phoneNumber: phoneNumber)
        else {
            localValidationError = .invalidNumber(.init(invalidE164: e164))
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
