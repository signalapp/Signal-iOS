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
    func setHasOldDevice(_ hasOldDevice: Bool)

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

        if FeatureFlags.Backups.supported {
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
        let sheet = RestoreOrTransferPickerController(
            setHasOldDeviceBlock: { [weak self] hasOldDevice in
                self?.dismiss(animated: true) {
                    self?.presenter?.setHasOldDevice(hasOldDevice)
                }
            }
        )
        self.present(sheet, animated: true)
    }
}

private class RestoreOrTransferPickerController: StackSheetViewController {

    private let setHasOldDeviceBlock: ((Bool) -> Void)
    init(setHasOldDeviceBlock: @escaping (Bool) -> Void) {
        self.setHasOldDeviceBlock = setHasOldDeviceBlock
        super.init()
    }

    open override var sheetBackgroundColor: UIColor { Theme.secondaryBackgroundColor }

    override func viewDidLoad() {
        super.viewDidLoad()
        stackView.spacing = 16

        let hasDeviceButton = RegistrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_HAVE_OLD_DEVICE_TITLE",
                comment: "Title for the 'have my old device' choice of the 'Restore or Transfer' prompt"
            ),
            body: OWSLocalizedString(
                "ONBOARDING_SPLASH_HAVE_OLD_DEVICE_BODY",
                comment: "Explanation of 'have old device' flow for the 'Restore or Transfer' prompt"
            ),
            iconName: Theme.iconName(.qrCodeLight)
        )
        hasDeviceButton.addTarget(target: self, selector: #selector(hasDevice))
        stackView.addArrangedSubview(hasDeviceButton)

        let noDeviceButton = RegistrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_DO_NOT_HAVE_OLD_DEVICE_TITLE",
                comment: "Title for the 'do not have my old device' choice of the 'Restore or Transfer' prompt"
            ),
            body: OWSLocalizedString(
                "ONBOARDING_SPLASH_DO_NOT_HAVE_OLD_DEVICE_BODY",
                comment: "Explanation of 'do not have old device' flow for the 'Restore or Transfer' prompt"
            ),
            iconName: Theme.iconName(.noDevice)
        )
        noDeviceButton.addTarget(target: self, selector: #selector(noDevice))
        stackView.addArrangedSubview(noDeviceButton)
    }

    @objc func hasDevice() {
        setHasOldDeviceBlock(true)
    }

    @objc func noDevice() {
        setHasOldDeviceBlock(false)
    }
}

#if DEBUG
private class PreviewRegistrationSplashPresenter: RegistrationSplashPresenter {
    func continueFromSplash() {
        print("continueFromSplash")
    }

    func setHasOldDevice(_ hasOldDevice: Bool) {
        print("setHasOldDevice: \(hasOldDevice)")
    }

    func switchToDeviceLinkingMode() {
        print("switchToDeviceLinkingMode")
    }

    func transferDevice() {
        print("transferDevice")
    }
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationSplashPresenter()
    return RegistrationSplashViewController(presenter: presenter)
}
#endif
