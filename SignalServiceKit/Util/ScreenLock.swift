//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class ScreenLock: NSObject {

    public enum Outcome {
        case success
        case cancel
        case failure(localizedErrorMessage: String)
        case unexpectedFailure
    }

    public static let screenLockTimeoutDefault: TimeInterval = 15 * .minute

    public let screenLockTimeouts: [TimeInterval] = [
        1 * .minute,
        5 * .minute,
        15 * .minute,
        30 * .minute,
        1 * .hour,
        0,
    ]

    public static let ScreenLockDidChange = Notification.Name("ScreenLockDidChange")

    private static let OWSScreenLock_Key_IsScreenLockEnabled = "OWSScreenLock_Key_IsScreenLockEnabled"
    private static let OWSScreenLock_Key_ScreenLockTimeoutSeconds = "OWSScreenLock_Key_ScreenLockTimeoutSeconds"

    // MARK: - Singleton class

    public static let shared = ScreenLock()

    override private init() {
        super.init()

    }

    // MARK: - KV Store

    public let keyValueStore = KeyValueStore(collection: "OWSScreenLock_Collection")

    // MARK: - Properties

    public func isScreenLockEnabled() -> Bool {
        AssertIsOnMainThread()

        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return isScreenLockEnabled(tx: transaction)
        }
    }

    public func isScreenLockEnabled(tx: DBReadTransaction) -> Bool {
        return self.keyValueStore.getBool(
            ScreenLock.OWSScreenLock_Key_IsScreenLockEnabled,
            defaultValue: false,
            transaction: tx,
        )
    }

    public func setIsScreenLockEnabled(_ value: Bool) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            setIsScreenLockEnabled(value, tx: transaction)
        }

        NotificationCenter.default.postOnMainThread(name: ScreenLock.ScreenLockDidChange, object: nil)
    }

    public func setIsScreenLockEnabled(_ value: Bool, tx: DBWriteTransaction) {
        self.keyValueStore.setBool(
            value,
            key: ScreenLock.OWSScreenLock_Key_IsScreenLockEnabled,
            transaction: tx,
        )
    }

    public func screenLockTimeout() -> TimeInterval {
        AssertIsOnMainThread()

        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return screenLockTimeout(tx: transaction)
        }
    }

    public func screenLockTimeout(tx: DBReadTransaction) -> TimeInterval {
        return self.keyValueStore.getDouble(
            ScreenLock.OWSScreenLock_Key_ScreenLockTimeoutSeconds,
            defaultValue: ScreenLock.screenLockTimeoutDefault,
            transaction: tx,
        )
    }

    public func setScreenLockTimeout(_ value: TimeInterval) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            setScreenLockTimeout(value, tx: transaction)
        }

        NotificationCenter.default.postOnMainThread(name: ScreenLock.ScreenLockDidChange, object: nil)
    }

    public func setScreenLockTimeout(_ value: TimeInterval, tx: DBWriteTransaction) {
        self.keyValueStore.setDouble(
            value,
            key: ScreenLock.OWSScreenLock_Key_ScreenLockTimeoutSeconds,
            transaction: tx,
        )
    }

    // MARK: - Methods

    /// Authenticates in order to unlock the app.
    public func tryToUnlockScreenLock() async -> Outcome {
        return await tryToAuthenticate(useCase: .unlockScreenLock)
    }

    /// Authenticates in order to change the screen lock settings themselves,
    /// e.g. to turn screen lock off or to lengthen its timeout.
    public func tryToUnlockScreenLockSettings() async -> Outcome {
        return await tryToAuthenticate(useCase: .changeScreenLockSettings)
    }

    private func tryToAuthenticate(
        useCase: LocalDeviceAuthentication.UseCase,
    ) async -> Outcome {
        let localDeviceAuth = LocalDeviceAuthentication(useCase: useCase)

        let authError: LocalDeviceAuthentication.AuthError
        switch localDeviceAuth.checkCanAttempt() {
        case .success(let attemptToken):
            switch await localDeviceAuth.attempt(token: attemptToken) {
            case .success:
                Logger.info("local authentication succeeded.")
                return .success
            case .failure(let error):
                authError = error
            }
        case .failure(let error):
            authError = error
        }

        return outcomeForAuthError(authError)
    }

    // MARK: - Outcome

    private func outcomeForAuthError(
        _ authError: LocalDeviceAuthentication.AuthError,
    ) -> Outcome {
        switch authError {
        case .notConfigured(.biometryNotAvailable):
            Logger.error("local authentication error: biometryNotAvailable.")
            return .failure(localizedErrorMessage: ScreenLock.ErrorMessage.authenticationNotAvailable)
        case .notConfigured(.biometryNotEnrolled):
            Logger.error("local authentication error: biometryNotEnrolled.")
            return .failure(localizedErrorMessage: ScreenLock.ErrorMessage.authenticationNotEnrolled)
        case .notConfigured(.passcodeNotSet):
            Logger.error("local authentication error: passcodeNotSet.")
            return .failure(localizedErrorMessage: ScreenLock.ErrorMessage.passcodeNotSet)
        case .failed(.lockout):
            Logger.error("local authentication error: lockout.")
            return .failure(localizedErrorMessage: DeviceAuthenticationErrorMessage.lockout)
        case .failed(.authenticationFailed):
            Logger.error("local authentication error: authenticationFailed.")
            return .failure(localizedErrorMessage: DeviceAuthenticationErrorMessage.authenticationFailed)
        case .canceled:
            Logger.info("local authentication cancelled.")
            return .cancel
        case .failed(.unexpected):
            Logger.error("local authentication error: unexpected.")
            return .unexpectedFailure
        }
    }
}

// MARK: Error Messages

extension ScreenLock {
    private enum ErrorMessage {
        static let authenticationNotAvailable = OWSLocalizedString(
            "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_AVAILABLE",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode are not available on this device.",
        )
        static let authenticationNotEnrolled = OWSLocalizedString(
            "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_ENROLLED",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode is not configured on this device.",
        )
        static let passcodeNotSet = OWSLocalizedString(
            "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_PASSCODE_NOT_SET",
            comment: "Indicates that Touch ID/Face ID/Phone Passcode passcode is not set.",
        )
    }
}

public enum DeviceAuthenticationErrorMessage {
    public static let errorSheetTitle = OWSLocalizedString(
        "SCREEN_LOCK_UNLOCK_FAILED",
        comment: "Title for alert indicating that screen lock could not be unlocked.",
    )

    public static let unknownError = OWSLocalizedString(
        "SCREEN_LOCK_ENABLE_UNKNOWN_ERROR",
        comment: "Indicates that an unknown error occurred while using Touch ID/Face ID/Phone Passcode.",
    )

    public static let lockout = OWSLocalizedString(
        "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_LOCKOUT",
        comment: "Indicates that Touch ID/Face ID/Phone Passcode is 'locked out' on this device due to authentication failures.",
    )
    public static let authenticationFailed = OWSLocalizedString(
        "SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_FAILED",
        comment: "Indicates that Touch ID/Face ID/Phone Passcode authentication failed.",
    )
}
