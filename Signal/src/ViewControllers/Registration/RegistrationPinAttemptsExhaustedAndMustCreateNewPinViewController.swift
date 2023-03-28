//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalMessaging

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
    private var learnMoreURL: URL { URL(string: "https://support.signal.org/hc/articles/360007059792")! }

    private var state: RegistrationPinAttemptsExhaustedViewState

    public init(
        state: RegistrationPinAttemptsExhaustedViewState,
        presenter: RegistrationPinAttemptsExhaustedAndMustCreateNewPinPresenter
    ) {
        self.state = state
        self.presenter = presenter

        super.init()
    }

    public func updateState(_ newState: RegistrationPinAttemptsExhaustedViewState) {
        self.state = newState
        self.render()
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    // MARK: Internal state

    private weak var presenter: RegistrationPinAttemptsExhaustedAndMustCreateNewPinPresenter?

    public override func viewDidLoad() {
        super.viewDidLoad()
        initialRender()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    // MARK: Rendering

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_TITLE",
            comment: "Title of the 'onboarding pin attempts exhausted' view when reglock is disabled."
        ))
        result.accessibilityIdentifier = "registration.pinAttemptsExhausted.titleLabel"
        return result
    }()

    private lazy var explanationLabel: UILabel = {
        let result = UILabel.explanationLabelForRegistration(text: "")
        result.accessibilityIdentifier = "registration.pinAttemptsExhausted.explanationLabel"
        return result
    }()

    private lazy var continueButton: OWSButton = {
        let result = OWSButton(title: "") { [weak self] in
            self?.presenter?.acknowledgePinGuessesExhausted()
        }
        result.dimsWhenHighlighted = true
        result.layer.cornerRadius = 8
        result.backgroundColor = .ows_accentBlue
        result.titleLabel?.font = UIFont.ows_dynamicTypeBody.ows_semibold
        result.titleLabel?.numberOfLines = 0
        result.contentEdgeInsets = .init(margin: 14)
        result.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)
        return result
    }()

    private lazy var learnMoreButton: OWSFlatButton = {
        let result = OWSFlatButton.button(
            title: OWSLocalizedString(
                "ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_LEARN_MORE",
                comment: "Label for the 'learn more' link when reglock is disabled in the 'onboarding pin attempts exhausted' view."
            ),
            font: UIFont.ows_dynamicTypeBody.ows_semibold,
            titleColor: Theme.accentBlueColor,
            backgroundColor: .clear,
            target: self,
            selector: #selector(didTapLearnMoreButton)
        )
        result.accessibilityIdentifier = "registration.pinAttemptsExhausted.learnMoreButton"
        return result
    }()

    private func initialRender() {
        navigationItem.setHidesBackButton(true, animated: false)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.layoutMargins = UIEdgeInsets.layoutMarginsForRegistration(
            traitCollection.horizontalSizeClass
        )
        stackView.isLayoutMarginsRelativeArrangement = true

        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(12, after: titleLabel)

        stackView.addArrangedSubview(explanationLabel)

        stackView.addArrangedSubview(UIView.vStretchingSpacer())

        stackView.addArrangedSubview(continueButton)
        stackView.setCustomSpacing(24, after: continueButton)

        stackView.addArrangedSubview(learnMoreButton)

        render()
    }

    private func render() {
        view.backgroundColor = Theme.backgroundColor
        titleLabel.textColor = Theme.primaryTextColor
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        learnMoreButton.setTitleColor(Theme.accentBlueColor)

        switch state.mode {
        case .restoringBackup:
            explanationLabel.text = OWSLocalizedString(
                "ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_EXPLANATION",
                comment: "Explanation of the 'onboarding pin attempts exhausted' view when reglock is disabled."
            )
            continueButton.setTitle(
                OWSLocalizedString(
                    "ONBOARDING_2FA_CREATE_NEW_PIN",
                    comment: "Label for the 'create new pin' button when reglock is disabled during onboarding."
                ),
                for: .normal
            )
        case .restoringRegistrationRecoveryPassword:
            explanationLabel.text = OWSLocalizedString(
                "ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_WITH_UNKNOWN_REGLOCK_EXPLANATION",
                comment: "Explanation of the 'onboarding pin attempts exhausted' view when it is unknown if reglock is enabled."
            )
            continueButton.setTitle(CommonStrings.continueButton, for: .normal)
        }
    }

    // MARK: Events

    @objc
    private func didTapLearnMoreButton() {
        present(SFSafariViewController(url: self.learnMoreURL), animated: true)
    }
}
