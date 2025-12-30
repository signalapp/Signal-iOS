//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
public import SignalUI

// MARK: - RegistrationSplashPresenter

public protocol RegistrationSplashPresenter: AnyObject {
    func continueFromSplash()
    func setHasOldDevice(_ hasOldDevice: Bool)

    func switchToDeviceLinkingMode()
}

// MARK: - RegistrationSplashViewController

public class RegistrationSplashViewController: OWSViewController, OWSNavigationChildController {

    public var prefersNavigationBarHidden: Bool {
        true
    }

    private weak var presenter: RegistrationSplashPresenter?

    public init(presenter: RegistrationSplashPresenter) {
        self.presenter = presenter
        super.init()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        // Buttons in the top right corner.
        let canSwitchModes = UIDevice.current.isIPad || BuildFlags.linkedPhones
        if canSwitchModes {
            let modeSwitchButton = UIButton(
                configuration: .plain(),
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapModeSwitch()
                },
            )
            modeSwitchButton.configuration?.image = .init(named: UIDevice.current.isIPad ? "link" : "link-slash")
            modeSwitchButton.tintColor = .ows_gray25
            modeSwitchButton.accessibilityIdentifier = "registration.splash.modeSwitch"

            view.addSubview(modeSwitchButton)
            modeSwitchButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                modeSwitchButton.widthAnchor.constraint(equalToConstant: 40),
                modeSwitchButton.heightAnchor.constraint(equalToConstant: 40),
                modeSwitchButton.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
                modeSwitchButton.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            ])
        }

        // Image at the top.
        let imageView = UIImageView(image: UIImage(named: "onboarding_splash_hero"))
        imageView.contentMode = .scaleAspectFit
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.setCompressionResistanceLow()
        imageView.setContentHuggingVerticalLow()
        imageView.accessibilityIdentifier = "registration.splash.heroImageView"
        let heroImageContainer = UIView.container()
        heroImageContainer.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        // Center image vertically in the available space above title text.
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: heroImageContainer.centerXAnchor),
            imageView.widthAnchor.constraint(equalTo: heroImageContainer.widthAnchor),
            imageView.centerYAnchor.constraint(equalTo: heroImageContainer.centerYAnchor),
            imageView.heightAnchor.constraint(equalTo: heroImageContainer.heightAnchor, constant: 0.8),
        ])

        // Welcome text.
        let titleText = {
            if TSConstants.isUsingProductionService {
                return OWSLocalizedString(
                    "ONBOARDING_SPLASH_TITLE",
                    comment: "Title of the 'onboarding splash' view.",
                )
            } else {
                return "Internal Staging Build\n\(AppVersionImpl.shared.currentAppVersion)"
            }
        }()
        let titleLabel = UILabel.titleLabelForRegistration(text: titleText)
        titleLabel.accessibilityIdentifier = "registration.splash.titleLabel"

        // Terms of service and privacy policy.
        let tosPPButton = UIButton(
            configuration: .smallBorderless(title: OWSLocalizedString(
                "ONBOARDING_SPLASH_TERM_AND_PRIVACY_POLICY",
                comment: "Link to the 'terms and privacy policy' in the 'onboarding splash' view.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.showTOSPP()
            },
        )
        tosPPButton.configuration?.baseForegroundColor = .Signal.secondaryLabel
        tosPPButton.enableMultilineLabel()
        tosPPButton.accessibilityIdentifier = "registration.splash.explanationLabel"

        // Large buttons enclosed in a container with some extra horizontal padding.
        let continueButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.continueButton),
            primaryAction: UIAction { [weak self] _ in
                self?.continuePressed()
            },
        )
        continueButton.accessibilityIdentifier = "registration.splash.continueButton"

        let restoreOrTransferButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "ONBOARDING_SPLASH_RESTORE_OR_TRANSFER_BUTTON_TITLE",
                comment: "Button for restoring or transferring account in the 'onboarding splash' view.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapRestoreOrTransfer()
            },
        )
        restoreOrTransferButton.enableMultilineLabel()
        restoreOrTransferButton.accessibilityIdentifier = "registration.splash.continueButton"

        let largeButtonsContainer = UIStackView.verticalButtonStack(buttons: [continueButton, restoreOrTransferButton])

        // Main content view.
        let stackView = addStaticContentStackView(arrangedSubviews: [
            heroImageContainer,
            titleLabel,
            tosPPButton,
            largeButtonsContainer,
        ])
        stackView.setCustomSpacing(44, after: imageView)
        stackView.setCustomSpacing(82, after: tosPPButton)

        view.sendSubviewToBack(stackView)
    }

    // MARK: - Events

    private func didTapModeSwitch() {
        Logger.info("")
        presenter?.switchToDeviceLinkingMode()
    }

    private func showTOSPP() {
        let safariVC = SFSafariViewController(url: TSConstants.legalTermsUrl)
        present(safariVC, animated: true)
    }

    private func continuePressed() {
        Logger.info("")
        presenter?.continueFromSplash()
    }

    private func didTapRestoreOrTransfer() {
        Logger.info("")
        let sheet = RestoreOrTransferPickerController(
            setHasOldDeviceBlock: { [weak self] hasOldDevice in
                self?.dismiss(animated: true) {
                    self?.presenter?.setHasOldDevice(hasOldDevice)
                }
            },
        )
        self.present(sheet, animated: true)
    }
}

private class RestoreOrTransferPickerController: StackSheetViewController {

    override var placeOnGlassIfAvailable: Bool { false }

    private let setHasOldDeviceBlock: (Bool) -> Void
    init(setHasOldDeviceBlock: @escaping (Bool) -> Void) {
        self.setHasOldDeviceBlock = setHasOldDeviceBlock
        super.init()
    }

    override open var sheetBackgroundColor: UIColor { .Signal.secondaryBackground }

    override func viewDidLoad() {
        super.viewDidLoad()
        stackView.spacing = 16

        let hasDeviceButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_HAVE_OLD_DEVICE_TITLE",
                comment: "Title for the 'have my old device' choice of the 'Restore or Transfer' prompt",
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_SPLASH_HAVE_OLD_DEVICE_BODY",
                comment: "Explanation of 'have old device' flow for the 'Restore or Transfer' prompt",
            ),
            iconName: "qr-code-48",
            primaryAction: UIAction { [weak self] _ in
                self?.setHasOldDeviceBlock(true)
            },
        )
        stackView.addArrangedSubview(hasDeviceButton)

        let noDeviceButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_DO_NOT_HAVE_OLD_DEVICE_TITLE",
                comment: "Title for the 'do not have my old device' choice of the 'Restore or Transfer' prompt",
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_SPLASH_DO_NOT_HAVE_OLD_DEVICE_BODY",
                comment: "Explanation of 'do not have old device' flow for the 'Restore or Transfer' prompt",
            ),
            iconName: "no-phone-48",
            primaryAction: UIAction { [weak self] _ in
                self?.setHasOldDeviceBlock(false)
            },
        )
        stackView.addArrangedSubview(noDeviceButton)
    }
}

// MARK: -

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
