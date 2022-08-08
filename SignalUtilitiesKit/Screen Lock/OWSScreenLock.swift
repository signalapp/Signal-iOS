// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import LocalAuthentication
import SessionMessagingKit

// FIXME: Refactor this once the 'PrivacySettingsTableViewController' and 'OWSScreenLockUI' have been refactored
@objc public class OWSScreenLock: NSObject {

    public enum OWSScreenLockOutcome {
        case success
        case cancel
        case failure(error: String)
        case unexpectedFailure(error: String)
    }

    @objc public let screenLockTimeoutDefault = (15 * kMinuteInterval)
    @objc public let screenLockTimeouts = [
        1 * kMinuteInterval,
        5 * kMinuteInterval,
        15 * kMinuteInterval,
        30 * kMinuteInterval,
        1 * kHourInterval,
        0
    ]

    @objc public static let ScreenLockDidChange = Notification.Name("ScreenLockDidChange")

    // MARK: - Singleton class

    @objc(sharedManager)
    public static let shared = OWSScreenLock()

    private override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - Properties

    @objc public func isScreenLockEnabled() -> Bool {
        return Storage.shared[.isScreenLockEnabled]
    }

    @objc
    public func setIsScreenLockEnabled(_ value: Bool) {
        Storage.shared.writeAsync(
            updates: { db in db[.isScreenLockEnabled] = value },
            completion: { _, _ in
                NotificationCenter.default.postNotificationNameAsync(OWSScreenLock.ScreenLockDidChange, object: nil)
            }
        )
    }

    @objc public func screenLockTimeout() -> TimeInterval {
        return Storage.shared[.screenLockTimeoutSeconds]
            .defaulting(to: screenLockTimeoutDefault)
    }

    @objc public func setScreenLockTimeout(_ value: TimeInterval) {
        Storage.shared.writeAsync(
            updates: { db in db[.screenLockTimeoutSeconds] = value },
            completion: { _, _ in
                NotificationCenter.default.postNotificationNameAsync(OWSScreenLock.ScreenLockDidChange, object: nil)
            }
        )
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

        let defaultErrorDescription = "SCREEN_LOCK_ENABLE_UNKNOWN_ERROR".localized()

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
                completion(.failure(error: defaultErrorDescription))
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

            switch laError.code {
                case .biometryNotAvailable:
                    Logger.error("local authentication error: biometryNotAvailable.")
                    return .failure(error: "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_AVAILABLE".localized())
                case .biometryNotEnrolled:
                    Logger.error("local authentication error: biometryNotEnrolled.")
                    return .failure(error: "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_ENROLLED".localized())
                case .biometryLockout:
                    Logger.error("local authentication error: biometryLockout.")
                    return .failure(error: "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_LOCKOUT".localized())
                default:
                    // Fall through to second switch
                    break
            }

            switch laError.code {
                case .authenticationFailed:
                    Logger.error("local authentication error: authenticationFailed.")
                    return .failure(error: "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_FAILED".localized())
                case .userCancel, .userFallback, .systemCancel, .appCancel:
                    Logger.info("local authentication cancelled.")
                    return .cancel
                case .passcodeNotSet:
                    Logger.error("local authentication error: passcodeNotSet.")
                    return .failure(error: "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_PASSCODE_NOT_SET".localized())
                case .touchIDNotAvailable:
                    Logger.error("local authentication error: touchIDNotAvailable.")
                    return .failure(error: "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_AVAILABLE".localized())
                case .touchIDNotEnrolled:
                    Logger.error("local authentication error: touchIDNotEnrolled.")
                    return .failure(error: "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_ENROLLED".localized())
                case .touchIDLockout:
                    Logger.error("local authentication error: touchIDLockout.")
                    return .failure(error: "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_LOCKOUT".localized())
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
        assert(!context.interactionNotAllowed)

        return context
    }
}
