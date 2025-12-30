//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LocalAuthentication

public struct LocalDeviceAuthentication {
    public enum AuthError: Error {
        case notRequired
        case canceled
        case genericError(localizedErrorMessage: String)
    }

    /// An opaque object representing successful authentication.
    public struct AuthSuccess {}

    public struct AttemptToken {}

    private let context: LAContext

    public init() {
        context = DeviceOwnerAuthenticationType.localAuthenticationContext()
    }

    // MARK: -

    public func performBiometricAuth() async -> AuthSuccess? {
        let localDeviceAuthAttemptToken: AttemptToken

        switch self.checkCanAttempt() {
        case .success(let attemptToken): localDeviceAuthAttemptToken = attemptToken
        case .failure(.notRequired): return AuthSuccess()
        case .failure(.canceled), .failure(.genericError): return nil
        }

        switch await self.attempt(token: localDeviceAuthAttemptToken) {
        case .success, .failure(.notRequired): return AuthSuccess()
        case .failure(.canceled), .failure(.genericError): return nil
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
                localizedReason: OWSLocalizedString(
                    "LINK_NEW_DEVICE_AUTHENTICATION_REASON",
                    comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to unlock device linking.",
                ),
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
            return .genericError(localizedErrorMessage: DeviceAuthenticationErrorMessage.unknownError)
        }

        switch laError.code {
        case
            .biometryNotAvailable,
            .biometryNotEnrolled,
            .passcodeNotSet,
            .touchIDNotAvailable,
            .touchIDNotEnrolled:
            return .notRequired
        case
            .userCancel,
            .userFallback,
            .systemCancel,
            .appCancel:
            return .canceled
        case .biometryLockout, .touchIDLockout:
            return .genericError(localizedErrorMessage: DeviceAuthenticationErrorMessage.lockout)
        case .authenticationFailed:
            return .genericError(localizedErrorMessage: DeviceAuthenticationErrorMessage.authenticationFailed)
        case .invalidContext:
            owsFailDebug("Context not valid.")
            return .genericError(localizedErrorMessage: DeviceAuthenticationErrorMessage.unknownError)
        case .notInteractive:
            owsFailDebug("Context not interactive!")
            return .genericError(localizedErrorMessage: DeviceAuthenticationErrorMessage.unknownError)
        case .companionNotAvailable:
            owsFailDebug("Companion device not available.")
            return .genericError(localizedErrorMessage: DeviceAuthenticationErrorMessage.unknownError)
        @unknown default:
            owsFailDebug("Unexpected LAContext error code: \(laError.code)")
            return .genericError(localizedErrorMessage: DeviceAuthenticationErrorMessage.unknownError)
        }
    }
}
