//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

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

    private var accountManager: AccountManager {
        return AppEnvironment.shared.accountManager
    }

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var backup: OWSBackup {
        return AppEnvironment.shared.backup
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

    public func requestingVerificationDidSucceed(viewController: UIViewController) {
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

    @objc
    public func verificationDidComplete(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        // At this point, the user has been prompted for contact access
        // and has valid service credentials.
        // We start the contact fetch/intersection now so that by the time
        // they get to HomeView we can show meaningful contact in the suggested
        // contact bubble.
        contactsManager.fetchSystemContactsOnceIfAlreadyAuthorized()

        if tsAccountManager.isReregistering() {
            showProfileView(fromView: view)
        } else {
            checkCanImportBackup(fromView: view)
        }
    }

    private func showProfileView(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = view.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        ProfileViewController.present(forRegistration: navigationController)
    }

    private func showBackupRestoreView(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = view.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        let restoreView = BackupRestoreViewController()
        navigationController.setViewControllers([restoreView], animated: true)
    }

    private func checkCanImportBackup(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        backup.checkCanImport({ (canImport) in
            Logger.info("canImport: \(canImport)")

            if (canImport) {
                self.backup.setHasPendingRestoreDecision(true)

                self.showBackupRestoreView(fromView: view)
            } else {
                self.showProfileView(fromView: view)
            }
        }, failure: { (_) in
            self.showBackupCheckFailedAlert(fromView: view)
        })
    }

    private func showBackupCheckFailedAlert(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        let alert = UIAlertController(title: NSLocalizedString("CHECK_FOR_BACKUP_FAILED_TITLE",
                                                               comment: "Title for alert shown when the app failed to check for an existing backup."),
                                      message: NSLocalizedString("CHECK_FOR_BACKUP_FAILED_MESSAGE",
                                                                 comment: "Message for alert shown when the app failed to check for an existing backup."),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("REGISTER_FAILED_TRY_AGAIN", comment: ""),
                                      style: .default) { (_) in
                                        self.checkCanImportBackup(fromView: view)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("CHECK_FOR_BACKUP_DO_NOT_RESTORE", comment: "The label for the 'do not restore backup' button."),
                                      style: .destructive) { (_) in
                                        self.showProfileView(fromView: view)
        })
        view.presentAlert(alert)
    }

    public func onboardingDidRequire2FAPin(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = viewController.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        guard !(navigationController.topViewController is Onboarding2FAViewController) else {
            // 2fa view is already presented, we don't need to push it again.
            return
        }

        let view = Onboarding2FAViewController(onboardingController: self)
        navigationController.pushViewController(view, animated: true)
    }

    @objc
    public func profileWasSkipped(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        showHomeView(view: view)
    }

    @objc
    public func profileDidComplete(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        showHomeView(view: view)
    }

    private func showHomeView(view: UIViewController) {
        AssertIsOnMainThread()

        guard let navigationController = view.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        // In production, this view will never be presented in a modal.
        // During testing (debug UI, etc.), it may be a modal.
        let isModal = navigationController.presentingViewController != nil
        if isModal {
            view.dismiss(animated: true, completion: {
                SignalApp.shared().showHomeView()
            })
        } else {
            SignalApp.shared().showHomeView()
        }
    }

    // MARK: - State

    public private(set) var countryState: OnboardingCountryState = .defaultValue

    public private(set) var phoneNumber: OnboardingPhoneNumber?

    public private(set) var captchaToken: String?

    public private(set) var verificationCode: String?

    public private(set) var twoFAPin: String?

    private var kbsAuth: RemoteAttestationAuth?

    public private(set) var verificationRequestCount: UInt = 0

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

    @objc
    public func update(verificationCode: String) {
        AssertIsOnMainThread()

        self.verificationCode = verificationCode
    }

    @objc
    public func update(twoFAPin: String) {
        AssertIsOnMainThread()

        self.twoFAPin = twoFAPin
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
            // The value may not be present in the keychain.
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

    public func requestVerification(fromViewController: UIViewController, isSMS: Bool) {
        AssertIsOnMainThread()

        guard let phoneNumber = phoneNumber else {
            owsFailDebug("Missing phoneNumber.")
            return
        }

        // We eagerly update this state, regardless of whether or not the
        // registration request succeeds.
        OnboardingController.setLastRegisteredCountryCode(value: countryState.countryCode)
        OnboardingController.setLastRegisteredPhoneNumber(value: phoneNumber.userInput)

        let captchaToken = self.captchaToken
        self.verificationRequestCount += 1
        ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                     canCancel: true) { modal in
            firstly {
                self.accountManager.requestAccountVerification(recipientId: phoneNumber.e164,
                                                               captchaToken: captchaToken,
                                                               isSMS: isSMS)
            }.done {
                modal.dismiss {
                    self.requestingVerificationDidSucceed(viewController: fromViewController)
                }
            }.catch { error in
                Logger.error("Error: \(error)")
                modal.dismiss {
                    self.requestingVerificationDidFail(viewController: fromViewController, error: error)
                }
            }.retainUntilComplete()
        }
    }

    private func requestingVerificationDidFail(viewController: UIViewController, error: Error) {
        switch error {
        case AccountServiceClientError.captchaRequired:
            onboardingDidRequireCaptcha(viewController: viewController)
            return

        case let networkManagerError as NetworkManagerError:
            switch networkManagerError.statusCode {
            case 400:
                OWSAlerts.showAlert(title: NSLocalizedString("REGISTRATION_ERROR", comment: ""),
                                    message: NSLocalizedString("REGISTRATION_NON_VALID_NUMBER", comment: ""))
                return
            default:
                break
            }

        default:
            break
        }

        let nsError = error as NSError
        owsFailDebug("unexpected error: \(nsError)")
        OWSAlerts.showAlert(title: nsError.localizedDescription,
                            message: nsError.localizedRecoverySuggestion)
    }

    // MARK: - Verification

    public enum VerificationOutcome: Equatable {
        case success
        case invalidVerificationCode
        case invalid2FAPin
        case invalidV2RegistrationLockPin(remainingAttempts: UInt32)
        case exhaustedV2RegistrationLockAttempts
    }

    public func submitVerification(fromViewController: UIViewController,
                                   completion : @escaping (VerificationOutcome) -> Void) {
        AssertIsOnMainThread()

        // If we have credentials for KBS auth, we need to restore our keys.
        if let kbsAuth = kbsAuth {
            guard let twoFAPin = twoFAPin else {
                owsFailDebug("We expected a 2fa attempt, but we don't have a code to try")
                return completion(.invalid2FAPin)
            }

            KeyBackupService.restoreKeys(with: twoFAPin, and: kbsAuth).done {
                // If we restored successfully clear out KBS auth, the server will give it
                // to us again if we still need to do KBS operations.
                self.kbsAuth = nil

                // We've restored our keys, we can now re-run this method to post our registration token
                self.submitVerification(fromViewController: fromViewController, completion: completion)
            }.catch { error in
                guard let error = error as? KeyBackupService.KBSError else {
                    owsFailDebug("unexpected response from KBS")
                    return completion(.invalid2FAPin)
                }

                switch error {
                case .assertion:
                    owsFailDebug("unexpected response from KBS")
                    completion(.invalid2FAPin)
                case .invalidPin(let remainingAttempts):
                    completion(.invalidV2RegistrationLockPin(remainingAttempts: remainingAttempts))
                case .backupMissing:
                    // We don't have a backup for this person, it probably
                    // was deleted due to too many failed attempts. They'll
                    // have to retry after the registration lock window expires.
                    completion(.exhaustedV2RegistrationLockAttempts)
                }
            }.retainUntilComplete()

            return
        }

        guard let phoneNumber = phoneNumber else {
            owsFailDebug("Missing phoneNumber.")
            return
        }
        guard let verificationCode = verificationCode else {
            completion(.invalidVerificationCode)
            return
        }

        // Ensure the account manager state is up-to-date.
        //
        // TODO: We could skip this in production.
        tsAccountManager.phoneNumberAwaitingVerification = phoneNumber.e164

        let twoFAPin = self.twoFAPin
        ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                     canCancel: true) { (modal) in

                                                        self.accountManager.register(verificationCode: verificationCode, pin: twoFAPin)
                                                            .done { (_) in
                                                                DispatchQueue.main.async {
                                                                    modal.dismiss(completion: {
                                                                        self.verificationDidComplete(fromView: fromViewController)
                                                                    })
                                                                }
                                                            }.catch({ (error) in
                                                                Logger.error("Error: \(error)")

                                                                DispatchQueue.main.async {
                                                                    modal.dismiss(completion: {
                                                                        self.verificationFailed(fromViewController: fromViewController,
                                                                                                error: error as NSError,
                                                                                                completion: completion)
                                                                    })
                                                                }
                                                            }).retainUntilComplete()
        }
    }

    private func verificationFailed(fromViewController: UIViewController, error: NSError,
                                    completion : @escaping (VerificationOutcome) -> Void) {
        AssertIsOnMainThread()

        if error.domain == OWSSignalServiceKitErrorDomain &&
            error.code == OWSErrorCode.registrationMissing2FAPIN.rawValue {

            Logger.info("Missing 2FA PIN.")

            // If we were provided KBS auth, we'll need to re-register using reg lock v2,
            // store this for that path.
            kbsAuth = error.userInfo[TSRemoteAttestationAuthErrorKey] as? RemoteAttestationAuth

            // Since we were told we need 2fa, clear out any stored KBS keys so we can
            // do a fresh verification.
            KeyBackupService.clearKeychain()

            completion(.invalid2FAPin)

            onboardingDidRequire2FAPin(viewController: fromViewController)
        } else {
            if error.domain == OWSSignalServiceKitErrorDomain &&
                error.code == OWSErrorCode.userError.rawValue {
                completion(.invalidVerificationCode)
            }

            Logger.verbose("error: \(error.domain) \(error.code)")
            OWSAlerts.showAlert(title: NSLocalizedString("REGISTRATION_VERIFICATION_FAILED_TITLE", comment: "Alert view title"),
                                message: error.localizedDescription,
                                fromViewController: fromViewController)
        }
    }
}

// MARK: -

public extension UIView {
    func addBottomStroke() -> UIView {
        return addBottomStroke(color: Theme.middleGrayColor, strokeWidth: CGHairlineWidth())
    }

    func addBottomStroke(color: UIColor, strokeWidth: CGFloat) -> UIView {
        let strokeView = UIView()
        strokeView.backgroundColor = color
        addSubview(strokeView)
        strokeView.autoSetDimension(.height, toSize: strokeWidth)
        strokeView.autoPinWidthToSuperview()
        strokeView.autoPinEdge(toSuperviewEdge: .bottom)
        return strokeView
    }
}
