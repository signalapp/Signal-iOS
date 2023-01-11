//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit
import SignalMessaging
import SignalUI

protocol ChangePhoneNumberViewDelegate: AnyObject {
    var changePhoneNumberViewFromViewController: UIViewController { get }
}

// MARK: -

class ChangePhoneNumberController: Dependencies {
    public weak var delegate: ChangePhoneNumberViewDelegate?

    public init(delegate: ChangePhoneNumberViewDelegate) {
        self.delegate = delegate
    }

// MARK: -

    public func cancelFlow(viewController: UIViewController) {
        AssertIsOnMainThread()

        guard let navigationController = viewController.navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }
        guard let fromViewController = delegate?.changePhoneNumberViewFromViewController else {
            owsFailDebug("Missing fromViewController.")
            return
        }

        navigationController.popToViewController(fromViewController, animated: true)
    }

    public func requestVerification(fromViewController: UIViewController,
                                    isSMS: Bool,
                                    completion: RegistrationHelper.VerificationCompletion?) {
        AssertIsOnMainThread()

        let countryState = self.newCountryState
        guard let phoneNumber = newPhoneNumber else {
            owsFailDebug("Missing newPhoneNumber.")
            if let completion = completion {
                DispatchQueue.main.async {
                    completion(false, OWSAssertionError("Missing newPhoneNumber."))
                }
            }
            return
        }

        RegistrationHelper.requestChangePhoneNumberVerification(delegate: self,
                                                                fromViewController: fromViewController,
                                                                phoneNumber: phoneNumber,
                                                                countryState: countryState,
                                                                captchaToken: captchaToken,
                                                                isSMS: isSMS,
                                                                completion: completion)
    }

    // MARK: - Verification

    public enum VerificationOutcome: Equatable {
        case success
        case invalidPhoneNumber
        case invalidVerificationCode
        case invalid2FAPin
        case invalidV2RegistrationLockPin(remainingAttempts: UInt32)
        case exhaustedV2RegistrationLockAttempts
        case cancelled
        case assertionError
    }

    public func submitVerification(fromViewController: UIViewController,
                                   completion: @escaping (VerificationOutcome) -> Void) {
        AssertIsOnMainThread()

        guard let newPhoneNumber = self.newPhoneNumber else {
            return completion(.invalidPhoneNumber)
        }
        guard let verificationCode = self.verificationCode?.nilIfEmpty else {
            return completion(.invalidVerificationCode)
        }
        let registrationLockToken: String? = self.registrationLockToken

        let promise = Self.accountManager.requestChangePhoneNumber(newPhoneNumber: newPhoneNumber.e164,
                                                                   verificationCode: verificationCode,
                                                                   registrationLock: registrationLockToken)

        ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                     canCancel: false) { modal in
            promise.done {
                modal.dismiss {
                    self.verificationDidComplete()
                }
            }.catch { error in
                modal.dismiss(completion: {
                    Logger.warn("Error: \(error)")

                    self.verificationFailed(
                        fromViewController: fromViewController,
                        error: error,
                        completion: completion)
                })
            }
        }
    }

    private func verificationDidComplete() {
        dismissFlow(didSucceed: true)
    }

    public func dismissFlow(didSucceed: Bool) {
        AssertIsOnMainThread()

        guard let changePhoneNumberViewFromViewController = delegate?.changePhoneNumberViewFromViewController else {
            owsFailDebug("Missing changePhoneNumberViewFromViewController.")
            return
        }
        guard let navigationController = changePhoneNumberViewFromViewController.navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }

        if didSucceed {
            guard let newPhoneNumber = newPhoneNumber else {
                owsFailDebug("Missing new number.")
                return
            }

            guard let rootViewController = navigationController.viewControllers.first else {
                owsFailDebug("Missing rootViewController.")
                return
            }

            navigationController.popToViewController(rootViewController, animated: true) {
                let format = NSLocalizedString(
                    "SETTINGS_CHANGE_PHONE_NUMBER_CHANGE_SUCCESSFUL_FORMAT",
                    comment: "Message indicating that 'change phone number' was successful. Embeds: {{ the user's new phone number }}")
                OWSActionSheets.showActionSheet(
                    message: String(format: format, PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: newPhoneNumber.e164)),
                    buttonTitle: CommonStrings.okayButton,
                    fromViewController: rootViewController
                )
            }
        } else {
            navigationController.popToViewController(changePhoneNumberViewFromViewController, animated: true)
        }
    }

    private func verificationFailed(fromViewController: UIViewController,
                                    error: Error,
                                    completion: @escaping (VerificationOutcome) -> Void) {
        AssertIsOnMainThread()

        if let registrationMissing2FAPinError = error as? RegistrationMissing2FAPinError {

            Logger.info("Missing 2FA PIN.")

            verificationDidRequire2FAPin(viewController: fromViewController,
                                         kbsAuth: registrationMissing2FAPinError.remoteAttestationAuth)
        } else {
            let nsError = error as NSError
            if nsError.domain == OWSSignalServiceKitErrorDomain &&
                nsError.code == OWSErrorCode.userError.rawValue {
                completion(.invalidVerificationCode)
            }

            Logger.warn("Error: \(error)")
            OWSActionSheets.showActionSheet(title: NSLocalizedString("REGISTRATION_VERIFICATION_FAILED_TITLE", comment: "Alert view title"),
                                            message: error.userErrorDescription,
                                            fromViewController: fromViewController)
        }
    }

    // MARK: -

    func firstViewController() -> UIViewController {
        ChangePhoneNumberSplashViewController(changePhoneNumberController: self)
    }

    public func verificationDidRequire2FAPin(viewController: UIViewController,
                                             kbsAuth: RemoteAttestation.Auth) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = viewController.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        guard !(navigationController.topViewController is ChangePhoneNumber2FAViewController) else {
            // 2fa view is already presented, we don't need to push it again.
            return
        }
        guard let oldPhoneNumber = self.oldPhoneNumber?.asPhoneNumber,
              let newPhoneNumber = self.newPhoneNumber?.asPhoneNumber else {
                  owsFailDebug("Missing phone number.")
                  return
              }

        let view = ChangePhoneNumber2FAViewController(changePhoneNumberController: self,
                                                      oldPhoneNumber: oldPhoneNumber,
                                                      newPhoneNumber: newPhoneNumber,
                                                      kbsAuth: kbsAuth)
        navigationController.pushViewController(view, animated: true)
    }

    // MARK: - State

    public var oldCountryState: RegistrationCountryState = .defaultValue

    public var oldPhoneNumber: RegistrationPhoneNumber?

    public var newCountryState: RegistrationCountryState = .defaultValue

    public var newPhoneNumber: RegistrationPhoneNumber?

    public var captchaToken: String?

    public var registrationLockToken: String?

    public var verificationCode: String?

    // MARK: -

    func showCaptchaView(fromViewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = fromViewController.navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }
        guard let oldPhoneNumber = oldPhoneNumber?.asPhoneNumber else {
            owsFailDebug("Missing oldPhoneNumber.")
            return
        }
        guard let newPhoneNumber = newPhoneNumber?.asPhoneNumber else {
            owsFailDebug("Missing newPhoneNumber.")
            return
        }

        let view = ChangePhoneNumberCaptchaViewController(changePhoneNumberController: self,
                                                          oldPhoneNumber: oldPhoneNumber,
                                                          newPhoneNumber: newPhoneNumber)
        navigationController.pushViewController(view, animated: true)
    }
}

// MARK: -

extension ChangePhoneNumberController: RegistrationHelperDelegate {

    public func registrationRequestVerificationDidSucceed(fromViewController: UIViewController) {
        AssertIsOnMainThread()

        guard let navigationController = fromViewController.navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }
        guard let oldPhoneNumber = oldPhoneNumber?.asPhoneNumber else {
            owsFailDebug("Missing oldPhoneNumber.")
            return
        }
        guard let newPhoneNumber = newPhoneNumber?.asPhoneNumber else {
            owsFailDebug("Missing newPhoneNumber.")
            return
        }

        let vc = ChangePhoneNumberVerificationViewController(changePhoneNumberController: self,
                                                             oldPhoneNumber: oldPhoneNumber,
                                                             newPhoneNumber: newPhoneNumber)
        navigationController.pushViewController(vc, animated: true)
    }

    public func registrationRequestVerificationDidRequireCaptcha(fromViewController: UIViewController) {
        AssertIsOnMainThread()

        showCaptchaView(fromViewController: fromViewController)
    }

    public func registrationIncrementVerificationRequestCount() {}
}

// MARK: -

extension ChangePhoneNumberController: RegistrationPinAttemptsExhaustedViewDelegate {
    var hasPendingRestoration: Bool { false }

    func pinAttemptsExhaustedViewDidComplete(viewController: RegistrationPinAttemptsExhaustedViewController) {
        dismissFlow(didSucceed: false)
    }
}
