//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public enum RegistrationStep: CustomStringConvertible {

    // MARK: - Opening Steps

    case registrationSplash
    case changeNumberSplash
    case signalLoginSplash(RegistrationSignalLoginSplashState)
    case permissions

    // MARK: - Quick Restore

    /// Display a QR code similar to provisioning that, when scanned,
    /// sets up a connection for the old device to sent registration information
    /// to the new device.
    case scanQuickRegistrationQrCode

    // MARK: - Actually registering

    /// The user should enter or confirm their phone number.
    /// The number may be pre-filled or empty; either way we will require
    /// the user to confirm the number at least once before proceeding.
    /// The number may be used to send an SMS or as a way to identify the
    /// account being registered for via KBS backup info.
    case phoneNumberEntry(RegistrationPhoneNumberViewState)

    /// If registering via session, the step to enter the verification code.
    case verificationCodeEntry(RegistrationVerificationState)

    /// Prompt the user to enter ACI/AEP for registration
    case promptForLogin(RegistrationSignalLoginState)

    /// For the first time we enter the pin. This can be
    /// for first account setup, creating a pin, or if
    /// re-registering and needing to confirm the pin.
    /// When doing first time setup, the pin must be confirmed; that is
    /// considered part of this same "step" and is just a UI detail.
    case pinEntry(RegistrationPinState)

    /// All PIN attempts have been exhausted. The user may still be able to register,
    /// but they cannot recover their kbs backups.
    case pinAttemptsExhaustedWithoutReglock(RegistrationPinAttemptsExhaustedViewState)

    /// At _any_ point during session-based registration, a captcha challenge may be
    /// requested.
    case captchaChallenge

    /// If we encounter reglock, fail to recover the kbs backups (probably because
    /// PIN guesses got used up), we have no choice but to wait out the reglock.
    case reglockTimeout(RegistrationReglockTimeoutState)

    case reviewAndConfirmSignalLogin(RegistrationSignalLoginDetailsState)

    // MARK: From Backup

    /// If the user elects to restore from backup and doesn't have their old phone,
    /// they are prompted to manually enter their recovery key.
    case enterRecoveryKey(RegistrationEnterAccountEntropyPoolState)

    // MARK: - Post-Registration

    /// The path taken to get to the restore options screen
    public enum RestorePath {
        public enum BackupTier {
            case free
            case paid
        }

        public enum Platform {
            case android
            case ios
        }

        /// Restore backup, transfer from old device, small skip button
        case quickRestore(BackupTier?, Platform)
        /// Restore backup, prominent skip button
        case manualRestore
        /// Transfer from device, restore backup, prominent skip button
        case unspecified

        public var logSafeString: String {
            switch self {
            case .quickRestore(let tier, let platform):
                let tierString = tier.map { "\($0)" } ?? "unknownTier"
                return "quickRestore(\(tierString), \(platform))"
            case .manualRestore: return "manualRestore"
            case .unspecified: return "unspecified"
            }
        }
    }

    /// Prompt the user to choose from the available restore methods
    case chooseRestoreMethod(RestorePath)

    /// Prompt the user to confirm restoring from backup
    case confirmRestoreFromBackup(RegistrationRestoreFromBackupConfirmationState)

    case deviceTransfer(DeviceTransferCoordinator)

    /// If the account has not set whether its phone number should be
    /// discoverable, this step happens after registration is complete.
    /// (Typically skipped during re-registration as a result.)
    case phoneNumberDiscoverability(RegistrationPhoneNumberDiscoverabilityState)

    /// If the account has not set profile info, this step happens after registration is complete.
    /// (Typically skipped during re-registration as a result.)
    case setupProfile(RegistrationProfileState)

    // MARK: - Non-ViewController steps

    /// Special case; should display an error on the current screen, whatever it is.
    /// (If this is returned as the first step, show the splash and then this error).
    /// This sheet should be undismissable; the user must ack it to proceed, and doing
    /// so should call `RegistrationCoordinator.nextStep()`
    case showError(any Error)

    /// Special case; done with the registration flow!
    case done

    // MARK: - Logging

    public var description: String {
        switch self {
        case .registrationSplash: return "registrationSplash"
        case .changeNumberSplash: return "changeNumberSplash"
        case .signalLoginSplash: return "signalLoginSplash"
        case .permissions: return "permissions"
        case .scanQuickRegistrationQrCode: return "scanQuickRegistrationQrCode"
        case .phoneNumberEntry: return "phoneNumberEntry"
        case .verificationCodeEntry: return "verificationCodeEntry"
        case .deviceTransfer: return "deviceTransfer"
        case .promptForLogin: return "promptForLogin"
        case .pinEntry(let pinState): return "pinEntry(\(pinState.operation.logSafeString))"
        case .pinAttemptsExhaustedWithoutReglock: return "pinAttemptsExhaustedWithoutReglock"
        case .captchaChallenge: return "captchaChallenge"
        case .reglockTimeout: return "reglockTimeout"
        case .reviewAndConfirmSignalLogin: return "reviewAndConfirmSignalLogin"
        case .enterRecoveryKey: return "enterRecoveryKey"
        case .chooseRestoreMethod(let restorePath): return "chooseRestoreMethod(\(restorePath.logSafeString))"
        case .confirmRestoreFromBackup: return "confirmRestoreFromBackup"
        case .phoneNumberDiscoverability: return "phoneNumberDiscoverability"
        case .setupProfile: return "setupProfile"
        case .showError(let error): return "showError(\(error.shortDescription))"
        case .done: return "done"
        }
    }
}
