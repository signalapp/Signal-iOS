//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI
import UIKit

class ProvisioningSplashViewController: ProvisioningBaseViewController {

    override var primaryLayoutMargins: UIEdgeInsets {
        var defaultMargins = super.primaryLayoutMargins
        // we want the hero image a bit closer to the top than most
        // onboarding content
        defaultMargins.top = 16
        return defaultMargins
    }

    override func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        let modeSwitchButton = UIButton()
        view.addSubview(modeSwitchButton)
        modeSwitchButton.setTemplateImageName(
            "link-slash",
            tintColor: .ows_gray25
        )
        modeSwitchButton.autoSetDimensions(to: CGSize(square: 40))
        modeSwitchButton.autoPinEdge(toSuperviewMargin: .trailing)
        modeSwitchButton.autoPinEdge(toSuperviewMargin: .top)
        modeSwitchButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.provisioningController.provisioningSplashRequestedModeSwitch(viewController: self)
        }, for: .touchUpInside)
        modeSwitchButton.accessibilityIdentifier = "onboarding.splash.modeSwitch"

        view.backgroundColor = Theme.backgroundColor

        let heroImage = UIImage(named: "onboarding_splash_hero")
        let heroImageView = UIImageView(image: heroImage)
        heroImageView.contentMode = .scaleAspectFit
        heroImageView.layer.minificationFilter = .trilinear
        heroImageView.layer.magnificationFilter = .trilinear
        heroImageView.setCompressionResistanceLow()
        heroImageView.setContentHuggingVerticalLow()
        heroImageView.accessibilityIdentifier = "onboarding.splash." + "heroImageView"

        let titleLabel = self.createTitleLabel(text: OWSLocalizedString("ONBOARDING_SPLASH_TITLE", comment: "Title of the 'onboarding splash' view."))
        primaryView.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.splash." + "titleLabel"

        if !TSConstants.isUsingProductionService {
            titleLabel.text = "Internal Staging Build" + "\n" + "\(AppVersionImpl.shared.currentAppVersion)"
        }

        let explanationLabel = UILabel()
        explanationLabel.text = OWSLocalizedString("ONBOARDING_SPLASH_TERM_AND_PRIVACY_POLICY",
                                                  comment: "Link to the 'terms and privacy policy' in the 'onboarding splash' view.")
        explanationLabel.textColor = Theme.accentBlueColor
        explanationLabel.font = UIFont.dynamicTypeSubheadlineClamped
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.isUserInteractionEnabled = true
        explanationLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(explanationLabelTapped)))
        explanationLabel.accessibilityIdentifier = "onboarding.splash." + "explanationLabel"

        let continueButton = self.primaryButton(title: CommonStrings.continueButton, action: .init(handler: { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.provisioningController.provisioningSplashDidComplete(viewController: self)
            }
        }))
        continueButton.accessibilityIdentifier = "onboarding.splash." + "continueButton"
        let primaryButtonView = ProvisioningBaseViewController.horizontallyWrap(primaryButton: continueButton)

        let stackView = UIStackView(arrangedSubviews: [
            heroImageView,
            UIView.spacer(withHeight: 22),
            titleLabel,
            UIView.spacer(withHeight: 92),
            explanationLabel,
            UIView.spacer(withHeight: 24),
            primaryButtonView
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill

        primaryView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
    }

    override func shouldShowBackButton() -> Bool {
        return false
    }

    // MARK: - Events

    @objc
    private func explanationLabelTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        let url = TSConstants.legalTermsUrl
        let safariVC = SFSafariViewController(url: url)
        present(safariVC, animated: true)
    }
}
