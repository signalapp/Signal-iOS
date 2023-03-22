//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalMessaging

// MARK: - RegistrationReglockTimeoutAcknowledgeAction

public enum RegistrationReglockTimeoutAcknowledgeAction {
    case resetPhoneNumber
    case close
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
    private var learnMoreURL: URL { URL(string: "https://support.signal.org/hc/articles/360007059792")! }

    private let oneMinute: TimeInterval = 60

    public init(
        state: RegistrationReglockTimeoutState,
        presenter: RegistrationReglockTimeoutPresenter
    ) {
        self.state = state
        self.presenter = presenter

        super.init()
    }

    @available(*, unavailable)
    public override init() {
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

    public override func viewDidLoad() {
        super.viewDidLoad()

        initialRender()

        explanationLabelTimer = Timer.scheduledTimer(
            withTimeInterval: oneMinute,
            repeats: true
        ) { [weak self] _ in
            self?.renderExplanationLabelText()
        }
    }

    public override func themeDidChange() {
        super.themeDidChange()
        renderColors()
    }

    // MARK: Rendering

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_LOCK_TIMEOUT_TITLE",
            comment: "Registration Lock can prevent users from registering in some cases, and they'll have to wait. This is the title of that screen."
        ))
        result.accessibilityIdentifier = "registration.reglockTimeout.titleLabel"
        return result
    }()

    private var explanationLabelText: String {
        let format = OWSLocalizedString(
            "REGISTRATION_LOCK_TIMEOUT_DESCRIPTION_FORMAT",
            comment: "Registration Lock can prevent users from registering in some cases, and they'll have to wait. This is the description on that screen, explaining what's going on. Embeds {{ duration }}, such as \"7 days\"."
        )

        let remainingSeconds: UInt32 = {
            let result = state.reglockExpirationDate.timeIntervalSince(Date())
            return UInt32(result <= oneMinute ? oneMinute : result)
        }()

        return String(
            format: format,
            DateUtil.formatDuration(seconds: remainingSeconds, useShortFormat: false)
        )
    }

    private lazy var explanationLabel: UILabel = {
        let result = UILabel.explanationLabelForRegistration(text: explanationLabelText)
        result.accessibilityIdentifier = "registration.reglockTimeout.explanationLabel"
        return result
    }()

    private lazy var okayButton: UIView = {
        let title: String
        switch state.acknowledgeAction {
        case .resetPhoneNumber:
            title = OWSLocalizedString(
                "REGISTRATION_LOCK_TIMEOUT_RESET_PHONE_NUMBER_BUTTON",
                comment: "Registration Lock can prevent users from registering in some cases, and they'll have to wait. This button appears on that screen. Tapping it will bump the user back, earlier in registration, so they can register with a different phone number."
            )
        case .close:
            title = CommonStrings.okayButton
        }

        let result = OWSButton(title: title) { [weak self] in
            self?.presenter?.acknowledgeReglockTimeout()
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
                "REGISTRATION_LOCK_TIMEOUT_LEARN_MORE_BUTTON",
                comment: "Registration Lock can prevent users from registering in some cases, and they'll have to wait. This button appears on that screen. Tapping it will tell the user more information."
            ),
            font: UIFont.ows_dynamicTypeBody.ows_semibold,
            titleColor: Theme.accentBlueColor,
            backgroundColor: .clear,
            target: self,
            selector: #selector(didTapLearnMoreButton)
        )
        result.accessibilityIdentifier = "registration.reglockTimeout.learnMoreButton"
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

        stackView.addArrangedSubview(okayButton)
        stackView.setCustomSpacing(24, after: okayButton)

        stackView.addArrangedSubview(learnMoreButton)

        renderExplanationLabelText()
        renderColors()
    }

    private func renderExplanationLabelText() {
        explanationLabel.text = explanationLabelText
    }

    private func renderColors() {
        view.backgroundColor = Theme.backgroundColor
        titleLabel.textColor = Theme.primaryTextColor
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        learnMoreButton.setTitleColor(Theme.accentBlueColor)
    }

    // MARK: Events

    @objc
    private func didTapLearnMoreButton() {
        present(SFSafariViewController(url: self.learnMoreURL), animated: true)
    }
}
