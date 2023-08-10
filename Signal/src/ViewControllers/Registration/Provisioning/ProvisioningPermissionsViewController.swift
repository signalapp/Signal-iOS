//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Lottie
import SignalMessaging
import SignalUI

public class ProvisioningPermissionsViewController: ProvisioningBaseViewController {

    private let animationView = AnimationView(name: "notificationPermission")

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleText: String
        let explanationText: String
        let giveAccessText: String
        titleText = OWSLocalizedString(
            "LINKED_ONBOARDING_PERMISSIONS_TITLE",
            comment: "Title of the 'onboarding permissions' view."
        )
        explanationText = OWSLocalizedString(
            "LINKED_ONBOARDING_PERMISSIONS_EXPLANATION",
            comment: "Explanation in the 'onboarding permissions' view."
        )
        giveAccessText = OWSLocalizedString(
            "LINKED_ONBOARDING_PERMISSIONS_ENABLE_PERMISSIONS_BUTTON",
            comment: "Label for the 'give access' button in the 'onboarding permissions' view."
        )

        let titleLabel = self.createTitleLabel(text: titleText)
        titleLabel.accessibilityIdentifier = "onboarding.permissions." + "titleLabel"
        titleLabel.setCompressionResistanceVerticalHigh()

        let explanationLabel = self.createExplanationLabel(explanationText: explanationText)
        explanationLabel.accessibilityIdentifier = "onboarding.permissions." + "explanationLabel"
        explanationLabel.setCompressionResistanceVerticalHigh()

        let giveAccessButton = self.primaryButton(title: giveAccessText, selector: #selector(giveAccessPressed))
        giveAccessButton.accessibilityIdentifier = "onboarding.permissions." + "giveAccessButton"
        giveAccessButton.setCompressionResistanceVerticalHigh()

        animationView.loopMode = .playOnce
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.contentMode = .scaleAspectFit
        animationView.setContentHuggingHigh()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 20),
            explanationLabel,
            UIView.spacer(withHeight: 60),
            animationView,
            UIView.vStretchingSpacer(minHeight: 80),
            ProvisioningBaseViewController.horizontallyWrap(primaryButton: giveAccessButton)
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 0
        primaryView.addSubview(stackView)

        stackView.autoPinEdgesToSuperviewMargins()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.animationView.play()
    }

    // MARK: Requesting permissions

    public func needsToAskForAnyPermissions() -> Guarantee<Bool> {
        return Guarantee<Bool> { resolve in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                resolve(settings.authorizationStatus == .notDetermined)
            }
        }
    }

    private func requestPermissions() {
        Logger.info("")

        // If you request any additional permissions, make sure to add them to
        // `needsToAskForAnyPermissions`.
        firstly {
            PushRegistrationManager.shared.registerUserNotificationSettings()
        }.done {
            self.provisioningController.provisioningPermissionsDidComplete(viewController: self)
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

     // MARK: - Events

    @objc
    private func giveAccessPressed() {
        Logger.info("")

        requestPermissions()
    }
}
