//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
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
    public init(
        state: RegistrationVerificationState,
        presenter: RegistrationVerificationPresenter
    ) {
        self.state = state
        self.presenter = presenter

        super.init()
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    public func updateState(_ state: RegistrationVerificationState) {
        self.state = state
    }

    deinit {
        nowTimer?.invalidate()
        nowTimer = nil
    }

    // MARK: Internal state

    private var state: RegistrationVerificationState {
        didSet { render() }
    }

    private weak var presenter: RegistrationVerificationPresenter?

    private var now = Date() {
        didSet { render() }
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

    private func button(
        title: String = "",
        selector: Selector,
        accessibilityIdentifierSuffix: String
    ) -> UIButton {
        let result = UIButton(type: .system)

        result.addTarget(self, action: selector, for: .touchUpInside)

        result.setTitle(title, for: .normal)
        if let titleLabel = result.titleLabel {
            titleLabel.font = .dynamicTypeSubheadlineClamped
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.textAlignment = .center
            result.heightAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.heightAnchor
            ).isActive = true
        } else {
            owsFailBeta("Button has no title label")
        }

        result.accessibilityIdentifier = "registration.verification.\(accessibilityIdentifierSuffix)"

        return result
    }

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_VERIFICATION_TITLE_LABEL",
            comment: "Title label for the onboarding verification page"
        ))
        result.accessibilityIdentifier = "registration.verification.titleLabel"
        return result
    }()

    private var explanationLabelText: String {
        let format = OWSLocalizedString(
            "ONBOARDING_VERIFICATION_TITLE_DEFAULT_FORMAT",
            comment: "Format for the title of the 'onboarding verification' view. Embeds {{the user's phone number}}."
        )
        return String(format: format, state.e164.stringValue.e164FormattedAsPhoneNumberWithoutBreaks)
    }

    private lazy var explanationLabel: UILabel = {
        let result = UILabel.explanationLabelForRegistration(text: explanationLabelText)
        result.accessibilityIdentifier = "registration.verification.explanationLabel"
        return result
    }()

    private lazy var wrongNumberButton = button(
        title: OWSLocalizedString(
            "ONBOARDING_VERIFICATION_BACK_LINK",
            comment: "Label for the link that lets users change their phone number in the onboarding views."
        ),
        selector: #selector(didTapWrongNumberButton),
        accessibilityIdentifierSuffix: "wrongNumberButton"
    )

    private lazy var verificationCodeView: RegistrationVerificationCodeView = {
        let result = RegistrationVerificationCodeView()
        result.delegate = self
        return result
    }()

    private lazy var helpButton = button(
        title: OWSLocalizedString(
            "ONBOARDING_VERIFICATION_HELP_LINK",
            comment: "Label for a button to get help entering a verification code when registering."
        ),
        selector: #selector(didTapHelpButton),
        accessibilityIdentifierSuffix: "helpButton"
    )

    private lazy var resendSMSCodeButton = button(
        selector: #selector(didTapResendSMSCode),
        accessibilityIdentifierSuffix: "resendSMSCodeButton"
    )

    private lazy var requestVoiceCodeButton = button(
        selector: #selector(didTapSendVoiceCode),
        accessibilityIdentifierSuffix: "requestVoiceCodeButton"
    )

    private lazy var contextButton: ContextMenuButton = {
        let result = ContextMenuButton()
        result.showsContextMenuAsPrimaryAction = true
        result.autoSetDimensions(to: .square(40))
        return result
    }()

    private lazy var contextBarButton = UIBarButtonItem(
        customView: contextButton,
        accessibilityIdentifier: "registration.verificationCode.contextButton"
    )

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.setHidesBackButton(true, animated: false)

        initialRender()

        // We don't need this timer in all cases but it's simpler to start it in all cases.
        nowTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
        }
    }

    private var isViewAppeared = false

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        verificationCodeView.becomeFirstResponder()

        showValidationErrorUiIfNecessary()

        isViewAppeared = true
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if contextButton.isShowingContextMenu {
            contextButton.dismissContextMenu(animated: animated)
        }

        isViewAppeared = false
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    private func initialRender() {
        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.autoPinWidthToSuperview()
        scrollView.autoPinEdge(.top, to: .top, of: keyboardLayoutGuideViewSafeArea)
        scrollView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.layoutMargins = UIEdgeInsets.layoutMarginsForRegistration(
            traitCollection.horizontalSizeClass
        )
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.setContentHuggingHigh()
        scrollView.addSubview(stackView)
        stackView.autoPinWidth(toWidthOf: scrollView)
        stackView.heightAnchor.constraint(
            greaterThanOrEqualTo: scrollView.contentLayoutGuide.heightAnchor
        ).isActive = true
        stackView.heightAnchor.constraint(
            greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor
        ).isActive = true

        stackView.addArrangedSubview(titleLabel)

        stackView.addArrangedSubview(explanationLabel)

        stackView.addArrangedSubview(wrongNumberButton)
        stackView.setCustomSpacing(24, after: wrongNumberButton)

        stackView.addArrangedSubview(verificationCodeView)
        stackView.setCustomSpacing(24, after: verificationCodeView)

        stackView.addArrangedSubview(helpButton)

        stackView.addArrangedSubview(UIView.vStretchingSpacer())

        let resendButtonsContainer = UIStackView(arrangedSubviews: [
            resendSMSCodeButton,
            requestVoiceCodeButton
        ])
        resendButtonsContainer.axis = .horizontal
        resendButtonsContainer.distribution = .fillEqually

        stackView.addArrangedSubview(resendButtonsContainer)

        render()
    }

    private func render() {
        switch state.exitConfiguration {
        case .noExitAllowed:
            navigationItem.leftBarButtonItem = nil
        case .exitReRegistration:
            navigationItem.leftBarButtonItem = contextBarButton
            contextButton.contextMenu = ContextMenu([
                .init(
                    title: OWSLocalizedString(
                        "EXIT_REREGISTRATION",
                        comment: "Button to exit re-registration, shown in context menu."
                    ),
                    handler: { [weak self] _ in
                        self?.presenter?.exitRegistration()
                    }
                )
            ])
        case .exitChangeNumber:
            navigationItem.leftBarButtonItem = contextBarButton
            contextButton.contextMenu = ContextMenu([
                .init(
                    title: OWSLocalizedString(
                        "EXIT_CHANGE_NUMBER",
                        comment: "Button to exit change number, shown in context menu."
                    ),
                    handler: { [weak self] _ in
                        self?.presenter?.exitRegistration()
                    }
                )
            ])
        }

        contextButton.setImage(Theme.iconImage(.buttonMore), for: .normal)
        contextButton.tintColor = Theme.accentBlueColor

        renderResendButton(
            button: resendSMSCodeButton,
            date: state.nextSMSDate,
            enabledString: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_RESEND_CODE_BUTTON",
                comment: "Label for button to resend SMS verification code."
            ),
            countdownFormat: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_RESEND_CODE_COUNTDOWN_FORMAT",
                comment: "Format string for button counting down time until SMS code can be resent. Embeds {{time remaining}}."
            )
        )
        renderResendButton(
            button: requestVoiceCodeButton,
            date: state.nextCallDate,
            enabledString: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_CALL_ME_BUTTON",
                comment: "Label for button to perform verification with a phone call."
            ),
            countdownFormat: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_CALL_ME_COUNTDOWN_FORMAT",
                comment: "Format string for button counting down time until phone call verification can be performed. Embeds {{time remaining}}."
            )
        )

        if isViewAppeared {
            showValidationErrorUiIfNecessary()
        }

        view.backgroundColor = Theme.backgroundColor
        titleLabel.textColor = .colorForRegistrationTitleLabel
        explanationLabel.textColor = .colorForRegistrationExplanationLabel
        explanationLabel.text = explanationLabelText
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

    private func renderResendButton(
        button: UIButton,
        date: Date?,
        enabledString: String,
        countdownFormat: String
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
                button.setTitle(enabledString, for: .normal)
            } else {
                button.isEnabled = false
                button.setTitle(
                    {
                        let timeRemaining = max(date.timeIntervalSince(now), 0)
                        let durationString = retryAfterFormatter.string(from: Date(timeIntervalSinceReferenceDate: timeRemaining))
                        return String(format: countdownFormat, durationString)
                    }(),
                    for: .normal
                )
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
                comment: "During registration and re-registration, users may have to enter a code to verify ownership of their phone number. If they enter an invalid code, they will see this error message."
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
                    comment: "Error shown if an SMS/call service provider is permanently unable to send a verification code to the provided number."
                )
            } else {
                message = OWSLocalizedString(
                    "REGISTRATION_PROVIDER_FAILURE_MESSAGE_TRANSIENT",
                    comment: "Error shown if an SMS/call service provider is temporarily unable to send a verification code to the provided number."
                )
            }
            OWSActionSheets.showActionSheet(title: nil, message: message)

        case .genericCodeRequestError(let isNetworkError):
            let title: String?
            let message: String
            if isNetworkError {
                title = OWSLocalizedString(
                    "REGISTRATION_NETWORK_ERROR_TITLE",
                    comment: "A network error occurred during registration, and an error is shown to the user. This is the title on that error sheet."
                )
                message = OWSLocalizedString(
                    "REGISTRATION_NETWORK_ERROR_BODY",
                    comment: "A network error occurred during registration, and an error is shown to the user. This is the body on that error sheet."
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
                    comment: "Error message when sending a verification code via sms failed, but resending via voice call might succeed."
                )
                alternativeTransportButtonText = OWSLocalizedString(
                    "REGISTRATION_SMS_CODE_FAILED_TRY_VOICE_BUTTON",
                    comment: "Button when sending a verification code via sms failed, but resending via voice call might succeed."
                )
                alternativeTransport = .voice
            case .voice:
                errorMessage = OWSLocalizedString(
                    "REGISTRATION_VOICE_CODE_FAILED_TRY_SMS_ERROR",
                    comment: "Error message when sending a verification code via voice call failed, but resending via sms might succeed."
                )
                alternativeTransportButtonText = OWSLocalizedString(
                    "REGISTRATION_VOICE_CODE_FAILED_TRY_SMS_BUTTON",
                    comment: "Button when sending a verification code via voice call failed, but resending via sms might succeed."
                )
                alternativeTransport = .sms
            }
            let actionSheet = ActionSheetController(title: nil, message: errorMessage)
            actionSheet.addAction(.init(
                title: alternativeTransportButtonText,
                accessibilityIdentifier: nil,
                handler: { [weak self] _ in
                    switch alternativeTransport {
                    case .sms:
                        self?.presenter?.requestSMSCode()
                    case .voice:
                        self?.presenter?.requestVoiceCode()
                    }
                }
            ))
            actionSheet.addAction(.init(
                title: CommonStrings.cancelButton,
                accessibilityIdentifier: nil
            ))
            self.present(actionSheet, animated: true)
            return

        case .smsResendTimeout, .voiceResendTimeout:
            let message = OWSLocalizedString(
                "REGISTER_RATE_LIMITING_ALERT",
                comment: "Body of action sheet shown when rate-limited during registration."
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
                comment: "Alert shown when submitting a verification code too many times. Embeds {{ duration }}, such as \"5:00\""
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

    @objc
    private func didTapWrongNumberButton() {
        Logger.info("")

        presenter?.returnToPhoneNumberEntry()
    }

    @objc
    private func didTapHelpButton() {
        Logger.info("")

        self.present(RegistrationVerificationHelpSheetViewController(), animated: true)
    }

    @objc
    private func didTapResendSMSCode() {
        Logger.info("")

        guard canRequestSMSCode else { return }

        presentActionSheet(.forRegistrationVerificationConfirmation(
            mode: .sms,
            e164: state.e164.stringValue,
            didConfirm: { [weak self] in self?.presenter?.requestSMSCode() },
            didRequestEdit: { [weak self] in self?.presenter?.returnToPhoneNumberEntry() }
        ))
    }

    @objc
    private func didTapSendVoiceCode() {
        Logger.info("")

        guard canRequestVoiceCode else { return }

        presentActionSheet(.forRegistrationVerificationConfirmation(
            mode: .voice,
            e164: state.e164.stringValue,
            didConfirm: { [weak self] in self?.presenter?.requestVoiceCode() },
            didRequestEdit: { [weak self] in self?.presenter?.returnToPhoneNumberEntry() }
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

    public required init() {
        super.init()

        scrollView.bounces = false
        scrollView.isScrollEnabled = false

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12

        stackView.addArrangedSubview(header)
        stackView.setCustomSpacing(20, after: header)
        let bulletPoints = bulletPoints
        stackView.addArrangedSubviews(bulletPoints)

        // TODO[Registration]: there should be a contact support link here.

        let insets = UIEdgeInsets(top: 20, left: 24, bottom: 80, right: 24)
        contentView.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()
        scrollView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges(with: insets)
        stackView.autoConstrainAttribute(.width, to: .width, of: contentView, withOffset: -insets.totalWidth)

        self.allowsExpansion = false
        intrinsicSizeObservation = stackView.observe(\.bounds, changeHandler: { [weak self] stackView, _ in
            self?.minimizedHeight = stackView.bounds.height + insets.totalHeight
            self?.scrollView.isScrollEnabled = (self?.maxHeight ?? 0) < stackView.bounds.height
        })
    }

    override public func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        scrollView.isScrollEnabled = self.maxHeight < stackView.bounds.height
    }

    let scrollView = UIScrollView()
    let stackView = UIStackView()

    let header: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = UIFont.dynamicTypeTitle2.semibold()
        label.text = OWSLocalizedString(
            "ONBOARDING_VERIFICATION_HELP_LINK",
            comment: "Label for a button to get help entering a verification code when registering."
        )
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }()

    let bulletPoints: [UIView] = {
        return [
            OWSLocalizedString(
                "ONBOARDING_VERIFICATION_HELP_BULLET_1",
                comment: "First bullet point for the explainer sheet for registering via verification code."
            ),
            OWSLocalizedString(
                "ONBOARDING_VERIFICATION_HELP_BULLET_2",
                comment: "Second bullet point for the explainer sheet for registering via verification code."
            ),
            OWSLocalizedString(
                "ONBOARDING_VERIFICATION_HELP_BULLET_3",
                comment: "Third bullet point for the explainer sheet for registering via verification code."
            )
        ].map { text in
            return RegistrationVerificationHelpSheetViewController.listPointView(text: text)
        }
    }()

    private static func listPointView(text: String) -> UIStackView {
        let stackView = UIStackView(frame: .zero)

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8

        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textColor = Theme.primaryTextColor
        label.font = .dynamicTypeBodyClamped

        let bulletPoint = UIView()
        bulletPoint.backgroundColor = UIColor(rgbHex: 0xC4C4C4)

        stackView.addArrangedSubview(.spacer(withWidth: 4))
        stackView.addArrangedSubview(bulletPoint)
        stackView.addArrangedSubview(label)

        bulletPoint.autoSetDimensions(to: .init(width: 4, height: 14))
        label.setCompressionResistanceHigh()
        return stackView
    }
}
