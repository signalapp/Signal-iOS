//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Lottie
import SignalMessaging
import UIKit

@objc
public class OnboardingPermissionsViewController: OnboardingBaseViewController {

    private let animationView = AnimationView(name: "notificationPermission")

    let shouldRequestAccessToContacts: Bool

    override public init(onboardingController: OnboardingController) {
        switch onboardingController.onboardingMode {
        case .registering: // primary
            shouldRequestAccessToContacts = true
        case .provisioning:  // linked
            shouldRequestAccessToContacts = !FeatureFlags.contactDiscoveryV2
        }
        super.init(onboardingController: onboardingController)
    }

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: CommonStrings.skipButton,
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(skipWasPressed))

        let titleText: String
        let explanationText: String
        let giveAccessText: String
        if shouldRequestAccessToContacts {
            titleText = NSLocalizedString(
                "ONBOARDING_PERMISSIONS_TITLE",
                comment: "Title of the 'onboarding permissions' view."
            )
            explanationText = NSLocalizedString(
                "ONBOARDING_PERMISSIONS_EXPLANATION",
                comment: "Explanation in the 'onboarding permissions' view."
            )
            giveAccessText = NSLocalizedString(
                "ONBOARDING_PERMISSIONS_ENABLE_PERMISSIONS_BUTTON",
                comment: "Label for the 'give access' button in the 'onboarding permissions' view."
            )
        } else {
            titleText = NSLocalizedString(
                "LINKED_ONBOARDING_PERMISSIONS_TITLE",
                comment: "Title of the 'onboarding permissions' view."
            )
            explanationText = NSLocalizedString(
                "LINKED_ONBOARDING_PERMISSIONS_EXPLANATION",
                comment: "Explanation in the 'onboarding permissions' view."
            )
            giveAccessText = NSLocalizedString(
                "LINKED_ONBOARDING_PERMISSIONS_ENABLE_PERMISSIONS_BUTTON",
                comment: "Label for the 'give access' button in the 'onboarding permissions' view."
            )
        }

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
            OnboardingBaseViewController.horizontallyWrap(primaryButton: giveAccessButton)
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
        if shouldRequestAccessToContacts, CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            return .value(true)
        }

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
        }.then { _ in
            self.requestContactsPermissionIfNeeded()
        }.done {
            self.onboardingController.onboardingPermissionsDidComplete(viewController: self)
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    /// Request contacts permissions.
    ///
    /// Always resolves, even if the user denies the request.
    private func requestContactsPermissionIfNeeded() -> Promise<Void> {
        Logger.info("")

        guard shouldRequestAccessToContacts else {
            return .value(())
        }

        let (promise, future) = Promise<Void>.pending()
        CNContactStore().requestAccess(for: CNEntityType.contacts) { (granted, error) -> Void in
            if granted {
                Logger.info("User granted contacts permission")
            } else {
                // Unfortunately, we can't easily disambiguate "not granted" and
                // "other error".
                Logger.warn("User denied contacts permission or there was an error. Error: \(String(describing: error))")
            }
            future.resolve()
        }
        return promise
    }

     // MARK: - Events

    @objc
    func skipWasPressed() {
        Logger.info("")

        onboardingController.onboardingPermissionsWasSkipped(viewController: self)
    }

    @objc
    func giveAccessPressed() {
        Logger.info("")

        requestPermissions()
    }
}
