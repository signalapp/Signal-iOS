//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

public struct RegistrationPinAttemptsExhaustedViewState: Equatable {
    public enum Mode: Equatable {
        /// We've already registered and were attempting to restore backups from kbs
        /// but ran out of guesses; we can proceed without backups.
        case restoringBackup
        /// We were attempting to use the PIN to bypass sms-based registration.
        /// We may or may not need the PIN for reglock later; for now we can fall back
        /// to sms based verification.
        case restoringRegistrationRecoveryPassword
    }

    public let mode: Mode
}

// MARK: - RegistrationPinAttemptsExhaustedAndMustCreateNewPinPresenter

protocol RegistrationPinAttemptsExhaustedAndMustCreateNewPinPresenter: AnyObject {
    func acknowledgePinGuessesExhausted()
}

// MARK: - RegistrationPinAttemptsExhaustedAndMustCreateNewPinViewController

class RegistrationPinAttemptsExhaustedAndMustCreateNewPinViewController: OWSViewController {
    private var state: RegistrationPinAttemptsExhaustedViewState

    init(
        state: RegistrationPinAttemptsExhaustedViewState,
        presenter: RegistrationPinAttemptsExhaustedAndMustCreateNewPinPresenter,
    ) {
        self.state = state
        self.presenter = presenter

        super.init()

        navigationItem.hidesBackButton = true
    }

    func updateState(_ newState: RegistrationPinAttemptsExhaustedViewState) {
        self.state = newState
        self.configure()
    }

    @available(*, unavailable)
    override init() {
        owsFail("This should not be called")
    }

    // MARK: Internal state

    private weak var presenter: RegistrationPinAttemptsExhaustedAndMustCreateNewPinPresenter?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_TITLE",
            comment: "Title of the 'onboarding pin attempts exhausted' view when reglock is disabled.",
        ))
        titleLabel.accessibilityIdentifier = "registration.pinAttemptsExhausted.titleLabel"

        let learnMoreButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_LEARN_MORE",
                comment: "Label for the 'learn more' link when reglock is disabled in the 'onboarding pin attempts exhausted' view.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapLearnMoreButton()
            },
        )
        learnMoreButton.accessibilityIdentifier = "registration.pinAttemptsExhausted.learnMoreButton"

        addStaticContentStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            .vStretchingSpacer(),
            [continueButton, learnMoreButton].enclosedInVerticalStackView(isFullWidthButtons: true),
        ])

        configure()
    }

    // MARK: UI

    private lazy var explanationLabel: UILabel = {
        let result = UILabel.explanationLabelForRegistration(text: "")
        result.accessibilityIdentifier = "registration.pinAttemptsExhausted.explanationLabel"
        return result
    }()

    private lazy var continueButton = UIButton(
        configuration: .largePrimary(title: ""),
        primaryAction: UIAction { [weak self] _ in
            self?.presenter?.acknowledgePinGuessesExhausted()
        },
    )

    private func configure() {
        switch state.mode {
        case .restoringBackup:
            explanationLabel.text = OWSLocalizedString(
                "ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_EXPLANATION",
                comment: "Explanation of the 'onboarding pin attempts exhausted' view when reglock is disabled.",
            )
            continueButton.configuration?.title = OWSLocalizedString(
                "ONBOARDING_2FA_CREATE_NEW_PIN",
                comment: "Label for the 'create new pin' button when reglock is disabled during onboarding.",
            )
        case .restoringRegistrationRecoveryPassword:
            explanationLabel.text = OWSLocalizedString(
                "ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_WITH_UNKNOWN_REGLOCK_EXPLANATION",
                comment: "Explanation of the 'onboarding pin attempts exhausted' view when it is unknown if reglock is enabled.",
            )
            continueButton.configuration?.title = CommonStrings.continueButton
        }
    }

    // MARK: Events

    private func didTapLearnMoreButton() {
        present(SFSafariViewController(url: URL.Support.pin), animated: true)
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationPinAttemptsExhaustedAndMustCreateNewPinPresenter: RegistrationPinAttemptsExhaustedAndMustCreateNewPinPresenter {
    func acknowledgePinGuessesExhausted() {
        print("acknowledgePinGuessesExhausted")
    }
}

@available(iOS 17, *)
#Preview("Create New PIN") {
    let presenter = PreviewRegistrationPinAttemptsExhaustedAndMustCreateNewPinPresenter()
    return UINavigationController(
        rootViewController: RegistrationPinAttemptsExhaustedAndMustCreateNewPinViewController(
            state: RegistrationPinAttemptsExhaustedViewState(mode: .restoringBackup),
            presenter: presenter,
        ),
    )
}

@available(iOS 17, *)
#Preview("Verify Phone Number") {
    let presenter = PreviewRegistrationPinAttemptsExhaustedAndMustCreateNewPinPresenter()
    return UINavigationController(
        rootViewController: RegistrationPinAttemptsExhaustedAndMustCreateNewPinViewController(
            state: RegistrationPinAttemptsExhaustedViewState(mode: .restoringRegistrationRecoveryPassword),
            presenter: presenter,
        ),
    )
}

#endif
