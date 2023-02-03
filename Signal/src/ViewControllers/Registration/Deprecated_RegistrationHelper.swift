//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging

public protocol Deprecated_RegistrationHelperDelegate: AnyObject {
    func registrationRequestVerificationDidSucceed(fromViewController: UIViewController)
    func registrationRequestVerificationDidRequireCaptcha(fromViewController: UIViewController)
    func registrationIncrementVerificationRequestCount()
}

// MARK: -

public class Deprecated_RegistrationHelper: Dependencies {

    public typealias VerificationCompletion = (_ willTransition: Bool, _ error: Error?) -> Void

#if DEBUG
    private static let forceCaptcha = false
#endif

    public static func requestRegistrationVerification(delegate: Deprecated_RegistrationHelperDelegate,
                                                       fromViewController: UIViewController,
                                                       phoneNumber: RegistrationPhoneNumber?,
                                                       countryState: RegistrationCountryState,
                                                       captchaToken: String?,
                                                       isSMS: Bool,
                                                       completion: VerificationCompletion?) {
        requestVerification(mode: .registration,
                            delegate: delegate,
                            fromViewController: fromViewController,
                            phoneNumber: phoneNumber,
                            countryState: countryState,
                            captchaToken: captchaToken,
                            isSMS: isSMS,
                            completion: completion)

    }

    public static func requestChangePhoneNumberVerification(delegate: Deprecated_RegistrationHelperDelegate,
                                                            fromViewController: UIViewController,
                                                            phoneNumber: RegistrationPhoneNumber?,
                                                            countryState: RegistrationCountryState,
                                                            captchaToken: String?,
                                                            isSMS: Bool,
                                                            completion: VerificationCompletion?) {
        requestVerification(mode: .changePhoneNumber,
                            delegate: delegate,
                            fromViewController: fromViewController,
                            phoneNumber: phoneNumber,
                            countryState: countryState,
                            captchaToken: captchaToken,
                            isSMS: isSMS,
                            completion: completion)
    }

    private static func requestVerification(mode: AccountManager.VerificationMode,
                                            delegate: Deprecated_RegistrationHelperDelegate,
                                            fromViewController: UIViewController,
                                            phoneNumber: RegistrationPhoneNumber?,
                                            countryState: RegistrationCountryState,
                                            captchaToken: String?,
                                            isSMS: Bool,
                                            completion: VerificationCompletion?) {

        AssertIsOnMainThread()

        guard let phoneNumber = phoneNumber else {
            owsFailDebug("Missing phoneNumber.")
            if let completion = completion {
                DispatchQueue.main.async {
                    completion(false, OWSAssertionError("Missing phoneNumber."))
                }
            }
            return
        }

        // We eagerly update this state, regardless of whether or not the
        // registration request succeeds.
        RegistrationValues.setLastRegisteredCountryCode(value: countryState.countryCode)
        RegistrationValues.setLastRegisteredPhoneNumber(value: phoneNumber.userInput)

#if DEBUG
        if forceCaptcha, captchaToken == nil {
            DispatchQueue.main.async {
                let error = AccountServiceClientError.captchaRequired
                completion?(true, error)
                delegate.registrationRequestVerificationDidRequireCaptcha(fromViewController: fromViewController)
            }
            return
        }
#endif

        delegate.registrationIncrementVerificationRequestCount()

        firstly { () -> Promise<Void> in
            self.accountManager.deprecated_requestAccountVerification(e164: phoneNumber.e164,
                                                                      captchaToken: captchaToken,
                                                                      isSMS: isSMS,
                                                                      mode: mode)
        }.done { [weak delegate] in
            completion?(true, nil)
            delegate?.registrationRequestVerificationDidSucceed(fromViewController: fromViewController)
        }.catch { [weak delegate] error in
            Self.handleVerificationError(error: error,
                                         fromViewController: fromViewController,
                                         delegate: delegate,
                                         completion: completion)
        }
    }

    private static func handleVerificationError(error: Error,
                                                fromViewController: UIViewController,
                                                delegate: Deprecated_RegistrationHelperDelegate?,
                                                completion: VerificationCompletion?) {
        AssertIsOnMainThread()

        Logger.warn("Error: \(error)")

        switch error {
        case let error where error.httpStatusCode == 400:
            completion?(false, error)
            OWSActionSheets.showActionSheet(
                title: NSLocalizedString("REGISTRATION_ERROR", comment: ""),
                message: NSLocalizedString("REGISTRATION_NON_VALID_NUMBER", comment: ""))

        case let error where error.httpStatusCode == 413 || error.httpStatusCode == 429:
            completion?(false, error)
            OWSActionSheets.showActionSheet(
                title: nil,
                message: NSLocalizedString("REGISTER_RATE_LIMITING_BODY", comment: "action sheet body"))

        case let error where error.isNetworkFailureOrTimeout:
            completion?(false, error)
            OWSActionSheets.showActionSheet(
                title: NSLocalizedString("REGISTRATION_ERROR_NETWORK_FAILURE_ALERT_TITLE",
                                         comment: "Alert title for network failure during registration"),
                message: NSLocalizedString("REGISTRATION_ERROR_NETWORK_FAILURE_ALERT_BODY",
                                           comment: "Alert body for network failure during registration"))

        case AccountServiceClientError.captchaRequired:
            completion?(true, error)
            delegate?.registrationRequestVerificationDidRequireCaptcha(fromViewController: fromViewController)
        default:
            owsFailDebug("unexpected error: \(error)")
            completion?(false, error)
            OWSActionSheets.showActionSheet(title: error.userErrorDescription,
                                            message: (error as NSError).localizedRecoverySuggestion)
        }
    }

    public static func presentPhoneNumberConfirmationSheet(from vc: UIViewController,
                                                           number: String,
                                                           completion: @escaping (_ didApprove: Bool) -> Void) {
        let titleFormat = NSLocalizedString(
            "REGISTRATION_VIEW_PHONE_NUMBER_CONFIRMATION_ALERT_TITLE_FORMAT",
            comment: "Title for confirmation alert during phone number registration. Embeds {{phone number}}.")
        let message = NSLocalizedString(
            "REGISTRATION_VIEW_PHONE_NUMBER_CONFIRMATION_ALERT_MESSAGE",
            comment: "Message for confirmation alert during phone number registration.")
        let editButtonTitle = NSLocalizedString(
            "REGISTRATION_VIEW_PHONE_NUMBER_CONFIRMATION_EDIT_BUTTON",
            comment: "A button allowing user to cancel registration and edit a phone number")

        let sheet = ActionSheetController(title: String(format: titleFormat, number), message: message)
        sheet.addAction(ActionSheetAction(title: CommonStrings.yesButton, style: .default, handler: { _ in
            completion(true)
        }))
        sheet.addAction(ActionSheetAction(title: editButtonTitle, style: .default, handler: { _ in
            completion(false)
        }))
        vc.present(sheet, animated: true, completion: nil)
    }
}
