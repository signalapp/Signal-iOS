//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class OnboardingCountryState: NSObject {
    public let countryName: String
    public let callingCode: String
    public let countryCode: String

    @objc
    public init(countryName: String,
                callingCode: String,
                countryCode: String) {
        self.countryName = countryName
        self.callingCode = callingCode
        self.countryCode = countryCode
    }

    public static var defaultValue: OnboardingCountryState {
        AssertIsOnMainThread()

        var countryCode: String = PhoneNumber.defaultCountryCode()
        if let lastRegisteredCountryCode = OnboardingController.lastRegisteredCountryCode(),
            lastRegisteredCountryCode.count > 0 {
            countryCode = lastRegisteredCountryCode
        }

        let callingCodeNumber: NSNumber = PhoneNumberUtil.sharedThreadLocal().nbPhoneNumberUtil.getCountryCode(forRegion: countryCode)
        let callingCode = "\(COUNTRY_CODE_PREFIX)\(callingCodeNumber)"

        var countryName = NSLocalizedString("UNKNOWN_COUNTRY_NAME", comment: "Label for unknown countries.")
        if let countryNameDerived = PhoneNumberUtil.countryName(fromCountryCode: countryCode) {
            countryName = countryNameDerived
        }

        return OnboardingCountryState(countryName: countryName, callingCode: callingCode, countryCode: countryCode)
    }
}

// MARK: -

@objc
public class OnboardingPhoneNumber: NSObject {
    public let e164: String
    public let userInput: String

    @objc
    public init(e164: String,
                userInput: String) {
        self.e164 = e164
        self.userInput = userInput
    }
}

// MARK: -

@objc
public class OnboardingController: NSObject {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    // MARK: -

    @objc
    public override init() {
        super.init()
    }

    // MARK: - Factory Methods

    @objc
    public func initialViewController() -> UIViewController {
        AssertIsOnMainThread()

        let view = OnboardingSplashViewController(onboardingController: self)
        return view
    }

    // MARK: - Transitions

    public func onboardingSplashDidComplete(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        let view = OnboardingPermissionsViewController(onboardingController: self)
        viewController.navigationController?.pushViewController(view, animated: true)
    }

    public func onboardingPermissionsWasSkipped(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        pushPhoneNumberView(viewController: viewController)
    }

    public func onboardingPermissionsDidComplete(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        pushPhoneNumberView(viewController: viewController)
    }

    private func pushPhoneNumberView(viewController: UIViewController) {
        AssertIsOnMainThread()

        let view = OnboardingPhoneNumberViewController(onboardingController: self)
        viewController.navigationController?.pushViewController(view, animated: true)
    }

    public func onboardingRegistrationSucceeded(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        let view = OnboardingVerificationViewController(onboardingController: self)
        viewController.navigationController?.pushViewController(view, animated: true)
    }

    public func onboardingDidRequireCaptcha(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = viewController.navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }

        // The service could demand CAPTCHA from the "phone number" view or later
        // from the "code verification" view.  The "Captcha" view should always appear
        // immediately after the "phone number" view.
        while navigationController.viewControllers.count > 1 &&
            !(navigationController.topViewController is OnboardingPhoneNumberViewController) {
                navigationController.popViewController(animated: false)
        }

        let view = OnboardingCaptchaViewController(onboardingController: self)
        navigationController.pushViewController(view, animated: true)
    }

    // MARK: - State

    public private(set) var countryState: OnboardingCountryState = .defaultValue

    public private(set) var phoneNumber: OnboardingPhoneNumber?

    public private(set) var captchaToken: String?

    @objc
    public func update(countryState: OnboardingCountryState) {
        AssertIsOnMainThread()

        self.countryState = countryState
    }

    @objc
    public func update(phoneNumber: OnboardingPhoneNumber) {
        AssertIsOnMainThread()

        self.phoneNumber = phoneNumber
    }

    @objc
    public func update(captchaToken: String) {
        AssertIsOnMainThread()

        self.captchaToken = captchaToken
    }

    // MARK: - Debug

    private static let kKeychainService_LastRegistered = "kKeychainService_LastRegistered"
    private static let kKeychainKey_LastRegisteredCountryCode = "kKeychainKey_LastRegisteredCountryCode"
    private static let kKeychainKey_LastRegisteredPhoneNumber = "kKeychainKey_LastRegisteredPhoneNumber"

    private class func debugValue(forKey key: String) -> String? {
        AssertIsOnMainThread()

        guard OWSIsDebugBuild() else {
            return nil
        }

        do {
            let value = try CurrentAppContext().keychainStorage().string(forService: kKeychainService_LastRegistered, key: key)
            return value
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private class func setDebugValue(_ value: String, forKey key: String) {
        AssertIsOnMainThread()

        guard OWSIsDebugBuild() else {
            return
        }

        do {
            try CurrentAppContext().keychainStorage().set(string: value, service: kKeychainService_LastRegistered, key: key)
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    public class func lastRegisteredCountryCode() -> String? {
        return debugValue(forKey: kKeychainKey_LastRegisteredCountryCode)
    }

    private class func setLastRegisteredCountryCode(value: String) {
        setDebugValue(value, forKey: kKeychainKey_LastRegisteredCountryCode)
    }

    public class func lastRegisteredPhoneNumber() -> String? {
        return debugValue(forKey: kKeychainKey_LastRegisteredPhoneNumber)
    }

    private class func setLastRegisteredPhoneNumber(value: String) {
        setDebugValue(value, forKey: kKeychainKey_LastRegisteredPhoneNumber)
    }

    // MARK: - Registration

    public func tryToRegister(fromViewController: UIViewController,
                              smsVerification: Bool) {
        guard let phoneNumber = phoneNumber else {
            owsFailDebug("Missing phoneNumber.")
            return
        }

        // We eagerly update this state, regardless of whether or not the
        // registration request succeeds.
        OnboardingController.setLastRegisteredCountryCode(value: countryState.countryCode)
        OnboardingController.setLastRegisteredPhoneNumber(value: phoneNumber.userInput)

        let captchaToken = self.captchaToken
        ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                     canCancel: true) { (modal) in

                                                        self.tsAccountManager.register(withPhoneNumber: phoneNumber.e164,
                                                                                       captchaToken: captchaToken,
                                                                                       success: {
                                                                                        DispatchQueue.main.async {
                                                                                            modal.dismiss(completion: {
                                                                                                self.registrationSucceeded(viewController: fromViewController)
                                                                                            })
                                                                                        }
                                                        }, failure: { (error) in
                                                            Logger.error("Error: \(error)")

                                                            DispatchQueue.main.async {
                                                                modal.dismiss(completion: {
                                                                    self.registrationFailed(viewController: fromViewController, error: error as NSError)
                                                                })
                                                            }
                                                        }, smsVerification: smsVerification)
        }
    }

    private func registrationSucceeded(viewController: UIViewController) {
        onboardingRegistrationSucceeded(viewController: viewController)
    }

    private func registrationFailed(viewController: UIViewController, error: NSError) {
        if error.code == 402 {
            Logger.info("Captcha requested.")

            onboardingDidRequireCaptcha(viewController: viewController)
            return
        } else if error.code == 400 {
            OWSAlerts.showAlert(title: NSLocalizedString("REGISTRATION_ERROR", comment: ""),
                                message: NSLocalizedString("REGISTRATION_NON_VALID_NUMBER", comment: ""))

        } else {
            OWSAlerts.showAlert(title: error.localizedDescription,
                                message: error.localizedRecoverySuggestion)
        }
    }
}
