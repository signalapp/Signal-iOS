//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LocalAuthentication

public struct LocalDeviceAuthentication {

    /// Describes why we're asking the user to authenticate. Presented to the
    /// user as part of the system authentication prompt.
    public enum UseCase {
        case changeScreenLockSettings
        case enableBackups
        case linkNewDevice
        case recoveryKeyReminder
        case transferAccount
        case unlockPaymentsLock
        case unlockScreenLock
        case viewRecoveryKey

        public var localizedReason: String {
            switch self {
            case .changeScreenLockSettings:
                return OWSLocalizedString(
                    "SCREEN_LOCK_REASON_CHANGE_SCREEN_LOCK_SETTINGS",
                    comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to confirm a change to the 'screen lock' settings.",
                )
            case .enableBackups:
                return OWSLocalizedString(
                    "ENABLE_BACKUPS_AUTHENTICATION_REASON",
                    comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to turn on backups.",
                )
            case .linkNewDevice:
                return OWSLocalizedString(
                    "LINK_NEW_DEVICE_AUTHENTICATION_REASON",
                    comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to unlock device linking.",
                )
            case .recoveryKeyReminder:
                return OWSLocalizedString(
                    "RECOVERY_KEY_REMINDER_AUTHENTICATION_REASON",
                    comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode during a periodic reminder to record your recovery key.",
                )
            case .transferAccount:
                return OWSLocalizedString(
                    "TRANSFER_ACCOUNT_AUTHENTICATION_REASON",
                    comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to transfer your account to a new device.",
                )
            case .unlockPaymentsLock:
                return OWSLocalizedString(
                    "PAYMENTS_LOCK_REASON_UNLOCK_PAYMENTS_LOCK",
                    comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to unlock 'payments lock'.",
                )
            case .unlockScreenLock:
                return OWSLocalizedString(
                    "SCREEN_LOCK_REASON_UNLOCK_SCREEN_LOCK",
                    comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to unlock 'screen lock'.",
                )
            case .viewRecoveryKey:
                return OWSLocalizedString(
                    "VIEW_RECOVERY_KEY_AUTHENTICATION_REASON",
                    comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to view your recovery key.",
                )
            }
        }
    }

    /// The kind of authentication the device will present to the user.
    public enum AuthenticationType {
        case unknown
        case passcode
        case faceId
        case touchId
        case opticId

        public static var current: Self {
            let context = LocalDeviceAuthentication.makeContext()

            // Calling this sets the biometryType we check below.
            context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)

            switch context.biometryType {
            case .none:
                return .passcode
            case .faceID:
                return .faceId
            case .touchID:
                return .touchId
            case .opticID:
                return .opticId
            @unknown default:
                return .unknown
            }
        }
    }

    public enum AuthError: Error {
        /// This device isn't set up for local authentication, so it can't be
        /// performed at all.
        case notConfigured(NotConfiguredReason)
        case canceled
        case failed(FailureReason)

        public enum NotConfiguredReason {
            case biometryNotAvailable
            case biometryNotEnrolled
            case passcodeNotSet
        }

        public enum FailureReason {
            case authenticationFailed
            case lockout
            case unexpected

            public var localizedErrorMessage: String {
                switch self {
                case .authenticationFailed:
                    return DeviceAuthenticationErrorMessage.authenticationFailed
                case .lockout:
                    return DeviceAuthenticationErrorMessage.lockout
                case .unexpected:
                    return DeviceAuthenticationErrorMessage.unknownError
                }
            }
        }
    }

    /// An opaque object representing successful authentication.
    public struct AuthSuccess {}

    public struct AttemptToken {}

    private let context: LAContext
    private let useCase: UseCase

    public init(useCase: UseCase) {
        self.context = Self.makeContext()
        self.useCase = useCase
    }

    private static func makeContext() -> LAContext {
        let context = LAContext()

        // Never recycle biometric auth.
        context.touchIDAuthenticationAllowableReuseDuration = TimeInterval(0)

        assert(!context.interactionNotAllowed)

        return context
    }

    // MARK: -

    public func performBiometricAuth() async -> AuthSuccess? {
        let localDeviceAuthAttemptToken: AttemptToken

        switch self.checkCanAttempt() {
        case .success(let attemptToken): localDeviceAuthAttemptToken = attemptToken
        case .failure(.notConfigured): return AuthSuccess()
        case .failure(.canceled), .failure(.failed): return nil
        }

        switch await self.attempt(token: localDeviceAuthAttemptToken) {
        case .success, .failure(.notConfigured): return AuthSuccess()
        case .failure(.canceled), .failure(.failed): return nil
        }
    }

    // MARK: -

    /// Returns whether checking local device auth is possible. Must be called
    /// prior to calling ``attempt(token:)``.
    public func checkCanAttempt() -> Result<AttemptToken, AuthError> {
        var error: NSError?
        let canEvaluatePolicy = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)

        guard canEvaluatePolicy, error == nil else {
            return .failure(parseAuthError(error))
        }

        return .success(AttemptToken())
    }

    /// Returns the result of performing local device authentication. Must be
    /// called after calling ``checkCanAttempt()``.
    public func attempt(token: AttemptToken) async -> Result<AuthSuccess, AuthError> {
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: useCase.localizedReason,
            )

            return .success(AuthSuccess())
        } catch {
            return .failure(parseAuthError(error))
        }
    }

    private func parseAuthError(_ error: Error?) -> AuthError {
        guard
            let error,
            let laError = error as? LAError
        else {
            owsFailDebug("Unexpected or missing auth error: \(error as Optional)")
            return .failed(.unexpected)
        }

        switch laError.code {
        case .biometryNotAvailable, .touchIDNotAvailable:
            return .notConfigured(.biometryNotAvailable)
        case .biometryNotEnrolled, .touchIDNotEnrolled:
            return .notConfigured(.biometryNotEnrolled)
        case .passcodeNotSet:
            return .notConfigured(.passcodeNotSet)
        case
            .userCancel,
            .userFallback,
            .systemCancel,
            .appCancel:
            return .canceled
        case .biometryLockout, .touchIDLockout:
            return .failed(.lockout)
        case .authenticationFailed:
            return .failed(.authenticationFailed)
        case .invalidContext:
            owsFailDebug("Context not valid.")
            return .failed(.unexpected)
        case .notInteractive:
            owsFailDebug("Context not interactive!")
            return .failed(.unexpected)
        case .companionNotAvailable:
            owsFailDebug("Companion device not available.")
            return .failed(.unexpected)
        @unknown default:
            owsFailDebug("Unexpected LAContext error code: \(laError.code)")
            return .failed(.unexpected)
        }
    }
}
