//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import LocalAuthentication

@objc public class OWSScreenLock: NSObject {

    public enum OWSScreenLockOutcome {
        case success
        case cancel
        case failure(error:String)
        case unexpectedFailure(error:String)
    }

    @objc public let screenLockTimeoutDefault = 15 * kMinuteInterval
    @objc public let screenLockTimeouts = [
        1 * kMinuteInterval,
        5 * kMinuteInterval,
        15 * kMinuteInterval,
        30 * kMinuteInterval,
        1 * kHourInterval,
        0
    ]

    @objc public static let ScreenLockDidChange = Notification.Name("ScreenLockDidChange")

    let primaryStorage: OWSPrimaryStorage
    let dbConnection: YapDatabaseConnection

    private let OWSScreenLock_Collection = "OWSScreenLock_Collection"
    private let OWSScreenLock_Key_IsScreenLockEnabled = "OWSScreenLock_Key_IsScreenLockEnabled"
    private let OWSScreenLock_Key_ScreenLockTimeoutSeconds = "OWSScreenLock_Key_ScreenLockTimeoutSeconds"

    // MARK: - Singleton class

    @objc(sharedManager)
    public static let shared = OWSScreenLock()

    private override init() {
        self.primaryStorage = OWSPrimaryStorage.shared()
        self.dbConnection = self.primaryStorage.newDatabaseConnection()

        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - Properties

    @objc public func isScreenLockEnabled() -> Bool {
        AssertIsOnMainThread()

        if !OWSStorage.isStorageReady() {
            owsFailDebug("accessed screen lock state before storage is ready.")
            return false
        }

        return self.dbConnection.bool(forKey: OWSScreenLock_Key_IsScreenLockEnabled, inCollection: OWSScreenLock_Collection, defaultValue: false)
    }

    @objc
    public func setIsScreenLockEnabled(_ value: Bool) {
        AssertIsOnMainThread()
        assert(OWSStorage.isStorageReady())

        self.dbConnection.setBool(value, forKey: OWSScreenLock_Key_IsScreenLockEnabled, inCollection: OWSScreenLock_Collection)

        NotificationCenter.default.postNotificationNameAsync(OWSScreenLock.ScreenLockDidChange, object: nil)
    }

    @objc public func screenLockTimeout() -> TimeInterval {
        AssertIsOnMainThread()

        if !OWSStorage.isStorageReady() {
            owsFailDebug("accessed screen lock state before storage is ready.")
            return 0
        }

        return self.dbConnection.double(forKey: OWSScreenLock_Key_ScreenLockTimeoutSeconds, inCollection: OWSScreenLock_Collection, defaultValue: screenLockTimeoutDefault)
    }

    @objc public func setScreenLockTimeout(_ value: TimeInterval) {
        AssertIsOnMainThread()
        assert(OWSStorage.isStorageReady())

        self.dbConnection.setDouble(value, forKey: OWSScreenLock_Key_ScreenLockTimeoutSeconds, inCollection: OWSScreenLock_Collection)

        NotificationCenter.default.postNotificationNameAsync(OWSScreenLock.ScreenLockDidChange, object: nil)
    }

    // MARK: - Methods

    // This method should only be called:
    //
    // * On the main thread.
    //
    // Exactly one of these completions will be performed:
    //
    // * Asynchronously.
    // * On the main thread.
    @objc public func tryToUnlockScreenLock(success: @escaping (() -> Void),
                                            failure: @escaping ((Error) -> Void),
                                            unexpectedFailure: @escaping ((Error) -> Void),
                                            cancel: @escaping (() -> Void)) {
        AssertIsOnMainThread()

        tryToVerifyLocalAuthentication(localizedReason: NSLocalizedString("SCREEN_LOCK_REASON_UNLOCK_SCREEN_LOCK",
                                                                          comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to unlock 'screen lock'."),
                                       completion: { (outcome: OWSScreenLockOutcome) in
                                        AssertIsOnMainThread()

                                        switch outcome {
                                        case .failure(let error):
                                            Logger.error("local authentication failed with error: \(error)")
                                            failure(self.authenticationError(errorDescription: error))
                                        case .unexpectedFailure(let error):
                                            Logger.error("local authentication failed with unexpected error: \(error)")
                                            unexpectedFailure(self.authenticationError(errorDescription: error))
                                        case .success:
                                            Logger.verbose("local authentication succeeded.")
                                            success()
                                        case .cancel:
                                            Logger.verbose("local authentication cancelled.")
                                            cancel()
                                        }
        })
    }

    // This method should only be called:
    //
    // * On the main thread.
    //
    // completionParam will be performed:
    //
    // * Asynchronously.
    // * On the main thread.
    private func tryToVerifyLocalAuthentication(localizedReason: String,
                                                completion completionParam: @escaping ((OWSScreenLockOutcome) -> Void)) {
        AssertIsOnMainThread()

        let defaultErrorDescription = NSLocalizedString("SCREEN_LOCK_ENABLE_UNKNOWN_ERROR",
                                                        comment: "Indicates that an unknown error occurred while using Touch ID/Face ID/Phone Passcode.")

        // Ensure completion is always called on the main thread.
        let completion = { (outcome: OWSScreenLockOutcome) in
            DispatchQueue.main.async {
                completionParam(outcome)
            }
        }

        let context = screenLockContext()

        var authError: NSError?
        let canEvaluatePolicy = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError)
        if !canEvaluatePolicy || authError != nil {
            Logger.error("could not determine if local authentication is supported: \(String(describing: authError))")

            let outcome = self.outcomeForLAError(errorParam: authError,
                                                 defaultErrorDescription: defaultErrorDescription)
            switch outcome {
            case .success:
                owsFailDebug("local authentication unexpected success")
                completion(.failure(error:defaultErrorDescription))
            case .cancel, .failure, .unexpectedFailure:
                completion(outcome)
            }
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localizedReason) { success, evaluateError in

            if success {
                Logger.info("local authentication succeeded.")
                completion(.success)
            } else {
                let outcome = self.outcomeForLAError(errorParam: evaluateError,
                                                     defaultErrorDescription: defaultErrorDescription)
                switch outcome {
                case .success:
                    owsFailDebug("local authentication unexpected success")
                    completion(.failure(error:defaultErrorDescription))
                case .cancel, .failure, .unexpectedFailure:
                    completion(outcome)
                }
            }
        }
    }

    // MARK: - Outcome

    private func outcomeForLAError(errorParam: Error?, defaultErrorDescription: String) -> OWSScreenLockOutcome {
        if let error = errorParam {
            guard let laError = error as? LAError else {
                return .failure(error:defaultErrorDescription)
            }

            if #available(iOS 11.0, *) {
                switch laError.code {
                case .biometryNotAvailable:
                    Logger.error("local authentication error: biometryNotAvailable.")
                    return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_AVAILABLE",
                                                             comment: "Indicates that Touch ID/Face ID/Phone Passcode are not available on this device."))
                case .biometryNotEnrolled:
                    Logger.error("local authentication error: biometryNotEnrolled.")
                    return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_ENROLLED",
                                                             comment: "Indicates that Touch ID/Face ID/Phone Passcode is not configured on this device."))
                case .biometryLockout:
                    Logger.error("local authentication error: biometryLockout.")
                    return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_LOCKOUT",
                                                             comment: "Indicates that Touch ID/Face ID/Phone Passcode is 'locked out' on this device due to authentication failures."))
                default:
                    // Fall through to second switch
                    break
                }
            }

            switch laError.code {
            case .authenticationFailed:
                Logger.error("local authentication error: authenticationFailed.")
                return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_FAILED",
                                                         comment: "Indicates that Touch ID/Face ID/Phone Passcode authentication failed."))
            case .userCancel, .userFallback, .systemCancel, .appCancel:
                Logger.info("local authentication cancelled.")
                return .cancel
            case .passcodeNotSet:
                Logger.error("local authentication error: passcodeNotSet.")
                return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_PASSCODE_NOT_SET",
                                                         comment: "Indicates that Touch ID/Face ID/Phone Passcode passcode is not set."))
            case .touchIDNotAvailable:
                Logger.error("local authentication error: touchIDNotAvailable.")
                return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_AVAILABLE",
                                                         comment: "Indicates that Touch ID/Face ID/Phone Passcode are not available on this device."))
            case .touchIDNotEnrolled:
                Logger.error("local authentication error: touchIDNotEnrolled.")
                return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_ENROLLED",
                                                         comment: "Indicates that Touch ID/Face ID/Phone Passcode is not configured on this device."))
            case .touchIDLockout:
                Logger.error("local authentication error: touchIDLockout.")
                return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_LOCKOUT",
                                                         comment: "Indicates that Touch ID/Face ID/Phone Passcode is 'locked out' on this device due to authentication failures."))
            case .invalidContext:
                owsFailDebug("context not valid.")
                return .unexpectedFailure(error:defaultErrorDescription)
            case .notInteractive:
                owsFailDebug("context not interactive.")
                return .unexpectedFailure(error:defaultErrorDescription)
            }
        }
        return .failure(error:defaultErrorDescription)
    }

    private func authenticationError(errorDescription: String) -> Error {
        return OWSErrorWithCodeDescription(.localAuthenticationError,
                                           errorDescription)
    }

    // MARK: - Context

    private func screenLockContext() -> LAContext {
        let context = LAContext()

        // Never recycle biometric auth.
        context.touchIDAuthenticationAllowableReuseDuration = TimeInterval(0)

        if #available(iOS 11.0, *) {
            assert(!context.interactionNotAllowed)
        }

        return context
    }
}
