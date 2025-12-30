//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

// MARK: - RegistrationReglockTimeoutAcknowledgeAction

public enum RegistrationReglockTimeoutAcknowledgeAction {
    case resetPhoneNumber
    case close
    // Unable to do anything, just stuck here.
    case none
}

// MARK: - RegistrationReglockTimeoutState

public struct RegistrationReglockTimeoutState: Equatable {
    let reglockExpirationDate: Date
    let acknowledgeAction: RegistrationReglockTimeoutAcknowledgeAction
}

// MARK: - RegistrationReglockTimeoutPresenter

protocol RegistrationReglockTimeoutPresenter: AnyObject {
    func acknowledgeReglockTimeout()
}

// MARK: - RegistrationReglockTimeoutViewController

class RegistrationReglockTimeoutViewController: OWSViewController {
    private let oneMinute: TimeInterval = 60

    init(
        state: RegistrationReglockTimeoutState,
        presenter: RegistrationReglockTimeoutPresenter,
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

    deinit {
        explanationLabelTimer?.invalidate()
        explanationLabelTimer = nil
    }

    // MARK: Internal state

    private let state: RegistrationReglockTimeoutState

    private weak var presenter: RegistrationReglockTimeoutPresenter?

    private var explanationLabelTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_LOCK_TIMEOUT_TITLE",
            comment: "Registration Lock can prevent users from registering in some cases, and they'll have to wait. This is the title of that screen.",
        ))
        titleLabel.accessibilityIdentifier = "registration.reglockTimeout.titleLabel"

        let okayButtonTitle: String
        switch state.acknowledgeAction {
        case .resetPhoneNumber:
            okayButtonTitle = OWSLocalizedString(
                "REGISTRATION_LOCK_TIMEOUT_RESET_PHONE_NUMBER_BUTTON",
                comment: "Registration Lock can prevent users from registering in some cases, and they'll have to wait. This button appears on that screen. Tapping it will bump the user back, earlier in registration, so they can register with a different phone number.",
            )
        case .close, .none:
            okayButtonTitle = CommonStrings.okayButton
        }
        let okayButton = UIButton(
            configuration: .largePrimary(title: okayButtonTitle),
            primaryAction: UIAction { [weak self] _ in
                self?.presenter?.acknowledgeReglockTimeout()
            },
        )

        let learnMoreButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "REGISTRATION_LOCK_TIMEOUT_LEARN_MORE_BUTTON",
                comment: "Registration Lock can prevent users from registering in some cases, and they'll have to wait. This button appears on that screen. Tapping it will tell the user more information.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapLearnMoreButton()
            },
        )
        learnMoreButton.accessibilityIdentifier = "registration.reglockTimeout.learnMoreButton"

        addStaticContentStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            .vStretchingSpacer(),
            [okayButton, learnMoreButton].enclosedInVerticalStackView(isFullWidthButtons: true),
        ])

        updateExplanationLabelText()

        explanationLabelTimer = Timer.scheduledTimer(
            withTimeInterval: oneMinute,
            repeats: true,
        ) { [weak self] _ in
            self?.updateExplanationLabelText()
        }
    }

    // MARK: UI

    private var explanationLabelText: String {
        let format = OWSLocalizedString(
            "REGISTRATION_LOCK_TIMEOUT_DESCRIPTION_FORMAT",
            comment: "Registration Lock can prevent users from registering in some cases, and they'll have to wait. This is the description on that screen, explaining what's going on. Embeds {{ duration }}, such as \"7 days\".",
        )

        let remainingSeconds: UInt32 = {
            let result = state.reglockExpirationDate.timeIntervalSince(Date())
            return UInt32(result <= oneMinute ? oneMinute : result)
        }()

        return String(
            format: format,
            DateUtil.formatDuration(seconds: remainingSeconds, useShortFormat: false),
        )
    }

    private lazy var explanationLabel: UILabel = {
        let result = UILabel.explanationLabelForRegistration(text: explanationLabelText)
        result.accessibilityIdentifier = "registration.reglockTimeout.explanationLabel"
        return result
    }()

    private func updateExplanationLabelText() {
        explanationLabel.text = explanationLabelText
    }

    // MARK: Events

    private func didTapLearnMoreButton() {
        present(SFSafariViewController(url: URL.Support.pin), animated: true)
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationReglockTimeoutPresenter: RegistrationReglockTimeoutPresenter {
    func acknowledgeReglockTimeout() {
        print("acknowledgeReglockTimeout")
    }
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationReglockTimeoutPresenter()
    UINavigationController(
        rootViewController: RegistrationReglockTimeoutViewController(
            state: RegistrationReglockTimeoutState(
                reglockExpirationDate: Date.now.addingTimeInterval(1000),
                acknowledgeAction: .resetPhoneNumber,
            ),
            presenter: presenter,
        ),
    )
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationReglockTimeoutPresenter()
    UINavigationController(
        rootViewController: RegistrationReglockTimeoutViewController(
            state: RegistrationReglockTimeoutState(
                reglockExpirationDate: Date.now.addingTimeInterval(1000),
                acknowledgeAction: .close,
            ),
            presenter: presenter,
        ),
    )
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationReglockTimeoutPresenter()
    UINavigationController(
        rootViewController: RegistrationReglockTimeoutViewController(
            state: RegistrationReglockTimeoutState(
                reglockExpirationDate: Date.now.addingTimeInterval(1000),
                acknowledgeAction: .none,
            ),
            presenter: presenter,
        ),
    )
}

#endif
