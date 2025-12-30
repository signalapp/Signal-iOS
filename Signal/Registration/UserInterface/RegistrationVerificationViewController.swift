//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
import SignalUI

// MARK: - RegistrationVerificationValidationError

public enum RegistrationVerificationValidationError: Equatable {
    case invalidVerificationCode(invalidCode: String)

    /// We tried to send via sms and failed, but voice code might work
    /// so we are on this screen now. An error should be shown.
    case failedInitialTransport(failedTransport: Registration.CodeTransport)

    /// A third party provider failed to send an sms or call to the session's number.
    /// May be permanent (the user should probably use a different number)
    /// or transient (the user should try again later).
    /// Regardless we let the user submit a code or retry.
    case providerFailure(isPermanent: Bool)

    /// Requesting a code failed with some unknown error; show a
    /// generic dialog and let the user dismiss. They might have actually
    /// gotten a code, so let them submit or resend.
    case genericCodeRequestError(isNetworkError: Bool)

    // These three errors are what happens when we try and
    // take the three respective actions but are rejected
    // with a timeout. The State should have timeout information.
    case smsResendTimeout
    case voiceResendTimeout
    case submitCodeTimeout
}

// MARK: - RegistrationVerificationState

public struct RegistrationVerificationState: Equatable {
    let e164: E164
    let nextSMSDate: Date?
    let nextCallDate: Date?
    let nextVerificationAttemptDate: Date?
    // If false, no option to go back and change e164 will be shown.
    let canChangeE164: Bool
    let showHelpText: Bool
    let validationError: RegistrationVerificationValidationError?

    public enum ExitConfiguration: Equatable {
        case noExitAllowed
        case exitReRegistration
        case exitChangeNumber
    }

    let exitConfiguration: ExitConfiguration
}

// MARK: - RegistrationVerificationPresenter

protocol RegistrationVerificationPresenter: AnyObject {
    func returnToPhoneNumberEntry()
    func requestSMSCode()
    func requestVoiceCode()
    func submitVerificationCode(_ code: String)
    func exitRegistration()
}

// MARK: - RegistrationVerificationViewController

class RegistrationVerificationViewController: OWSViewController {
    init(
        state: RegistrationVerificationState,
        presenter: RegistrationVerificationPresenter,
    ) {
        self.state = state
        self.presenter = presenter

        super.init()

        navigationItem.hidesBackButton = true
    }

    @available(*, unavailable)
    override init() {
        owsFail("This should not be called")
    }

    func updateState(_ state: RegistrationVerificationState) {
        self.state = state
    }

    deinit {
        nowTimer?.invalidate()
        nowTimer = nil
    }

    // MARK: Internal state

    private var state: RegistrationVerificationState {
        didSet { configureUI() }
    }

    private weak var presenter: RegistrationVerificationPresenter?

    private var now = Date() {
        didSet { configureUI() }
    }

    private var nowTimer: Timer?

    private var canRequestSMSCode: Bool {
        guard let nextDate = state.nextSMSDate else { return false }
        return nextDate <= now
    }

    private var canRequestVoiceCode: Bool {
        guard let nextDate = state.nextCallDate else { return false }
        return nextDate <= now
    }

    private var previouslyRenderedValidationError: RegistrationVerificationValidationError?

    // MARK: Rendering

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_VERIFICATION_TITLE_LABEL",
            comment: "Title label for the onboarding verification page",
        ))
        result.accessibilityIdentifier = "registration.verification.titleLabel"
        return result
    }()

    private func explanationLabelText() -> String {
        let format = OWSLocalizedString(
            "ONBOARDING_VERIFICATION_TITLE_DEFAULT_FORMAT",
            comment: "Format for the title of the 'onboarding verification' view. Embeds {{the user's phone number}}.",
        )
        return String(format: format, state.e164.stringValue.e164FormattedAsPhoneNumberWithoutBreaks)
    }

    private lazy var explanationLabel: UILabel = {
        let result = UILabel.explanationLabelForRegistration(text: explanationLabelText())
        result.accessibilityIdentifier = "registration.verification.explanationLabel"
        return result
    }()

    private lazy var wrongNumberButton: UIButton = {
        let button = UIButton(
            configuration: .mediumBorderless(title: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_BACK_LINK",
                comment: "Label for the link that lets users change their phone number in the onboarding views.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapWrongNumberButton()
            },
        )
        button.accessibilityIdentifier = "registration.verification.wrongNumberButton"
        return button
    }()

    private lazy var verificationCodeView: RegistrationVerificationCodeView = {
        let result = RegistrationVerificationCodeView()
        result.delegate = self
        return result
    }()

    private lazy var helpButton: UIButton = {
        let button = UIButton(
            configuration: .mediumBorderless(title: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_HELP_LINK",
                comment: "Label for a button to get help entering a verification code when registering.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapHelpButton()
            },
        )
        button.accessibilityIdentifier = "registration.verification.helpButton"
        return button
    }()

    private func simpleMultilineButton(
        accessibilityIdentifierSuffix: String,
        primaryAction: UIAction,
    ) -> UIButton {
        let result = UIButton(
            configuration: .plain(),
            primaryAction: primaryAction,
        )
        result.configuration?.title = title
        result.configuration?.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadlineClamped)
        result.configuration?.baseForegroundColor = .Signal.accent
        result.enableMultilineLabel()
        result.accessibilityIdentifier = "registration.verification.\(accessibilityIdentifierSuffix)"
        result.setContentHuggingVerticalHigh()
        return result
    }

    private lazy var resendSMSCodeButton = simpleMultilineButton(
        accessibilityIdentifierSuffix: "resendSMSCodeButton",
        primaryAction: UIAction { [weak self] _ in
            self?.didTapResendSMSCode()
        },
    )

    private lazy var requestVoiceCodeButton = simpleMultilineButton(
        accessibilityIdentifierSuffix: "requestVoiceCodeButton",
        primaryAction: UIAction { [weak self] _ in
            self?.didTapSendVoiceCode()
        },
    )

    private lazy var contextButton: ContextMenuButton = {
        let result = ContextMenuButton(empty: ())
        result.autoSetDimensions(to: .square(40))
        result.setImage(Theme.iconImage(.buttonMore), for: .normal)
        if #unavailable(iOS 26) {
            result.tintColor = .Signal.accent
        }
        return result
    }()

    private lazy var contextBarButton = UIBarButtonItem(
        customView: contextButton,
        accessibilityIdentifier: "registration.verificationCode.contextButton",
    )

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.setHidesBackButton(true, animated: false)
        view.backgroundColor = .Signal.background

        // Buttons at the bottom
        let resendButtonsContainer = UIStackView(arrangedSubviews: [
            resendSMSCodeButton,
            requestVoiceCodeButton,
        ])
        resendButtonsContainer.directionalLayoutMargins = .init(hMargin: 0, vMargin: 16)
        resendButtonsContainer.isLayoutMarginsRelativeArrangement = true
        resendButtonsContainer.axis = .horizontal
        resendButtonsContainer.distribution = .fillEqually
        resendButtonsContainer.spacing = 16

        // Main content stack embedded in a scroll view.
        let stackView = addStaticContentStackView(
            arrangedSubviews: [
                titleLabel,
                explanationLabel,
                wrongNumberButton,
                verificationCodeView,
                helpButton,
                .vStretchingSpacer(),
                resendButtonsContainer,
            ],
            isScrollable: true,
            shouldAvoidKeyboard: true,
        )
        stackView.setCustomSpacing(24, after: wrongNumberButton)
        stackView.setCustomSpacing(24, after: verificationCodeView)

        configureUI()

        // We don't need this timer in all cases but it's simpler to start it in all cases.
        nowTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
        }
    }

    private var isViewAppeared = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        verificationCodeView.becomeFirstResponder()

        showValidationErrorUiIfNecessary()

        isViewAppeared = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        isViewAppeared = false
    }

    private func configureUI() {
        switch state.exitConfiguration {
        case .noExitAllowed:
            navigationItem.leftBarButtonItem = nil
        case .exitReRegistration:
            navigationItem.leftBarButtonItem = contextBarButton
            contextButton.setActions(actions: [
                UIAction(
                    title: OWSLocalizedString(
                        "EXIT_REREGISTRATION",
                        comment: "Button to exit re-registration, shown in context menu.",
                    ),
                    handler: { [weak self] _ in
                        self?.presenter?.exitRegistration()
                    },
                ),
            ])
        case .exitChangeNumber:
            navigationItem.leftBarButtonItem = contextBarButton
            contextButton.setActions(actions: [
                UIAction(
                    title: OWSLocalizedString(
                        "EXIT_CHANGE_NUMBER",
                        comment: "Button to exit change number, shown in context menu.",
                    ),
                    handler: { [weak self] _ in
                        self?.presenter?.exitRegistration()
                    },
                ),
            ])
        }

        updateButtonWithTimer(
            button: resendSMSCodeButton,
            date: state.nextSMSDate,
            enabledString: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_RESEND_CODE_BUTTON",
                comment: "Label for button to resend SMS verification code.",
            ),
            countdownFormat: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_RESEND_CODE_COUNTDOWN_FORMAT",
                comment: "Format string for button counting down time until SMS code can be resent. Embeds {{time remaining}}.",
            ),
        )
        updateButtonWithTimer(
            button: requestVoiceCodeButton,
            date: state.nextCallDate,
            enabledString: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_CALL_ME_BUTTON",
                comment: "Label for button to perform verification with a phone call.",
            ),
            countdownFormat: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_CALL_ME_COUNTDOWN_FORMAT",
                comment: "Format string for button counting down time until phone call verification can be performed. Embeds {{time remaining}}.",
            ),
        )

        if isViewAppeared {
            showValidationErrorUiIfNecessary()
        }

        explanationLabel.text = explanationLabelText()
        wrongNumberButton.isHidden = state.canChangeE164.negated
        helpButton.isHidden = state.showHelpText.negated

        verificationCodeView.updateColors()
    }

    private lazy var retryAfterFormatter: DateFormatter = {
        let result = DateFormatter()
        result.dateFormat = "m:ss"
        result.timeZone = TimeZone(identifier: "UTC")!
        return result
    }()

    private func updateButtonWithTimer(
        button: UIButton,
        date: Date?,
        enabledString: String,
        countdownFormat: String,
    ) {
        // UIButton will flash when we update the title.
        UIView.performWithoutAnimation {
            defer { button.layoutIfNeeded() }

            guard let date else {
                button.isHidden = true
                button.isEnabled = false
                return
            }

            if date <= now {
                button.isEnabled = true
                button.configuration?.title = enabledString
            } else {
                button.isEnabled = false
                button.configuration?.title = {
                    let timeRemaining = max(date.timeIntervalSince(now), 0)
                    let durationString = retryAfterFormatter.string(from: Date(timeIntervalSinceReferenceDate: timeRemaining))
                    return String(format: countdownFormat, durationString)
                }()
            }
        }
    }

    private func showValidationErrorUiIfNecessary() {
        let oldError = previouslyRenderedValidationError
        let newError = state.validationError

        previouslyRenderedValidationError = newError

        guard let newError, oldError != newError else { return }
        switch newError {
        case .invalidVerificationCode(let code):
            let message = OWSLocalizedString(
                "REGISTRATION_VERIFICATION_ERROR_INVALID_VERIFICATION_CODE",
                comment: "During registration and re-registration, users may have to enter a code to verify ownership of their phone number. If they enter an invalid code, they will see this error message.",
            )
            if verificationCodeView.verificationCode == code {
                verificationCodeView.clear()
            }
            OWSActionSheets.showActionSheet(title: nil, message: message)

        case .providerFailure(let isPermanent):
            let message: String
            if isPermanent {
                message = OWSLocalizedString(
                    "REGISTRATION_PROVIDER_FAILURE_MESSAGE_PERMANENT",
                    comment: "Error shown if an SMS/call service provider is permanently unable to send a verification code to the provided number.",
                )
            } else {
                message = OWSLocalizedString(
                    "REGISTRATION_PROVIDER_FAILURE_MESSAGE_TRANSIENT",
                    comment: "Error shown if an SMS/call service provider is temporarily unable to send a verification code to the provided number.",
                )
            }
            OWSActionSheets.showActionSheet(title: nil, message: message)

        case .genericCodeRequestError(let isNetworkError):
            let title: String?
            let message: String
            if isNetworkError {
                title = OWSLocalizedString(
                    "REGISTRATION_NETWORK_ERROR_TITLE",
                    comment: "A network error occurred during registration, and an error is shown to the user. This is the title on that error sheet.",
                )
                message = OWSLocalizedString(
                    "REGISTRATION_NETWORK_ERROR_BODY",
                    comment: "A network error occurred during registration, and an error is shown to the user. This is the body on that error sheet.",
                )
            } else {
                title = nil
                message = CommonStrings.somethingWentWrongTryAgainLaterError
            }
            OWSActionSheets.showActionSheet(title: title, message: message)

        case .failedInitialTransport(let failedTransport):
            let errorMessage: String
            let alternativeTransportButtonText: String
            let alternativeTransport: Registration.CodeTransport
            switch failedTransport {
            case .sms:
                errorMessage = OWSLocalizedString(
                    "REGISTRATION_SMS_CODE_FAILED_TRY_VOICE_ERROR",
                    comment: "Error message when sending a verification code via sms failed, but resending via voice call might succeed.",
                )
                alternativeTransportButtonText = OWSLocalizedString(
                    "REGISTRATION_SMS_CODE_FAILED_TRY_VOICE_BUTTON",
                    comment: "Button when sending a verification code via sms failed, but resending via voice call might succeed.",
                )
                alternativeTransport = .voice
            case .voice:
                errorMessage = OWSLocalizedString(
                    "REGISTRATION_VOICE_CODE_FAILED_TRY_SMS_ERROR",
                    comment: "Error message when sending a verification code via voice call failed, but resending via sms might succeed.",
                )
                alternativeTransportButtonText = OWSLocalizedString(
                    "REGISTRATION_VOICE_CODE_FAILED_TRY_SMS_BUTTON",
                    comment: "Button when sending a verification code via voice call failed, but resending via sms might succeed.",
                )
                alternativeTransport = .sms
            }
            let actionSheet = ActionSheetController(title: nil, message: errorMessage)
            actionSheet.addAction(.init(
                title: alternativeTransportButtonText,
                handler: { [weak self] _ in
                    switch alternativeTransport {
                    case .sms:
                        self?.presenter?.requestSMSCode()
                    case .voice:
                        self?.presenter?.requestVoiceCode()
                    }
                },
            ))
            actionSheet.addAction(.cancel)
            self.present(actionSheet, animated: true)
            return

        case .smsResendTimeout, .voiceResendTimeout:
            let message = OWSLocalizedString(
                "REGISTER_RATE_LIMITING_ALERT",
                comment: "Body of action sheet shown when rate-limited during registration.",
            )
            OWSActionSheets.showActionSheet(title: nil, message: message)

        case .submitCodeTimeout:
            guard let nextVerificationAttemptDate = state.nextVerificationAttemptDate else {
                return
            }
            let now = Date()
            if now >= nextVerificationAttemptDate {
                return
            }
            let format = OWSLocalizedString(
                "REGISTRATION_SUBMIT_CODE_RATE_LIMIT_ALERT_FORMAT",
                comment: "Alert shown when submitting a verification code too many times. Embeds {{ duration }}, such as \"5:00\"",
            )

            let formatter: DateFormatter = {
                let result = DateFormatter()
                result.dateFormat = "m:ss"
                result.timeZone = TimeZone(identifier: "UTC")!
                return result
            }()

            let timeRemaining = max(nextVerificationAttemptDate.timeIntervalSince(now), 0)
            let durationString = formatter.string(from: Date(timeIntervalSinceReferenceDate: timeRemaining))
            let message = String(format: format, durationString)
            OWSActionSheets.showActionSheet(title: nil, message: message)
        }
    }

    // MARK: Events

    private func didTapWrongNumberButton() {
        Logger.info("")

        presenter?.returnToPhoneNumberEntry()
    }

    private func didTapHelpButton() {
        Logger.info("")

        self.present(RegistrationVerificationHelpSheetViewController(), animated: true)
    }

    private func didTapResendSMSCode() {
        Logger.info("")

        guard canRequestSMSCode else { return }

        presentActionSheet(.forRegistrationVerificationConfirmation(
            mode: .sms,
            e164: state.e164.stringValue,
            didConfirm: { [weak self] in self?.presenter?.requestSMSCode() },
            didRequestEdit: { [weak self] in self?.presenter?.returnToPhoneNumberEntry() },
        ))
    }

    private func didTapSendVoiceCode() {
        Logger.info("")

        guard canRequestVoiceCode else { return }

        presentActionSheet(.forRegistrationVerificationConfirmation(
            mode: .voice,
            e164: state.e164.stringValue,
            didConfirm: { [weak self] in self?.presenter?.requestVoiceCode() },
            didRequestEdit: { [weak self] in self?.presenter?.returnToPhoneNumberEntry() },
        ))
    }
}

// MARK: - RegistrationVerificationCodeViewDelegate

extension RegistrationVerificationViewController: RegistrationVerificationCodeViewDelegate {
    func codeViewDidChange() {
        if verificationCodeView.isComplete {
            Logger.info("Submitting verification code")
            verificationCodeView.resignFirstResponder()
            // Clear any errors so we render new ones.
            previouslyRenderedValidationError = nil
            presenter?.submitVerificationCode(verificationCodeView.verificationCode)
        }
    }
}

// MARK: - RegistrationVerificationHelpSheetViewController

private class RegistrationVerificationHelpSheetViewController: InteractiveSheetViewController {

    private var intrinsicSizeObservation: NSKeyValueObservation?

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.bounces = false
        scrollView.isScrollEnabled = false
        scrollView.preservesSuperviewLayoutMargins = true
        return scrollView
    }()

    private lazy var stackView: UIStackView = {
        let headerLabel = UILabel()
        headerLabel.textAlignment = .center
        headerLabel.font = UIFont.dynamicTypeTitle2.semibold()
        headerLabel.text = OWSLocalizedString(
            "ONBOARDING_VERIFICATION_HELP_LINK",
            comment: "Label for a button to get help entering a verification code when registering.",
        )
        headerLabel.numberOfLines = 0
        headerLabel.lineBreakMode = .byWordWrapping

        let stackView = UIStackView(arrangedSubviews: [headerLabel])
        stackView.addArrangedSubviews(bulletPoints())
        stackView.spacing = 12
        stackView.setCustomSpacing(20, after: headerLabel)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.preservesSuperviewLayoutMargins = true
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()

    init() {
        super.init()

        self.allowsExpansion = false

        // TODO[Registration]: there should be a contact support link here.

        contentView.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        let insets = UIEdgeInsets(top: 20, left: 0, bottom: 80, right: 0)
        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: insets.top),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -insets.bottom),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
        ])

        intrinsicSizeObservation = stackView.observe(\.bounds, changeHandler: { [weak self] stackView, _ in
            self?.minimizedHeight = stackView.bounds.height + insets.totalHeight
            self?.scrollView.isScrollEnabled = (self?.maxHeight ?? 0) < stackView.bounds.height
        })
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        scrollView.isScrollEnabled = self.maxHeight < stackView.bounds.height
    }

    private func bulletPoints() -> [UIView] {
        return [
            OWSLocalizedString(
                "ONBOARDING_VERIFICATION_HELP_BULLET_1",
                comment: "First bullet point for the explainer sheet for registering via verification code.",
            ),
            OWSLocalizedString(
                "ONBOARDING_VERIFICATION_HELP_BULLET_2",
                comment: "Second bullet point for the explainer sheet for registering via verification code.",
            ),
            OWSLocalizedString(
                "ONBOARDING_VERIFICATION_HELP_BULLET_3",
                comment: "Third bullet point for the explainer sheet for registering via verification code.",
            ),
        ].map { text in
            return RegistrationVerificationHelpSheetViewController.listPointView(text: text)
        }
    }

    private static func listPointView(text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textColor = .Signal.label
        label.font = .dynamicTypeBodyClamped
        label.setCompressionResistanceHigh()

        let bulletPoint = UIView()
        bulletPoint.backgroundColor = UIColor(rgbHex: 0xC4C4C4)
        bulletPoint.autoSetDimensions(to: .init(width: 4, height: 14))

        let stackView = UIStackView(arrangedSubviews: [bulletPoint, label])
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8

        return stackView
    }
}
