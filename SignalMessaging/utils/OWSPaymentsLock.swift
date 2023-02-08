//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LocalAuthentication

public class OWSPaymentsLock: Dependencies {

    public enum LocalAuthOutcome: Equatable {
        case success
        case cancel
        case disabled
        case failure(error: String)
        case unexpectedFailure(error: String)
    }

    // MARK: - Singleton class

    public static let shared = OWSPaymentsLock()

    init() {
        SwiftSingletons.register(self)
    }

    // MARK: - KV Store

    private let keyValueStore = SDSKeyValueStore(collection: "OWSPaymentsLock")

    // MARK: - Properties

    public func isPaymentsLockEnabled() -> Bool {
        AssertIsOnMainThread()

        guard AppReadiness.isAppReady else {
            owsFailDebug("accessed payments lock state before storage is ready.")
            // `true` is a more secure default
            return true
        }

        return databaseStorage.read { transaction in
            return self.keyValueStore.getBool(.isPaymentsLockEnabledKey,
                                              defaultValue: false,
                                              transaction: transaction)
        }
    }

    public func setIsPaymentsLockEnabledAndSnooze(_ value: Bool) {
        databaseStorage.write { transaction in
            setIsPaymentsLockEnabled(value, transaction: transaction)
            snoozeSuggestion(transaction: transaction)
        }
    }

    public func setIsPaymentsLockEnabled(_ value: Bool, transaction: SDSAnyWriteTransaction) {
        AssertIsOnMainThread()
        assert(AppReadiness.isAppReady)

        self.keyValueStore.setBool(value,
                                   key: .isPaymentsLockEnabledKey,
                                   transaction: transaction)
    }

    public func isTimeToShowSuggestion() -> Bool {
        AssertIsOnMainThread()

        if !AppReadiness.isAppReady {
            owsFailDebug("accessed payments lock state before storage is ready.")
            return false
        }

        let defaultDate = Date.distantPast
        let date = databaseStorage.read { transaction in
            return self.keyValueStore.getDate(.timeToShowSuggestionKey,
                                              transaction: transaction) ?? defaultDate
        }

        return Date() > date
    }

    public func snoozeSuggestion(transaction: SDSAnyWriteTransaction) {
        AssertIsOnMainThread()
        assert(AppReadiness.isAppReady)

        let currentDate = Date()
        let numberOfSnoozeDays = 30.0
        let nextTimeToShowSuggestion = currentDate.addingTimeInterval(
            Double(numberOfSnoozeDays * kDayInterval)
        )

        self.keyValueStore.setDate(nextTimeToShowSuggestion,
                                   key: .timeToShowSuggestionKey,
                                   transaction: transaction)
    }

    // MARK: - Biometry Types

    // This method should only be called:
    //
    // * On the main thread.
    //
    // completionParam will be performed:
    //
    // * Asynchronously.
    // * On the main thread.
    public func tryToUnlock(
        completion completionParam: @escaping ((LocalAuthOutcome) -> Void)
    ) {
        AssertIsOnMainThread()

        // Ensure completion is always called on the main thread.
        let completion = { (outcome: LocalAuthOutcome) in
            DispatchQueue.main.async {
                completionParam(outcome)
            }
        }

        guard self.isPaymentsLockEnabled() else {
            completion(.disabled)
            return
        }

        let context = BiometryType.localAuthenticationContext()

        var authError: NSError?
        let canEvaluatePolicy = context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &authError)

        guard canEvaluatePolicy && authError == nil else {
            Logger.error("could not determine if local authentication is supported: " +
                         "\(String(describing: authError))")

            let outcome = outcomeForLAError(errorParam: authError)
            switch outcome {
            case .success:
                owsFailDebug("local authentication unexpected success")
                completion(.failure(error: .localizedDefaultErrorDescription))
            case .cancel, .failure, .unexpectedFailure, .disabled:
                completion(outcome)
            }
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: .localizedAuthReason
        ) { success, evaluateError in

            guard success else {
                let outcome = self.outcomeForLAError(errorParam: evaluateError)
                switch outcome {
                case .success:
                    owsFailDebug("local authentication unexpected success")
                    completion(.failure(error: .localizedDefaultErrorDescription))
                case .cancel, .failure, .unexpectedFailure, .disabled:
                    completion(outcome)
                }
                return
            }

            Logger.info("local authentication succeeded.")
            completion(.success)
        }
    }

    public func tryToUnlockPromise() -> Promise<OWSPaymentsLock.LocalAuthOutcome> {
        Promise<OWSPaymentsLock.LocalAuthOutcome>(on: DispatchQueue.main) { future in
            OWSPaymentsLock.shared.tryToUnlock { outcome in
                future.resolve(outcome)
            }
        }
    }

    // MARK: - Outcome

    private func outcomeForLAError(errorParam: Error?) -> LocalAuthOutcome {
        guard let error = errorParam,
              let laError = error as? LAError
        else {
            return .failure(error: .localizedDefaultErrorDescription)
        }

        return LocalAuthOutcome.outcomeFromLAError(
            laError,
            defaultErrorDescription: .localizedDefaultErrorDescription)
    }
}

// MARK: - File-Specific Constants & Computed Values

fileprivate extension String {
    static let isPaymentsLockEnabledKey = "isPaymentsLockEnabled"
    static let timeToShowSuggestionKey = "timeToShowSuggestion"

    // Localized String Constants

    static var localizedDefaultErrorDescription: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_AUTHENTICATION_ENABLE_UNKNOWN_ERROR",
            comment: "Indicates that an unknown error occurred while using Touch ID/Face ID/Phone Passcode.")
    }

    static var localizedAuthReason: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_REASON_UNLOCK_PAYMENTS_LOCK",
            comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to unlock 'payments lock'.")
    }

}

fileprivate extension OWSPaymentsLock.LocalAuthOutcome {
    static func outcomeFromLAError(
        _ laError: LAError,
        defaultErrorDescription: String
    ) -> OWSPaymentsLock.LocalAuthOutcome {
        switch laError.code {
        case .biometryNotAvailable:
            Logger.error("local authentication error: biometryNotAvailable.")
            return .failure(error: LAError.notAvailableLocalized)
        case .biometryNotEnrolled:
            Logger.error("local authentication error: biometryNotEnrolled.")
            return .failure(error: LAError.notEnrolledLocalized)
        case .biometryLockout:
            Logger.error("local authentication error: biometryLockout.")
            return .failure(error: LAError.lockoutLocalized)
        case .authenticationFailed:
            Logger.error("local authentication error: authenticationFailed.")
            return .failure(error: LAError.authenticationFailedLocalized)
        case .passcodeNotSet:
            Logger.error("local authentication error: passcodeNotSet.")
            return .failure(error: LAError.passcodeNotSetLocalized)
        case .touchIDNotAvailable:
            Logger.error("local authentication error: touchIDNotAvailable.")
            return .failure(error: LAError.notAvailableLocalized)
        case .touchIDNotEnrolled:
            Logger.error("local authentication error: touchIDNotEnrolled.")
            return .failure(error: LAError.notEnrolledLocalized)
        case .touchIDLockout:
            Logger.error("local authentication error: touchIDLockout.")
            return .failure(error: LAError.lockoutLocalized)
        case .userCancel, .userFallback, .systemCancel, .appCancel:
            Logger.info("local authentication cancelled.")
            return .cancel
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
}

fileprivate extension LAError {

    // Localized LAError Descriptions

    static var authenticationFailedLocalized: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_ERROR_LOCAL_AUTHENTICATION_FAILED",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode authentication failed.")
    }

    static var passcodeNotSetLocalized: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_ERROR_LOCAL_AUTHENTICATION_PASSCODE_NOT_SET",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode passcode is not set.")
    }

    static var notAvailableLocalized: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_AVAILABLE",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode are not available on this device.")
    }

    static var notEnrolledLocalized: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_ENROLLED",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode is not configured on this device.")
    }

    static var lockoutLocalized: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_ERROR_LOCAL_AUTHENTICATION_LOCKOUT",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode is 'locked out' on this device due to authentication failures.")
    }
}
