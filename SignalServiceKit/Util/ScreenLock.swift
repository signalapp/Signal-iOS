//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LocalAuthentication

public class ScreenLock: NSObject {

    public enum Outcome {
        case success
        case cancel
        case failure(error: String)
        case unexpectedFailure(error: String)
    }

    public static let screenLockTimeoutDefault = 15 * kMinuteInterval

    public let screenLockTimeouts = [
        1 * kMinuteInterval,
        5 * kMinuteInterval,
        15 * kMinuteInterval,
        30 * kMinuteInterval,
        1 * kHourInterval,
        0
    ]

    public static let ScreenLockDidChange = Notification.Name("ScreenLockDidChange")

    private static let OWSScreenLock_Key_IsScreenLockEnabled = "OWSScreenLock_Key_IsScreenLockEnabled"
    private static let OWSScreenLock_Key_ScreenLockTimeoutSeconds = "OWSScreenLock_Key_ScreenLockTimeoutSeconds"

    // MARK: - Singleton class

    public static let shared = ScreenLock()

    private override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - KV Store

    public let keyValueStore = KeyValueStore(collection: "OWSScreenLock_Collection")

    // MARK: - Properties

    public func isScreenLockEnabled() -> Bool {
        AssertIsOnMainThread()

        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return self.keyValueStore.getBool(ScreenLock.OWSScreenLock_Key_IsScreenLockEnabled,
                                              defaultValue: false,
                                              transaction: transaction.asV2Read)
        }
    }

    public func setIsScreenLockEnabled(_ value: Bool) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.keyValueStore.setBool(value,
                                       key: ScreenLock.OWSScreenLock_Key_IsScreenLockEnabled,
                                       transaction: transaction.asV2Write)
        }

        NotificationCenter.default.postNotificationNameAsync(ScreenLock.ScreenLockDidChange, object: nil)
    }

    public func screenLockTimeout() -> TimeInterval {
        AssertIsOnMainThread()

        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return self.keyValueStore.getDouble(ScreenLock.OWSScreenLock_Key_ScreenLockTimeoutSeconds,
                                                defaultValue: ScreenLock.screenLockTimeoutDefault,
                                                transaction: transaction.asV2Read)
        }
    }

    public func setScreenLockTimeout(_ value: TimeInterval) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.keyValueStore.setDouble(value,
                                         key: ScreenLock.OWSScreenLock_Key_ScreenLockTimeoutSeconds,
                                         transaction: transaction.asV2Write)
        }

        NotificationCenter.default.postNotificationNameAsync(ScreenLock.ScreenLockDidChange, object: nil)
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
    public func tryToUnlockScreenLock(success: @escaping (() -> Void),
                                      failure: @escaping ((Error) -> Void),
                                      unexpectedFailure: @escaping ((Error) -> Void),
                                      cancel: @escaping (() -> Void)) {
        AssertIsOnMainThread()

        tryToVerifyLocalAuthentication(localizedReason: OWSLocalizedString("SCREEN_LOCK_REASON_UNLOCK_SCREEN_LOCK",
                                                                          comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to unlock 'screen lock'."),
                                       completion: { (outcome: Outcome) in
                                        AssertIsOnMainThread()

                                        switch outcome {
                                        case .failure(let error):
                                            Logger.error("local authentication failed with error: \(error)")
                                            failure(self.authenticationError(errorDescription: error))
                                        case .unexpectedFailure(let error):
                                            Logger.error("local authentication failed with unexpected error: \(error)")
                                            unexpectedFailure(self.authenticationError(errorDescription: error))
                                        case .success:
                                            success()
                                        case .cancel:
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
                                                completion completionParam: @escaping ((Outcome) -> Void)) {
        AssertIsOnMainThread()

        let defaultErrorDescription = DeviceAuthenticationErrorMessage.unknownError

        // Ensure completion is always called on the main thread.
        let completion = { (outcome: Outcome) in
            DispatchQueue.main.async {
                completionParam(outcome)
            }
        }

        let context = DeviceOwnerAuthenticationType.localAuthenticationContext()

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
                    completion(.failure(error: defaultErrorDescription))
                case .cancel, .failure, .unexpectedFailure:
                    completion(outcome)
                }
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
                return .failure(error: ScreenLock.ErrorMessage.authenticationNotAvailable)
            case .biometryNotEnrolled:
                Logger.error("local authentication error: biometryNotEnrolled.")
                return .failure(error: ScreenLock.ErrorMessage.authenticationNotEnrolled)
            case .biometryLockout:
                Logger.error("local authentication error: biometryLockout.")
                return .failure(error: DeviceAuthenticationErrorMessage.lockout)
            default:
                // Fall through to second switch
                break
            }

            switch laError.code {
            case .authenticationFailed:
                Logger.error("local authentication error: authenticationFailed.")
                return .failure(error: DeviceAuthenticationErrorMessage.authenticationFailed)
            case .userCancel, .userFallback, .systemCancel, .appCancel:
                Logger.info("local authentication cancelled.")
                return .cancel
            case .passcodeNotSet:
                Logger.error("local authentication error: passcodeNotSet.")
                return .failure(error: ScreenLock.ErrorMessage.passcodeNotSet)
            case .touchIDNotAvailable:
                Logger.error("local authentication error: touchIDNotAvailable.")
                return .failure(error: ScreenLock.ErrorMessage.authenticationNotAvailable)
            case .touchIDNotEnrolled:
                Logger.error("local authentication error: touchIDNotEnrolled.")
                return .failure(error: ScreenLock.ErrorMessage.authenticationNotEnrolled)
            case .touchIDLockout:
                Logger.error("local authentication error: touchIDLockout.")
                return .failure(error: DeviceAuthenticationErrorMessage.lockout)
            case .invalidContext:
                owsFailDebug("context not valid.")
                return .unexpectedFailure(error: defaultErrorDescription)
            case .notInteractive:
                owsFailDebug("context not interactive.")
                return .unexpectedFailure(error: defaultErrorDescription)
            @unknown default:
                owsFailDebug("Unexpected enum value.")
                return .unexpectedFailure(error: defaultErrorDescription)
            }
        }
        return .failure(error: defaultErrorDescription)
    }

    private func authenticationError(errorDescription: String) -> Error {
        return OWSError(error: .localAuthenticationError,
                        description: errorDescription,
                        isRetryable: false)
    }
}

// MARK: Error Messages

extension ScreenLock {
    private enum ErrorMessage {
        static let authenticationNotAvailable = OWSLocalizedString(
            "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_AVAILABLE",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode are not available on this device."
        )
        static let authenticationNotEnrolled = OWSLocalizedString(
            "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_ENROLLED",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode is not configured on this device."
        )
        static let passcodeNotSet = OWSLocalizedString(
            "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_PASSCODE_NOT_SET",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode passcode is not set."
        )
    }
}

public enum DeviceAuthenticationErrorMessage {
    public static let errorSheetTitle = OWSLocalizedString(
        "SCREEN_LOCK_UNLOCK_FAILED",
        comment: "Title for alert indicating that screen lock could not be unlocked."
    )

    public static let unknownError = OWSLocalizedString(
        "SCREEN_LOCK_ENABLE_UNKNOWN_ERROR",
        comment: "Indicates that an unknown error occurred while using Touch ID/Face ID/Phone Passcode."
    )

    public static let lockout = OWSLocalizedString(
        "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_LOCKOUT",
        comment: "Indicates that Touch ID/Face ID/Phone Passcode is 'locked out' on this device due to authentication failures."
    )
    public static let authenticationFailed = OWSLocalizedString(
        "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_FAILED",
        comment: "Indicates that Touch ID/Face ID/Phone Passcode authentication failed."
    )
}
