//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit
import SafariServices

@objc
public class OnboardingSplashViewController: OnboardingBaseViewController {

    let modeSwitchButton = UIButton()

    override var primaryLayoutMargins: UIEdgeInsets {
        var defaultMargins = super.primaryLayoutMargins
        // we want the hero image a bit closer to the top than most
        // onboarding content
        defaultMargins.top = 16
        return defaultMargins
    }

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.addSubview(modeSwitchButton)
        modeSwitchButton.setTemplateImageName(
            OnboardingController.defaultOnboardingMode == .registering ? "link-24" : "link-broken-24",
            tintColor: .ows_gray25
        )
        modeSwitchButton.autoSetDimensions(to: CGSize(square: 40))
        modeSwitchButton.autoPinEdge(toSuperviewMargin: .trailing)
        modeSwitchButton.autoPinEdge(toSuperviewMargin: .top)
        modeSwitchButton.addTarget(self, action: #selector(didTapModeSwitch), for: .touchUpInside)
        modeSwitchButton.accessibilityIdentifier = "onboarding.splash.modeSwitch"

        modeSwitchButton.isHidden = !UIDevice.current.isIPad && !FeatureFlags.linkedPhones

        view.backgroundColor = Theme.backgroundColor

        let heroImage = UIImage(named: "onboarding_splash_hero")
        let heroImageView = UIImageView(image: heroImage)
        heroImageView.contentMode = .scaleAspectFit
        heroImageView.layer.minificationFilter = .trilinear
        heroImageView.layer.magnificationFilter = .trilinear
        heroImageView.setCompressionResistanceLow()
        heroImageView.setContentHuggingVerticalLow()
        heroImageView.accessibilityIdentifier = "onboarding.splash." + "heroImageView"

        let titleLabel = self.titleLabel(text: NSLocalizedString("ONBOARDING_SPLASH_TITLE", comment: "Title of the 'onboarding splash' view."))
        primaryView.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.splash." + "titleLabel"

        let explanationLabel = UILabel()
        explanationLabel.text = NSLocalizedString("ONBOARDING_SPLASH_TERM_AND_PRIVACY_POLICY",
                                                  comment: "Link to the 'terms and privacy policy' in the 'onboarding splash' view.")
        explanationLabel.textColor = Theme.accentBlueColor
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.isUserInteractionEnabled = true
        explanationLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(explanationLabelTapped)))
        explanationLabel.accessibilityIdentifier = "onboarding.splash." + "explanationLabel"

        let continueButton = self.primaryButton(title: CommonStrings.continueButton,
                                                    selector: #selector(continuePressed))
        continueButton.accessibilityIdentifier = "onboarding.splash." + "continueButton"
        let primaryButtonView = OnboardingBaseViewController.horizontallyWrap(primaryButton: continueButton)

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

    // MARK: - Events

    @objc func didTapModeSwitch() {
        Logger.info("")

        onboardingController.onboardingSplashRequestedModeSwitch(viewController: self)
    }

    @objc func explanationLabelTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        guard let url = URL(string: kLegalTermsUrlString) else {
            owsFailDebug("Invalid URL.")
            return
        }
        let safariVC = SFSafariViewController(url: url)
        present(safariVC, animated: true)
    }

    @objc func continuePressed() {
        Logger.info("")

        onboardingController.onboardingSplashDidComplete(viewController: self)
    }
}
