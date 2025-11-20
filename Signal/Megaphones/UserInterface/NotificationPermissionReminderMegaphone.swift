//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class NotificationPermissionReminderMegaphone: MegaphoneView {
    weak var actionSheetController: ActionSheetController?

    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString("NOTIFICATION_PERMISSION_REMINDER_MEGAPHONE_TITLE",
                                      comment: "Title for notification permission reminder megaphone")
        bodyText = OWSLocalizedString("NOTIFICATION_PERMISSION_REMINDER_MEGAPHONE_BODY",
                                     comment: "Body for notification permission reminder megaphone")
        imageName = "notificationMegaphone"

        let primaryButtonTitle = OWSLocalizedString("NOTIFICATION_PERMISSION_REMINDER_MEGAPHONE_ACTION",
                                                   comment: "Action text for notification permission reminder megaphone")

        let primaryButton = MegaphoneView.Button(title: primaryButtonTitle) { [weak self] in
            guard let self = self else { return }

            let turnOnView = TurnOnPermissionView(
                title: OWSLocalizedString(
                    "NOTIFICATION_PERMISSION_ACTION_SHEET_TITLE",
                    comment: "Title for notification permission action sheet"
                ),
                message: OWSLocalizedString(
                    "NOTIFICATION_PERMISSION_ACTION_SHEET_BODY",
                    comment: "Body for notification permission action sheet"
                ),
                steps: [
                    .init(
                        icon: nil,
                        text: OWSLocalizedString(
                            "NOTIFICATION_PERMISSION_ACTION_SHEET_STEP_ONE",
                            comment: "First step for notification permission action sheet"
                        )
                    ),
                    .init(
                        icon: #imageLiteral(resourceName: "notifications-32"),
                        text: OWSLocalizedString(
                            "NOTIFICATION_PERMISSION_ACTION_SHEET_STEP_TWO",
                            comment: "Second step for notification permission action sheet"
                        )
                    ),
                    .init(
                        icon: UIImage(imageLiteralResourceName: "toggle-32"),
                        text: OWSLocalizedString(
                            "NOTIFICATION_PERMISSION_ACTION_SHEET_STEP_THREE",
                            comment: "Third step for notification permission action sheet"
                        )
                    )
                ]
            )

            let actionSheetController = ActionSheetController()
            actionSheetController.customHeader = turnOnView
            actionSheetController.isCancelable = true
            fromViewController.presentActionSheet(actionSheetController)
            self.actionSheetController = actionSheetController
        }

        let secondaryButton = snoozeButton(
            fromViewController: fromViewController,
            snoozeTitle: OWSLocalizedString("NOTIFICATION_PERMISSION_NOT_NOW_ACTION",
                                           comment: "Snooze action text for contact permission reminder megaphone")
        )
        setButtons(primary: primaryButton, secondary: secondaryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        super.dismiss(animated: animated, completion: completion)
        actionSheetController?.dismiss(animated: animated)
    }
}

class TurnOnPermissionView: UIStackView {
    struct Step {
        let icon: UIImage?
        let text: String
    }

    init(title: String, message: String, steps: [Step], button: UIButton? = nil) {
        super.init(frame: .zero)

        axis = .vertical
        spacing = 24 // spacing between steps
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 8, bottom: 16, trailing: 8)

        // Title
        let titleLabel = UILabel.titleLabelForRegistration(text: title)
        addArrangedSubview(titleLabel)
        setCustomSpacing(12, after: titleLabel)

        // Subtitle
        let subtitleLabel = UILabel.explanationLabelForRegistration(text: message)
        addArrangedSubview(subtitleLabel)
        setCustomSpacing(32, after: subtitleLabel)

        // Steps
        for (index, step) in steps.enumerated() {
            addStepStack(step: step, number: index + 1)
        }

        // Button
        let primaryButton = button ?? UIButton(
            configuration: .largePrimary(title: CommonStrings.goToSettingsButton),
            primaryAction: UIAction { [weak self] _ in
                self?.goToSettings()
            }
        )
        let buttonContainer = UIView.container()
        buttonContainer.addSubview(primaryButton)
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            primaryButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            primaryButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor, constant: 22),
            primaryButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            primaryButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
        ])
        addArrangedSubview(buttonContainer)
    }

    private func goToSettings() {
        UIApplication.shared.openSystemSettings()
    }

    private var lastNumberLabel: UIView?

    @discardableResult
    private func addStepStack(step: Step, number: Int) -> UIView {
        let imageSize: CGFloat = 32

        let stepStack = UIStackView()
        stepStack.axis = .horizontal
        stepStack.spacing = 8
        stepStack.alignment = .top
        stepStack.translatesAutoresizingMaskIntoConstraints = false

        let numberLabel = UILabel()
        numberLabel.text = "\(number)" + "."
        numberLabel.textColor = .Signal.label
        numberLabel.font = .dynamicTypeBodyClamped
        numberLabel.textAlignment = .right
        numberLabel.setContentHuggingHorizontalHigh()
        numberLabel.setCompressionResistanceHorizontalHigh()
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: imageSize).isActive = true
        stepStack.addArrangedSubview(numberLabel)

        if let icon = step.icon {
            let iconView = UIImageView()
            iconView.image = icon
            iconView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: imageSize),
                iconView.heightAnchor.constraint(equalToConstant: imageSize),
            ])
            stepStack.addArrangedSubview(iconView)
        }

        let stepLabel = UILabel()
        stepLabel.text = step.text
        stepLabel.textColor = .Signal.label
        stepLabel.font = .dynamicTypeBodyClamped
        stepLabel.numberOfLines = 0
        stepLabel.setContentHuggingHorizontalLow()
        stepLabel.translatesAutoresizingMaskIntoConstraints = false
        stepLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: imageSize).isActive = true
        stepStack.addArrangedSubview(stepLabel)

        addArrangedSubview(stepStack)

        if let lastNumberLabel {
            lastNumberLabel.widthAnchor.constraint(equalTo: numberLabel.widthAnchor).isActive = true
        }
        lastNumberLabel = numberLabel

        return stepStack
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
