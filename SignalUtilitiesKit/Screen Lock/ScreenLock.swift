// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import LocalAuthentication
import SessionMessagingKit

public class ScreenLock {
    public enum Outcome {
        case success
        case cancel
        case failure(error: String)
        case unexpectedFailure(error: String)
    }

    public let screenLockTimeoutDefault = (15 * kMinuteInterval)
    public let screenLockTimeouts = [
        1 * kMinuteInterval,
        5 * kMinuteInterval,
        15 * kMinuteInterval,
        30 * kMinuteInterval,
        1 * kHourInterval,
        0
    ]
    
    public static let shared: ScreenLock = ScreenLock()

    // MARK: - Methods

    /// This method should only be called:
    ///
    /// * On the main thread.
    ///
    /// Exactly one of these completions will be performed:
    ///
    /// * Asynchronously.
    /// * On the main thread.
    public func tryToUnlockScreenLock(
        success: @escaping (() -> Void),
        failure: @escaping ((Error) -> Void),
        unexpectedFailure: @escaping ((Error) -> Void),
        cancel: @escaping (() -> Void)
    ) {
        AssertIsOnMainThread()

        tryToVerifyLocalAuthentication(
            // Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to
            // unlock 'screen lock'.
            localizedReason: "SCREEN_LOCK_REASON_UNLOCK_SCREEN_LOCK".localized()
        ) { outcome in
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
        }
    }

    /// This method should only be called:
    ///
    /// * On the main thread.
    ///
    /// completionParam will be performed:
    ///
    /// * Asynchronously.
    /// * On the main thread.
    private func tryToVerifyLocalAuthentication(
        localizedReason: String,
        completion completionParam: @escaping ((Outcome) -> Void)
    ) {
        AssertIsOnMainThread()

        let defaultErrorDescription = "SCREEN_LOCK_ENABLE_UNKNOWN_ERROR".localized()

        // Ensure completion is always called on the main thread.
        let completion = { outcome in
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
                    Logger.error("local authentication unexpected success")
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
                return
            }
            
            let outcome = self.outcomeForLAError(
                errorParam: evaluateError,
                defaultErrorDescription: defaultErrorDescription
            )
            
            switch outcome {
                case .success:
                    Logger.error("local authentication unexpected success")
                    completion(.failure(error: defaultErrorDescription))
                    
                case .cancel, .failure, .unexpectedFailure:
                    completion(outcome)
            }
        }
    }

    // MARK: - Outcome

    private func outcomeForLAError(errorParam: Error?, defaultErrorDescription: String) -> Outcome {
        if let error = errorParam {
            guard let laError = error as? LAError else {
                return .failure(error: defaultErrorDescription)
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
                    Logger.error("context not valid.")
                    return .unexpectedFailure(error: defaultErrorDescription)
                    
                case .notInteractive:
                    Logger.error("context not interactive.")
                    return .unexpectedFailure(error: defaultErrorDescription)
                
                @unknown default:
                    return .failure(error: defaultErrorDescription)
            }
        }
        
        return .failure(error:defaultErrorDescription)
    }

    private func authenticationError(errorDescription: String) -> Error {
        return OWSErrorWithCodeDescription(.localAuthenticationError, errorDescription)
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
