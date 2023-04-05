//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SafariServices
import SignalMessaging

// MARK: - RegistrationSplashPresenter

public protocol RegistrationSplashPresenter: AnyObject {
    func continueFromSplash()

    func switchToDeviceLinkingMode()
}

// MARK: - RegistrationSplashViewController

public class RegistrationSplashViewController: OWSViewController {

    private weak var presenter: RegistrationSplashPresenter?

    public init(presenter: RegistrationSplashPresenter) {
        self.presenter = presenter
        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.setHidesBackButton(true, animated: false)

        view.backgroundColor = Theme.backgroundColor

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = {
            let horizontalSizeClass = traitCollection.horizontalSizeClass
            var result = UIEdgeInsets.layoutMarginsForRegistration(horizontalSizeClass)
            // We want the hero image a bit closer to the top.
            result.top = 16
            return result
        }()
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        let canSwitchModes = UIDevice.current.isIPad || FeatureFlags.linkedPhones
        if canSwitchModes {
            let modeSwitchButton = UIButton()

            modeSwitchButton.setTemplateImageName(
                UIDevice.current.isIPad ? "link-24" : "link-broken-24",
                tintColor: .ows_gray25
            )
            modeSwitchButton.addTarget(self, action: #selector(didTapModeSwitch), for: .touchUpInside)
            modeSwitchButton.accessibilityIdentifier = "onboarding.splash.modeSwitch"

            view.addSubview(modeSwitchButton)
            modeSwitchButton.autoSetDimensions(to: CGSize(square: 40))
            modeSwitchButton.autoPinEdge(toSuperviewMargin: .trailing)
            modeSwitchButton.autoPinEdge(toSuperviewMargin: .top)
        }

        let heroImage = UIImage(named: "onboarding_splash_hero")
        let heroImageView = UIImageView(image: heroImage)
        heroImageView.contentMode = .scaleAspectFit
        heroImageView.layer.minificationFilter = .trilinear
        heroImageView.layer.magnificationFilter = .trilinear
        heroImageView.setCompressionResistanceLow()
        heroImageView.setContentHuggingVerticalLow()
        heroImageView.accessibilityIdentifier = "registration.splash.heroImageView"
        stackView.addArrangedSubview(heroImageView)
        stackView.setCustomSpacing(22, after: heroImageView)

        let titleText = {
            if TSConstants.isUsingProductionService {
                return OWSLocalizedString(
                    "ONBOARDING_SPLASH_TITLE",
                    comment: "Title of the 'onboarding splash' view."
                )
            } else {
                return "Internal Staging Build\n\(AppVersion.shared.currentAppVersion4)"
            }
        }()
        let titleLabel = UILabel.titleLabelForRegistration(text: titleText)
        titleLabel.accessibilityIdentifier = "registration.splash.titleLabel"
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(92, after: titleLabel)

        // TODO: This should be a button, not a label.
        let explanationLabel = UILabel()
        explanationLabel.text = OWSLocalizedString(
            "ONBOARDING_SPLASH_TERM_AND_PRIVACY_POLICY",
            comment: "Link to the 'terms and privacy policy' in the 'onboarding splash' view."
        )
        explanationLabel.textColor = Theme.accentBlueColor
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.isUserInteractionEnabled = true
        explanationLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(explanationLabelTapped)))
        explanationLabel.accessibilityIdentifier = "registration.splash.explanationLabel"
        stackView.addArrangedSubview(explanationLabel)
        stackView.setCustomSpacing(24, after: explanationLabel)

        let continueButton = OWSFlatButton.primaryButtonForRegistration(
            title: CommonStrings.continueButton,
            target: self,
            selector: #selector(continuePressed)
        )
        continueButton.accessibilityIdentifier = "registration.splash.continueButton"
        stackView.addArrangedSubview(continueButton)
        continueButton.autoSetDimension(.width, toSize: 280)
        continueButton.autoHCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            continueButton.autoPinEdge(toSuperviewEdge: .leading)
            continueButton.autoPinEdge(toSuperviewEdge: .trailing)
        }
    }

    // MARK: - Events

    @objc
    private func didTapModeSwitch() {
        Logger.info("")

        presenter?.switchToDeviceLinkingMode()
    }

    @objc
    private func explanationLabelTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else { return }
        let safariVC = SFSafariViewController(url: TSConstants.legalTermsUrl)
        present(safariVC, animated: true)
    }

    @objc
    private func continuePressed() {
        Logger.info("")
        presenter?.continueFromSplash()
    }
}
