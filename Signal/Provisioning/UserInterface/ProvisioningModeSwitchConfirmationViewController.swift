//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ProvisioningModeSwitchConfirmationViewController: ProvisioningBaseViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_MODE_SWITCH_TITLE_PROVISIONING",
            comment: "header text indicating to the user they're switching from linking to registering flow",
        ))
        let explanationLabel = UILabel.explanationLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_MODE_SWITCH_EXPLANATION_PROVISIONING",
            comment: "explanation to the user they're switching from linking to registering flow",
        ))

        let imageView = UIImageView(image: UIImage(named: "ipad-primary"))
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingHigh()
        let imageViewContainer = UIView.container()
        imageViewContainer.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: imageViewContainer.topAnchor),
            imageView.leadingAnchor.constraint(greaterThanOrEqualTo: imageViewContainer.leadingAnchor),
            imageView.centerXAnchor.constraint(equalTo: imageViewContainer.centerXAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageViewContainer.bottomAnchor),
        ])

        let nextButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "ONBOARDING_MODE_SWITCH_BUTTON_PROVISIONING",
                comment: "button indicating that the user will register their ipad",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didPressNext()
            },
        )
        nextButton.accessibilityIdentifier = "onboarding.modeSwitch.nextButton"

        let topSpacer = UIView.vStretchingSpacer(minHeight: 12)
        let bottomSpacer = UIView.vStretchingSpacer(minHeight: 12)

        let stackView = addStaticContentStackView(arrangedSubviews: [
            topSpacer,
            titleLabel,
            explanationLabel,
            imageViewContainer,
            bottomSpacer,
            nextButton.enclosedInVerticalStackView(isFullWidthButton: true),
        ])
        stackView.setCustomSpacing(24, after: explanationLabel)

        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor, multiplier: 0.5).isActive = true
    }

    private func didPressNext() {
        let actionSheet = ActionSheetController(message: OWSLocalizedString(
            "ONBOARDING_MODE_SWITCH_WARNING_PROVISIONING",
            comment: "warning to the user that registering an ipad is not recommended",
        ))

        let continueAction = ActionSheetAction(
            title: CommonStrings.continueButton,
            handler: { [weak self] _ in
                guard let self else { return }
                self.provisioningController.switchToPrimaryRegistration(viewController: self)
            },
        )
        actionSheet.addAction(continueAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }
}
