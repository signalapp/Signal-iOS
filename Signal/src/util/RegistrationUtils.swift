//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import UIKit

@objc
public extension RegistrationUtils {

    static func reregister(fromViewController: UIViewController) {
        AssertIsOnMainThread()

        // If this is not the primary device, jump directly to the re-linking flow.
        guard self.tsAccountManager.isPrimaryDevice else {
            Self.showRelinkingUI()
            return
        }

        guard tsAccountManager.resetForReregistration(),
              let phoneNumber = Self.tsAccountManager.reregistrationPhoneNumber()?.nilIfEmpty else {
            owsFailDebug("could not reset for re-registration.")
            return
        }

        Logger.info("phoneNumber: \(phoneNumber)")

        Self.preferences.unsetRecordedAPNSTokens()

        ModalActivityIndicatorViewController.present(
            fromViewController: fromViewController,
            canCancel: false) { modalActivityIndicator in

                firstly {
                    Self.accountManager.requestRegistrationVerification(e164: phoneNumber,
                                                                        captchaToken: nil,
                                                                        isSMS: true)
                }.done(on: .main) { _ in

                    Logger.info("re-registering: send verification code succeeded.")

                    modalActivityIndicator.dismiss {
                        AssertIsOnMainThread()

                        // TODO[ViewContextPiping]
                        let context = ViewControllerContext.shared
                        let onboardingController = OnboardingController(context: context, onboardingMode: .registering)
                        let registrationPhoneNumber = RegistrationPhoneNumber(e164: phoneNumber, userInput: phoneNumber)
                        onboardingController.update(phoneNumber: registrationPhoneNumber)

                        let viewController = OnboardingVerificationViewController(onboardingController: onboardingController)
                        viewController.hideBackLink()
                        let navigationController = OnboardingNavigationController(onboardingController: onboardingController)
                        navigationController.setViewControllers([viewController], animated: false)
                        let window: UIWindow = CurrentAppContext().mainWindow!
                        window.rootViewController = navigationController
                    }
                }.catch(on: .main) { error in
                    AssertIsOnMainThread()

                    Logger.warn("Re-registration failure: \(error).")

                    modalActivityIndicator.dismiss {
                        AssertIsOnMainThread()

                        if error.httpStatusCode == 400 {
                            OWSActionSheets.showActionSheet(
                                title: NSLocalizedString("REGISTRATION_ERROR", comment: ""),
                                message: NSLocalizedString("REGISTRATION_NON_VALID_NUMBER", comment: "")
                            )
                        } else if let error = error as? UserErrorDescriptionProvider {
                            OWSActionSheets.showActionSheet(
                                title: NSLocalizedString("REGISTRATION_ERROR", comment: ""),
                                message: error.localizedDescription
                            )
                        } else if let error = error as? AccountServiceClientError {
                            switch error {
                            case .captchaRequired:
                                // TODO[ViewContextPiping]
                                let context = ViewControllerContext.shared
                                let onboardingController = OnboardingController(context: context, onboardingMode: .registering)
                                let registrationPhoneNumber = RegistrationPhoneNumber(e164: phoneNumber, userInput: phoneNumber)
                                onboardingController.update(phoneNumber: registrationPhoneNumber)

                                let viewController = OnboardingCaptchaViewController(onboardingController: onboardingController)
                                let navigationController = OnboardingNavigationController(onboardingController: onboardingController)
                                navigationController.setViewControllers([viewController], animated: false)
                                let window: UIWindow = CurrentAppContext().mainWindow!
                                window.rootViewController = navigationController
                            }

                        } else {
                            OWSActionSheets.showActionSheet(
                                title: NSLocalizedString("REGISTRATION_ERROR", comment: "")
                                )
                        }
                    }
                }
            }
    }
}
