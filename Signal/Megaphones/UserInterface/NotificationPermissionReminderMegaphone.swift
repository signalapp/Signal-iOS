//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class NotificationPermissionReminderMegaphone: MegaphoneView {
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

final class TurnOnPermissionView: UIStackView {
    struct Step {
        let icon: UIImage?
        let text: String
    }

    init(title: String, message: String, steps: [Step], button: OWSFlatButton? = nil) {
        super.init(frame: .zero)

        addBackgroundView(withBackgroundColor: Theme.actionSheetBackgroundColor)
        axis = .vertical
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 32, leading: 32, bottom: 16, trailing: 32)

        addArrangedSubview(titleLabel(text: title))
        addArrangedSubview(.spacer(withHeight: 8))
        addArrangedSubview(explanationLabel(explanationText: message))

        addArrangedSubview(.spacer(withHeight: 32))

        for (index, step) in steps.enumerated() {
            addStepStack(step: step, number: index + 1)
        }

        addArrangedSubview(.spacer(withHeight: 8))

        let button = button ?? self.button(title: CommonStrings.goToSettingsButton, selector: #selector(goToSettings))

        addArrangedSubview(button)
    }

    @objc
    func goToSettings() {
        UIApplication.shared.openSystemSettings()
    }

    func titleLabel(text: String) -> UILabel {
        let titleLabel = UILabel()
        titleLabel.text = text
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = UIFont.dynamicTypeTitle2.semibold()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        titleLabel.setCompressionResistanceVerticalHigh()
        titleLabel.setContentHuggingVerticalHigh()
        return titleLabel
    }

    func explanationLabel(explanationText: String) -> UILabel {
        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.font = .dynamicTypeSubheadline
        explanationLabel.text = explanationText
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.setCompressionResistanceVerticalHigh()
        explanationLabel.setContentHuggingVerticalHigh()
        return explanationLabel
    }

    func button(title: String, selector: Selector) -> OWSFlatButton {
        let font = UIFont.dynamicTypeBodyClamped.semibold()
        let buttonHeight = OWSFlatButton.heightForFont(font)
        let button = OWSFlatButton.button(title: title,
                                          font: font,
                                          titleColor: .white,
                                          backgroundColor: .ows_accentBlue,
                                          target: self,
                                          selector: selector)
        button.autoSetDimension(.height, toSize: buttonHeight)
        return button
    }

    private var lastNumberLabelContainer: UIView?
    func addStepStack(step: Step, number: Int) {
        let stepStack = UIStackView()
        stepStack.axis = .horizontal
        stepStack.spacing = 8

        addArrangedSubview(stepStack)
        addArrangedSubview(.spacer(withHeight: 24))

        let numberLabel = UILabel()
        numberLabel.text = "\(number)" + "."
        numberLabel.textColor = Theme.primaryTextColor
        numberLabel.font = .dynamicTypeBodyClamped
        numberLabel.textAlignment = .right

        let numberLabelContainer = UIView()
        numberLabelContainer.addSubview(numberLabel)
        numberLabel.autoPinWidthToSuperview()
        numberLabel.autoPinEdge(toSuperviewEdge: .top)
        numberLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 0, relation: .lessThanOrEqual)
        numberLabel.autoSetDimension(.height, toSize: 32, relation: .greaterThanOrEqual)

        stepStack.addArrangedSubview(numberLabelContainer)

        lastNumberLabelContainer?.autoMatch(.width, to: .width, of: numberLabelContainer)
        lastNumberLabelContainer = numberLabelContainer

        if let icon = step.icon {
            let iconView = UIImageView()
            iconView.image = icon

            let iconViewContainer = UIView()
            iconViewContainer.addSubview(iconView)
            iconView.autoPinWidthToSuperview()
            iconView.autoPinEdge(toSuperviewEdge: .top)
            iconView.autoSetDimensions(to: CGSize(square: 32))

            stepStack.addArrangedSubview(iconViewContainer)
        }

        let stepLabel = UILabel()
        stepLabel.text = step.text
        stepLabel.textColor = Theme.primaryTextColor
        stepLabel.font = .dynamicTypeBodyClamped
        stepLabel.setCompressionResistanceHorizontalHigh()
        stepLabel.setContentHuggingHorizontalLow()
        stepLabel.autoSetDimension(.height, toSize: 32, relation: .greaterThanOrEqual)

        stepStack.addArrangedSubview(stepLabel)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
