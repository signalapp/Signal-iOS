//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class OnboardingState: NSObject {
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

    public static var defaultValue: OnboardingState {
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

        return OnboardingState(countryName: countryName, callingCode: callingCode, countryCode: countryCode)
    }
}

@objc
public class OnboardingController: NSObject {

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

        let view = OnboardingPermissionsViewController(onboardingController: self)
        viewController.navigationController?.pushViewController(view, animated: true)
    }

    public func onboardingPermissionsWasSkipped(viewController: UIViewController) {
        AssertIsOnMainThread()

        pushPhoneNumberView(viewController: viewController)
    }

    public func onboardingPermissionsDidComplete(viewController: UIViewController) {
        AssertIsOnMainThread()

        pushPhoneNumberView(viewController: viewController)
    }

    private func pushPhoneNumberView(viewController: UIViewController) {
        AssertIsOnMainThread()

        let view = OnboardingPhoneNumberViewController(onboardingController: self)
        viewController.navigationController?.pushViewController(view, animated: true)
    }

    public func onboardingPhoneNumberDidComplete(viewController: UIViewController) {
        AssertIsOnMainThread()

        //        CodeVerificationViewController *vc = [CodeVerificationViewController new];
        //        [weakSelf.navigationController pushViewController:vc animated:YES];
    }

    public func onboardingPhoneNumberDidRequireCaptcha(viewController: UIViewController) {
        AssertIsOnMainThread()

        let view = OnboardingCaptchaViewController(onboardingController: self)
        viewController.navigationController?.pushViewController(view, animated: true)
    }

    // MARK: - State

    public private(set) var state: OnboardingState = .defaultValue

    public func update(withCountryName countryName: String, callingCode: String, countryCode: String) {
        AssertIsOnMainThread()

        guard countryCode.count > 0 else {
            owsFailDebug("Invalid country code.")
            return
        }
        guard countryName.count > 0 else {
            owsFailDebug("Invalid country name.")
            return
        }
        guard callingCode.count > 0 else {
            owsFailDebug("Invalid calling code.")
            return
        }

        state = OnboardingState(countryName: countryName, callingCode: callingCode, countryCode: countryCode)
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

    public class func setLastRegisteredCountryCode(value: String) {
        setDebugValue(value, forKey: kKeychainKey_LastRegisteredCountryCode)
    }

    public class func lastRegisteredPhoneNumber() -> String? {
        return debugValue(forKey: kKeychainKey_LastRegisteredPhoneNumber)
    }

    public class func setLastRegisteredPhoneNumber(value: String) {
        setDebugValue(value, forKey: kKeychainKey_LastRegisteredPhoneNumber)
    }
}
