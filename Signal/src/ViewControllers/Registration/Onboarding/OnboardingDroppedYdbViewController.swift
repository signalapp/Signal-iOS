//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

@objc
public class OnboardingDroppedYdbViewController: OnboardingBaseViewController {

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let heroImageView = UIImageView.withTemplateImageName("signal-logo-128",
                                                              tintColor: .ows_accentBlue)
        heroImageView.autoSetDimensions(to: .square(100))
        heroImageView.setContentHuggingHigh()

        let titleLabel = self.createTitleLabel(text: NSLocalizedString("ONBOARDING_DROPPED_YDB_TITLE",
                                                                       comment: "Title of the 'onboarding after dropped YDB' view."))
        primaryView.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.droppedYdb." + "titleLabel"

        let explanationLabel = UILabel()
        explanationLabel.text = NSLocalizedString("ONBOARDING_DROPPED_YDB_EXPLANATION",
                                                  comment: "Explanation on the 'onboarding after dropped YDB' view.")
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.accessibilityIdentifier = "onboarding.droppedYdb." + "explanationLabel"

        let nextButton = self.primaryButton(title: CommonStrings.nextButton,
                                            selector: #selector(nextPressed))
        nextButton.accessibilityIdentifier = "onboarding.droppedYdb." + "nextButton"
        let primaryButtonView = OnboardingBaseViewController.horizontallyWrap(primaryButton: nextButton)

        let topStack = UIStackView(arrangedSubviews: [
            heroImageView,
            UIView.spacer(withHeight: 28),
            titleLabel,
            UIView.spacer(withHeight: 12),
            explanationLabel
        ])
        topStack.axis = .vertical
        topStack.alignment = .center

        let topVSpacer = UIView.vStretchingSpacer()
        let bottomVSpacer = UIView.vStretchingSpacer()

        let stackView = UIStackView(arrangedSubviews: [
            topVSpacer,
            topStack,
            bottomVSpacer,
            primaryButtonView
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill

        primaryView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        topVSpacer.autoMatch(.height, to: .height, of: bottomVSpacer)
    }

    // MARK: - Events

    @objc
    func nextPressed() {
        Logger.info("")

        SSKPreferences.setDidDropYdb(false)

        let splash = OnboardingSplashViewController(onboardingController: onboardingController)
        navigationController?.setViewControllers([splash], animated: true)
    }
}
