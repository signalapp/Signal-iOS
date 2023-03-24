//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

// MARK: - RegistrationVerificationValidationError

public enum RegistrationVerificationValidationError: Equatable {
    case invalidVerificationCode(invalidCode: String)
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
    // TODO[Registration]: use this state to render a countdown.
    let nextVerificationAttemptDate: Date
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
    ) -> OWSFlatButton {
        let result = OWSFlatButton.button(
            title: title,
            font: UIFont.ows_dynamicTypeSubheadlineClamped,
            titleColor: .clear, // This should be overwritten in `render`.
            backgroundColor: .clear,
            target: self,
            selector: selector
        )
        result.enableMultilineLabel()
        result.contentEdgeInsets = UIEdgeInsets(margin: 12)
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

    private lazy var explanationLabel: UILabel = {
        let format = OWSLocalizedString(
            "ONBOARDING_VERIFICATION_TITLE_DEFAULT_FORMAT",
            comment: "Format for the title of the 'onboarding verification' view. Embeds {{the user's phone number}}."
        )
        let text = String(format: format, state.e164.stringValue.e164FormattedAsPhoneNumberWithoutBreaks)

        let result = UILabel.explanationLabelForRegistration(text: text)
        result.accessibilityIdentifier = "registration.verification.explanationLabel"
        return result
    }()

    private lazy var wrongNumberButton: OWSFlatButton = button(
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

    private lazy var resendSMSCodeButton: OWSFlatButton = button(
        selector: #selector(didTapResendSMSCode),
        accessibilityIdentifierSuffix: "resendSMSCodeButton"
    )

    private lazy var requestVoiceCodeButton: OWSFlatButton = button(
        selector: #selector(didTapSendVoiceCode),
        accessibilityIdentifierSuffix: "requestVoiceCodeButton"
    )

    public override func viewDidLoad() {
        super.viewDidLoad()

        initialRender()

        // We don't need this timer in all cases but it's simpler to start it in all cases.
        nowTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        verificationCodeView.becomeFirstResponder()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if contextButton.isShowingContextMenu {
            contextButton.dismissContextMenu(animated: animated)
        }
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    private func initialRender() {
        let stackView = UIStackView()

        stackView.axis = .vertical
        stackView.spacing = 12
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        stackView.addArrangedSubview(titleLabel)

        stackView.addArrangedSubview(explanationLabel)

        stackView.addArrangedSubview(wrongNumberButton)
        stackView.setCustomSpacing(24, after: wrongNumberButton)

        stackView.addArrangedSubview(verificationCodeView)

        // TODO[Registration]: If the user has tried several times, show a "need help" button.

        stackView.addArrangedSubview(UIView.vStretchingSpacer(minHeight: 12))

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

        contextButton.setImage(Theme.iconImage(.more24), for: .normal)
        contextButton.tintColor = Theme.accentBlueColor

        renderResendButton(
            button: resendSMSCodeButton,
            date: state.nextSMSDate,
            // TODO: This copy is ambiguous if you request a voice code. Does "resend code" mean
            // that you'll get a new SMS code or a new voice code? We should update the wording to
            // make it clearer that it's an SMS code.
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

        showValidationErrorUiIfNecessary()

        view.backgroundColor = Theme.backgroundColor
        titleLabel.textColor = .colorForRegistrationTitleLabel
        explanationLabel.textColor = .colorForRegistrationExplanationLabel
        wrongNumberButton.setTitleColor(Theme.accentBlueColor)
        // TODO: Update colors of `verificationCodeView`, which is relevant if the theme changes.
    }

    private lazy var retryAfterFormatter: DateFormatter = {
        let result = DateFormatter()
        result.dateFormat = "m:ss"
        result.timeZone = TimeZone(identifier: "UTC")!
        return result
    }()

    private func renderResendButton(
        button: OWSFlatButton,
        date: Date?,
        enabledString: String,
        countdownFormat: String
    ) {
        guard let date else {
            button.alpha = 0
            button.setEnabled(false)
            return
        }

        button.alpha = 1

        if date <= now {
            button.setEnabled(true)
            button.setTitle(title: enabledString, titleColor: Theme.accentBlueColor)
        } else {
            button.setEnabled(false)
            button.setTitle(
                title: {
                    let timeRemaining = max(date.timeIntervalSince(now), 0)
                    let durationString = retryAfterFormatter.string(from: Date(timeIntervalSinceReferenceDate: timeRemaining))
                    return String(format: countdownFormat, durationString)
                }(),
                titleColor: Theme.secondaryTextAndIconColor
            )
        }
    }

    private func showValidationErrorUiIfNecessary() {
        let oldError = previouslyRenderedValidationError
        let newError = state.validationError

        previouslyRenderedValidationError = newError

        guard let newError, oldError != newError else { return }

        let title: String?
        let message: String
        switch newError {
        case .invalidVerificationCode:
            title = nil
            message = OWSLocalizedString(
                "REGISTRATION_VERIFICATION_ERROR_INVALID_VERIFICATION_CODE",
                comment: "During registration and re-registration, users may have to enter a code to verify ownership of their phone number. If they enter an invalid code, they will see this error message."
            )
        case .smsResendTimeout, .voiceResendTimeout:
            // This isn't the best error message but this should be a rare case. The UI would have
            // to allow the user to request a code that the server would not allow. It could happen
            // if the user changes their clock.
            title = nil
            message = CommonStrings.somethingWentWrongTryAgainLaterError
        case .submitCodeTimeout:
            title = OWSLocalizedString(
                "REGISTRATION_NETWORK_ERROR_TITLE",
                comment: "A network error occurred during registration, and an error is shown to the user. This is the title on that error sheet."
            )
            message = OWSLocalizedString(
                "REGISTRATION_NETWORK_ERROR_BODY",
                comment: "A network error occurred during registration, and an error is shown to the user. This is the body on that error sheet."
            )
        }
        OWSActionSheets.showActionSheet(title: title, message: message)
    }

    // MARK: Events

    @objc
    private func didTapWrongNumberButton() {
        Logger.info("")

        presenter?.returnToPhoneNumberEntry()
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
}

// MARK: - RegistrationVerificationCodeViewDelegate

extension RegistrationVerificationViewController: RegistrationVerificationCodeViewDelegate {
    func codeViewDidChange() {
        if verificationCodeView.isComplete {
            Logger.info("Submitting verification code")
            verificationCodeView.resignFirstResponder()
            presenter?.submitVerificationCode(verificationCodeView.verificationCode)
        }
    }
}
