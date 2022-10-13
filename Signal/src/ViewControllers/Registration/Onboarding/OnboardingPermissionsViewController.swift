//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import Contacts
import Lottie

@objc
public class OnboardingPermissionsViewController: OnboardingBaseViewController {

    private let animationView = AnimationView(name: "notificationPermission")

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: CommonStrings.skipButton,
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(skipWasPressed))

        let titleLabel = self.createTitleLabel(text: NSLocalizedString("ONBOARDING_PERMISSIONS_TITLE", comment: "Title of the 'onboarding permissions' view."))
        titleLabel.accessibilityIdentifier = "onboarding.permissions." + "titleLabel"

        let explanationLabel = self.createExplanationLabel(explanationText: NSLocalizedString("ONBOARDING_PERMISSIONS_EXPLANATION",
                                                                                  comment: "Explanation in the 'onboarding permissions' view."))
        explanationLabel.accessibilityIdentifier = "onboarding.permissions." + "explanationLabel"

        animationView.loopMode = .playOnce
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.contentMode = .scaleAspectFit
        animationView.setContentHuggingHigh()

        let giveAccessButton = self.primaryButton(title: NSLocalizedString("ONBOARDING_PERMISSIONS_ENABLE_PERMISSIONS_BUTTON",
                                                                    comment: "Label for the 'give access' button in the 'onboarding permissions' view."),
                                           selector: #selector(giveAccessPressed))
        giveAccessButton.accessibilityIdentifier = "onboarding.permissions." + "giveAccessButton"
        let primaryButtonView = OnboardingBaseViewController.horizontallyWrap(primaryButton: giveAccessButton)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 20),
            explanationLabel,
            UIView.spacer(withHeight: 60),
            animationView,
            UIView.vStretchingSpacer(minHeight: 80),
            primaryButtonView
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

    // MARK: Request Access

    private func requestAccess() {
        Logger.info("")

        firstly {
            PushRegistrationManager.shared.registerUserNotificationSettings()
        }.then { _ in
            self.requestContactsAccess()
        }.done {
            self.onboardingController.onboardingPermissionsDidComplete(viewController: self)
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private func requestContactsAccess() -> Promise<Void> {
        Logger.info("")

        let (promise, future) = Promise<Void>.pending()
        CNContactStore().requestAccess(for: CNEntityType.contacts) { (granted, error) -> Void in
            if granted {
                Logger.info("Granted.")
            } else {
                Logger.error("Error: \(String(describing: error)).")
            }
            // Always fulfill.
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

        requestAccess()
    }

    @objc
    func notNowPressed() {
        Logger.info("")

        onboardingController.onboardingPermissionsWasSkipped(viewController: self)
    }
}
