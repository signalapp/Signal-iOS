//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

class OnboardingModeSwitchConfirmationViewController: OnboardingBaseViewController {
    var warningText: String?

    override func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleText: String
        let explanationText: String
        let nextButtonText: String
        let image: UIImage?

        switch OnboardingController.defaultOnboardingMode {
        case .registering:
            titleText = NSLocalizedString("ONBOARDING_MODE_SWITCH_TITLE_REGISTERING",
                                          comment: "header text indicating to the user they're switching from registering to linking flow")
            explanationText = NSLocalizedString("ONBOARDING_MODE_SWITCH_EXPLANATION_REGISTERING",
                                                comment: "explanation to the user they're switching from registering to linking flow")

            nextButtonText = NSLocalizedString("ONBOARDING_MODE_SWITCH_BUTTON_REGISTERING",
                                               comment: "button indicating that the user will link their phone")

            warningText = NSLocalizedString("ONBOARDING_MODE_SWITCH_WARNING_REGISTERING",
                                            comment: "warning to the user that linking a phone is not recommended")
            image = nil
        case .provisioning:
            titleText = NSLocalizedString("ONBOARDING_MODE_SWITCH_TITLE_PROVISIONING",
                                          comment: "header text indicating to the user they're switching from linking to registering flow")
            explanationText = NSLocalizedString("ONBOARDING_MODE_SWITCH_EXPLANATION_PROVISIONING",
                                                comment: "explanation to the user they're switching from linking to registering flow")
            nextButtonText = NSLocalizedString("ONBOARDING_MODE_SWITCH_BUTTON_PROVISIONING",
                                               comment: "button indicating that the user will register their ipad")
            warningText = NSLocalizedString("ONBOARDING_MODE_SWITCH_WARNING_PROVISIONING",
                                            comment: "warning to the user that registering an ipad is not recommended")
            image = #imageLiteral(resourceName: "ipad-primary")
        }

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingHigh()

        let titleLabel = self.createTitleLabel(text: titleText)

        let explanationLabel = self.createExplanationLabel(explanationText: explanationText)

        let nextButton = self.primaryButton(title: nextButtonText,
                                            selector: #selector(didPressNext))
        nextButton.accessibilityIdentifier = "onboarding.modeSwitch.nextButton"
        let primaryButtonView = OnboardingBaseViewController.horizontallyWrap(primaryButton: nextButton)

        let topSpacer = UIView.vStretchingSpacer(minHeight: 12)
        let bottomSpacer = UIView.vStretchingSpacer(minHeight: 12)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 12),
            explanationLabel,
            topSpacer,
            imageView,
            bottomSpacer,
            primaryButtonView
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12
        primaryView.addSubview(stackView)

        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        stackView.autoPinEdgesToSuperviewMargins()
    }

    override func shouldShowBackButton() -> Bool {
        return true
    }

    @objc
    func didPressNext() {
        let actionSheet = ActionSheetController(message: warningText)

        let continueAction = ActionSheetAction(
            title: CommonStrings.continueButton,
            accessibilityIdentifier: "onboarding.modeSwitch.continue",
            handler: { [weak self] _ in
                guard let self else { return }
                self.onboardingController.overrideDefaultRegistrationMode(viewController: self)
            }
        )
        actionSheet.addAction(continueAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }
}
