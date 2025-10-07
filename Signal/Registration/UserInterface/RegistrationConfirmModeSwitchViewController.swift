//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol RegistrationConfimModeSwitchPresenter: AnyObject {
    func confirmSwitchToDeviceLinkingMode()
}

class RegistrationConfirmModeSwitchViewController: OWSViewController {
    weak var presenter: RegistrationConfimModeSwitchPresenter?

    public init(presenter: RegistrationConfimModeSwitchPresenter) {
        self.presenter = presenter
        super.init()
    }

    private var titleText: String {
        OWSLocalizedString(
            "ONBOARDING_MODE_SWITCH_TITLE_REGISTERING",
            comment: "header text indicating to the user they're switching from registering to linking flow"
        )
    }

    private var subtitleText: String {
        OWSLocalizedString(
            "ONBOARDING_MODE_SWITCH_EXPLANATION_REGISTERING",
            comment: "explanation to the user they're switching from registering to linking flow"
        )
    }

    private var warningText: String {
        OWSLocalizedString(
            "ONBOARDING_MODE_SWITCH_WARNING_REGISTERING",
            comment: "warning to the user that linking a phone is not recommended"
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        let titleLabel = UILabel.titleLabelForRegistration(text: titleText)
        let explanationLabel = UILabel.explanationLabelForRegistration(text: subtitleText)

        let nextButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "ONBOARDING_MODE_SWITCH_BUTTON_REGISTERING",
                comment: "button indicating that the user will link their phone"
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didPressNext()
            }
        )
        nextButton.accessibilityIdentifier = "onboarding.modeSwitch.nextButton"

        let buttonContainer = UIView.container()
        buttonContainer.addSubview(nextButton)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nextButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            nextButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            nextButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor, constant: 22),
            nextButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: -16),
        ])

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            UIView.vStretchingSpacer(minHeight: 36),
            buttonContainer
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.preservesSuperviewLayoutMargins = true
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func didPressNext() {
        let actionSheet = ActionSheetController(message: warningText)

        let continueAction = ActionSheetAction(
            title: CommonStrings.continueButton,
            handler: { [weak self] _ in
                self?.presenter?.confirmSwitchToDeviceLinkingMode()
            }
        )
        actionSheet.addAction(continueAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }
}
