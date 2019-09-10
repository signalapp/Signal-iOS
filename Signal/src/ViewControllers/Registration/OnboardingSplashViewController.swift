//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

@objc
public class OnboardingSplashViewController: OnboardingBaseViewController {

    override public func loadView() {
        super.loadView()

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero

        let titleLabel = self.createTitleLabel(text: NSLocalizedString("Loki Messenger", comment: ""))
        view.addSubview(titleLabel)
        titleLabel.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)
        titleLabel.accessibilityIdentifier = "onboarding.splash." + "titleLabel"

        let lokiLogo = UIImage(named: "LokiLogo")
        let lokiLogoImageView = UIImageView(image: lokiLogo)
        lokiLogoImageView.accessibilityIdentifier = "onboarding.splash." + "lokiLogoImageView"
        lokiLogoImageView.autoSetDimension(.height, toSize: 71)
        lokiLogoImageView.contentMode = .scaleAspectFit
        
        let lokiLogoContainer = UIView()
        view.setContentHuggingVerticalLow()
        view.setCompressionResistanceVerticalLow()
        lokiLogoContainer.addSubview(lokiLogoImageView)
        
        let betaTermsLabel = UILabel()
        betaTermsLabel.text = NSLocalizedString("Loki Messenger is currently in beta. For development purposes the beta version collects basic usage statistics and crash logs. In addition, the beta version doesn't provide full privacy and shouldn't be used to transmit sensitive information.", comment: "")
        betaTermsLabel.textColor = .white
        betaTermsLabel.font = .ows_dynamicTypeSubheadlineClamped
        betaTermsLabel.numberOfLines = 0
        betaTermsLabel.textAlignment = .center
        betaTermsLabel.lineBreakMode = .byWordWrapping
        betaTermsLabel.accessibilityIdentifier = "onboarding.splash." + "betaTermsLabel"
        
        let privacyPolicyLabel = UILabel()
        privacyPolicyLabel.text = NSLocalizedString("Privacy Policy", comment: "")
        privacyPolicyLabel.textColor = .ows_materialBlue
        privacyPolicyLabel.font = .ows_dynamicTypeSubheadlineClamped
        privacyPolicyLabel.numberOfLines = 0
        privacyPolicyLabel.textAlignment = .center
        privacyPolicyLabel.lineBreakMode = .byWordWrapping
        privacyPolicyLabel.isUserInteractionEnabled = true
        privacyPolicyLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(explanationLabelTapped)))
        privacyPolicyLabel.accessibilityIdentifier = "onboarding.splash." + "privacyPolicyLabel"

        let continueButton = self.createButton(title: NSLocalizedString("BUTTON_CONTINUE", comment: "Label for 'continue' button."), selector: #selector(continuePressed))
        view.addSubview(continueButton)
        continueButton.accessibilityIdentifier = "onboarding.splash." + "continueButton"
        
        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            lokiLogoContainer,
            betaTermsLabel,
            UIView.spacer(withHeight: 24),
            privacyPolicyLabel,
            UIView.spacer(withHeight: 24),
            continueButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        stackView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        lokiLogoImageView.autoCenterInSuperview()
    }

     // MARK: - Events

    @objc func explanationLabelTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        guard let url = URL(string: kLegalTermsUrlString) else {
            owsFailDebug("Invalid URL.")
            return
        }
        UIApplication.shared.openURL(url)
    }

    @objc func continuePressed() {
        Logger.info("")

        onboardingController.onboardingSplashDidComplete(viewController: self)
    }
}
