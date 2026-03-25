//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ProvisioningModeSwitchConfirmationViewController: ProvisioningBaseViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let imageView = UIImageView(image: .onboardingSplashHero)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.setCompressionResistanceLow()
        imageView.setContentHuggingVerticalLow()
        let imageViewContainer = UIView.container()
        imageViewContainer.addSubview(imageView)
        // Center image vertically in the available space above title text.
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: imageViewContainer.centerXAnchor),
            imageView.widthAnchor.constraint(equalTo: imageViewContainer.widthAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageViewContainer.centerYAnchor),
            imageView.heightAnchor.constraint(equalTo: imageViewContainer.heightAnchor, constant: 0.8),
        ])

        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_MODE_SWITCH_TITLE_PROVISIONING",
            comment: "header text indicating to the user they're switching from linking to registering flow",
        ))
        let explanationLabel = UILabel.explanationLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_MODE_SWITCH_EXPLANATION_PROVISIONING",
            comment: "explanation to the user they're switching from linking to registering flow",
        ))

        let nextButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "ONBOARDING_MODE_SWITCH_BUTTON_PROVISIONING",
                comment: "button indicating that the user will register their ipad",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didPressNext()
            },
        )

        let stackView = addStaticContentStackView(arrangedSubviews: [
            imageViewContainer,
            titleLabel,
            explanationLabel,
            nextButton.enclosedInVerticalStackView(isFullWidthButton: true),
        ])
        stackView.setCustomSpacing(44, after: imageViewContainer)
        stackView.setCustomSpacing(16, after: titleLabel)
        stackView.setCustomSpacing(82, after: explanationLabel)
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
