//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class OWSPaymentsLock {

    public enum LocalAuthOutcome: Equatable {
        case success
        case cancel
        case disabled
        case failure(error: String)
        case unexpectedFailure(error: String)
    }

    // MARK: - Singleton class

    private let appReadiness: AppReadiness

    init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
    }

    // MARK: - KV Store

    private let keyValueStore = KeyValueStore(collection: "OWSPaymentsLock")

    // MARK: - Properties

    public func isPaymentsLockEnabled() -> Bool {
        AssertIsOnMainThread()

        guard appReadiness.isAppReady else {
            owsFailDebug("accessed payments lock state before storage is ready.")
            // `true` is a more secure default
            return true
        }

        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return self.keyValueStore.getBool(
                .isPaymentsLockEnabledKey,
                defaultValue: false,
                transaction: transaction,
            )
        }
    }

    public func setIsPaymentsLockEnabledAndSnooze(_ value: Bool) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            setIsPaymentsLockEnabled(value, transaction: transaction)
            snoozeSuggestion(transaction: transaction)
        }
    }

    public func setIsPaymentsLockEnabled(_ value: Bool, transaction: DBWriteTransaction) {
        AssertIsOnMainThread()
        assert(appReadiness.isAppReady)

        self.keyValueStore.setBool(
            value,
            key: .isPaymentsLockEnabledKey,
            transaction: transaction,
        )
    }

    public func isTimeToShowSuggestion() -> Bool {
        AssertIsOnMainThread()

        if !appReadiness.isAppReady {
            owsFailDebug("accessed payments lock state before storage is ready.")
            return false
        }

        let defaultDate = Date.distantPast
        let date = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return self.keyValueStore.getDate(
                .timeToShowSuggestionKey,
                transaction: transaction,
            ) ?? defaultDate
        }

        return Date() > date
    }

    public func snoozeSuggestion(transaction: DBWriteTransaction) {
        AssertIsOnMainThread()
        assert(appReadiness.isAppReady)

        let currentDate = Date()
        let numberOfSnoozeDays = 30.0
        let nextTimeToShowSuggestion = currentDate.addingTimeInterval(
            Double(numberOfSnoozeDays * .day),
        )

        self.keyValueStore.setDate(
            nextTimeToShowSuggestion,
            key: .timeToShowSuggestionKey,
            transaction: transaction,
        )
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
        completion completionParam: @escaping ((LocalAuthOutcome) -> Void),
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

        let localDeviceAuth = LocalDeviceAuthentication(useCase: .unlockPaymentsLock)

        let attemptToken: LocalDeviceAuthentication.AttemptToken
        switch localDeviceAuth.checkCanAttempt() {
        case .success(let token):
            attemptToken = token
        case .failure(let authError):
            Logger.error("could not attempt local authentication: \(authError)")
            completion(LocalAuthOutcome.outcomeFromAuthError(
                authError,
                defaultErrorDescription: .localizedDefaultErrorDescription,
            ))
            return
        }

        Task {
            switch await localDeviceAuth.attempt(token: attemptToken) {
            case .success:
                Logger.info("local authentication succeeded.")
                completion(.success)
            case .failure(let authError):
                completion(LocalAuthOutcome.outcomeFromAuthError(
                    authError,
                    defaultErrorDescription: .localizedDefaultErrorDescription,
                ))
            }
        }
    }

    @MainActor
    public func tryToUnlock() async -> OWSPaymentsLock.LocalAuthOutcome {
        return await withCheckedContinuation { continuation in
            self.tryToUnlock(completion: { continuation.resume(returning: $0) })
        }
    }
}

// MARK: - File-Specific Constants & Computed Values

private extension String {
    static let isPaymentsLockEnabledKey = "isPaymentsLockEnabled"
    static let timeToShowSuggestionKey = "timeToShowSuggestion"

    // Localized String Constants

    static var localizedDefaultErrorDescription: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_AUTHENTICATION_ENABLE_UNKNOWN_ERROR",
            comment: "Indicates that an unknown error occurred while using Touch ID/Face ID/Phone Passcode.",
        )
    }

}

private extension OWSPaymentsLock.LocalAuthOutcome {
    static func outcomeFromAuthError(
        _ authError: LocalDeviceAuthentication.AuthError,
        defaultErrorDescription: String,
    ) -> OWSPaymentsLock.LocalAuthOutcome {
        switch authError {
        case .notConfigured(.biometryNotAvailable):
            Logger.error("local authentication error: biometryNotAvailable.")
            return .failure(error: .notAvailableLocalized)
        case .notConfigured(.biometryNotEnrolled):
            Logger.error("local authentication error: biometryNotEnrolled.")
            return .failure(error: .notEnrolledLocalized)
        case .notConfigured(.passcodeNotSet):
            Logger.error("local authentication error: passcodeNotSet.")
            return .failure(error: .passcodeNotSetLocalized)
        case .failed(.lockout):
            Logger.error("local authentication error: lockout.")
            return .failure(error: .lockoutLocalized)
        case .failed(.authenticationFailed):
            Logger.error("local authentication error: authenticationFailed.")
            return .failure(error: .authenticationFailedLocalized)
        case .canceled:
            Logger.info("local authentication cancelled.")
            return .cancel
        case .failed(.unexpected):
            return .unexpectedFailure(error: defaultErrorDescription)
        }
    }
}

private extension String {

    // Localized Error Descriptions

    static var authenticationFailedLocalized: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_ERROR_LOCAL_AUTHENTICATION_FAILED",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode authentication failed.",
        )
    }

    static var passcodeNotSetLocalized: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_ERROR_LOCAL_AUTHENTICATION_PASSCODE_NOT_SET",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode passcode is not set.",
        )
    }

    static var notAvailableLocalized: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_AVAILABLE",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode are not available on this device.",
        )
    }

    static var notEnrolledLocalized: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_ENROLLED",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode is not configured on this device.",
        )
    }

    static var lockoutLocalized: String {
        OWSLocalizedString(
            "PAYMENTS_LOCK_ERROR_LOCAL_AUTHENTICATION_LOCKOUT",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode is 'locked out' on this device due to authentication failures.",
        )
    }
}
