//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PureLayout
import SafariServices
import SignalServiceKit
public import SignalUI

// MARK: - RegistrationSplashPresenter

public protocol RegistrationSplashPresenter: AnyObject {
    func continueFromSplash()
    func restoreOrTransfer()

    func switchToDeviceLinkingMode()
    func transferDevice()
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
        stackView.directionalLayoutMargins = {
            let horizontalSizeClass = traitCollection.horizontalSizeClass
            var result = NSDirectionalEdgeInsets.layoutMarginsForRegistration(horizontalSizeClass)
            // We want the hero image a bit closer to the top.
            result.top = 16
            return result
        }()
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        let canSwitchModes = UIDevice.current.isIPad || FeatureFlags.linkedPhones
        var transferButtonTrailingView: UIView = self.view
        var transferButtonTrailingEdge: ALEdge = .trailing
        if canSwitchModes {
            let modeSwitchButton = UIButton()

            modeSwitchButton.setTemplateImageName(
                UIDevice.current.isIPad ? "link" : "link-slash",
                tintColor: .ows_gray25
            )
            modeSwitchButton.addTarget(self, action: #selector(didTapModeSwitch), for: .touchUpInside)
            modeSwitchButton.accessibilityIdentifier = "onboarding.splash.modeSwitch"

            view.addSubview(modeSwitchButton)
            modeSwitchButton.autoSetDimensions(to: CGSize(square: 40))
            modeSwitchButton.autoPinEdge(toSuperviewMargin: .trailing)
            modeSwitchButton.autoPinEdge(toSuperviewMargin: .top)

            transferButtonTrailingEdge = .leading
            transferButtonTrailingView = modeSwitchButton
        }

        if FeatureFlags.preRegDeviceTransfer {
            let transferButton = UIButton()

            transferButton.setImage(Theme.iconImage(.transfer), animated: false)
            transferButton.addTarget(self, action: #selector(didTapTransfer), for: .touchUpInside)
            transferButton.accessibilityIdentifier = "onboarding.splash.transfer"

            view.addSubview(transferButton)
            transferButton.autoSetDimensions(to: CGSize(square: 40))
            transferButton.autoPinEdge(
                .trailing,
                to: transferButtonTrailingEdge,
                of: transferButtonTrailingView
            )
            transferButton.autoPinEdge(toSuperviewMargin: .top)
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
                return "Internal Staging Build\n\(AppVersionImpl.shared.currentAppVersion)"
            }
        }()
        let titleLabel = UILabel.titleLabelForRegistration(text: titleText)
        titleLabel.accessibilityIdentifier = "registration.splash.titleLabel"
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(12, after: titleLabel)

        let explanationButton = UIButton()
        explanationButton.setTitle(
            OWSLocalizedString(
                "ONBOARDING_SPLASH_TERM_AND_PRIVACY_POLICY",
                comment: "Link to the 'terms and privacy policy' in the 'onboarding splash' view."
            ),
            for: .normal
        )
        explanationButton.setTitleColor(Theme.secondaryTextAndIconColor, for: .normal)
        explanationButton.titleLabel?.font = UIFont.dynamicTypeBody2
        explanationButton.titleLabel?.numberOfLines = 0
        explanationButton.titleLabel?.textAlignment = .center
        explanationButton.titleLabel?.lineBreakMode = .byWordWrapping
        explanationButton.addTarget(
            self,
            action: #selector(explanationButtonTapped),
            for: .touchUpInside
        )
        explanationButton.accessibilityIdentifier = "registration.splash.explanationLabel"
        stackView.addArrangedSubview(explanationButton)
        stackView.setCustomSpacing(57, after: explanationButton)

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

        if FeatureFlags.messageBackupQuickRestoreFlow {
            stackView.setCustomSpacing(16, after: continueButton)

            let restoreOrTransferButton = OWSFlatButton.secondaryButtonForRegistration(
                title: OWSLocalizedString(
                    "ONBOARDING_SPLASH_RESTORE_OR_TRANSFER_BUTTON_TITLE",
                    comment: "Button for restoring or transferring account in the 'onboarding splash' view."
                ),
                target: self,
                selector: #selector(didTapRestoreOrTransfer)
            )
            restoreOrTransferButton.accessibilityIdentifier = "registration.splash.continueButton"
            stackView.addArrangedSubview(restoreOrTransferButton)
            restoreOrTransferButton.autoSetDimension(.width, toSize: 280)
            restoreOrTransferButton.autoHCenterInSuperview()
            NSLayoutConstraint.autoSetPriority(.defaultLow) {
                restoreOrTransferButton.autoPinEdge(toSuperviewEdge: .leading)
                restoreOrTransferButton.autoPinEdge(toSuperviewEdge: .trailing)
            }
        }
    }

    // MARK: - Events

    @objc
    private func didTapModeSwitch() {
        Logger.info("")

        presenter?.switchToDeviceLinkingMode()
    }

    @objc
    private func didTapTransfer() {
        Logger.info("")

        presenter?.transferDevice()
    }

    @objc
    private func explanationButtonTapped(sender: UIGestureRecognizer) {
        let safariVC = SFSafariViewController(url: TSConstants.legalTermsUrl)
        present(safariVC, animated: true)
    }

    @objc
    private func continuePressed() {
        Logger.info("")
        presenter?.continueFromSplash()
    }

    @objc
    private func didTapRestoreOrTransfer() {
        Logger.info("")
        presenter?.restoreOrTransfer()
    }
}
