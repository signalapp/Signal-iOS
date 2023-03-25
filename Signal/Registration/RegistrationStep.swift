//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum RegistrationStep: Equatable {

    // MARK: - Opening Steps
    case registrationSplash
    case changeNumberSplash
    case permissions(RegistrationPermissionsState)

    // MARK: - Actually registering

    /// The user should enter or confirm their phone number.
    /// The number may be pre-filled or empty; either way we will require
    /// the user to confirm the number at least once before proceeding.
    /// The number may be used to send an SMS or as a way to identify the
    /// account being registered for via KBS backup info.
    case phoneNumberEntry(RegistrationPhoneNumberViewState)

    /// If registering via session, the step to enter the verification code.
    case verificationCodeEntry(RegistrationVerificationState)

    /// When registering, the server can inform the client that a device-to-device
    /// transfer is possible. If so, the user must either do the transfer, or explicitly
    /// elect not to. This step presents those options to the user.
    /// Only happens if registering on a new device without local data.
    case transferSelection

    /// For the first time we enter the pin. This can be
    /// for first account setup, creating a pin, or if
    /// re-registering and needing to confirm the pin.
    /// When doing first time setup, the pin must be confirmed; that is
    /// considered part of this same "step" and is just a UI detail.
    case pinEntry(RegistrationPinState)

    /// At _any_ point during session-based registration, a captcha challenge may be
    /// requested.
    case captchaChallenge

    /// If we encounter reglock, fail to recover the kbs backups (probably because
    /// PIN guesses got used up), we have no choice but to wait out the reglock.
    case reglockTimeout(RegistrationReglockTimeoutState)

    // MARK: - Post-Registration

    /// If the account has not set whether its phone number should be
    /// discoverable, this step happens after registration is complete.
    /// (Typically skipped during re-registration as a result.)
    case phoneNumberDiscoverability(RegistrationPhoneNumberDiscoverabilityState)

    /// If the account has not set profile info, this step happens after registration is complete.
    /// (Typically skipped during re-registration as a result.)
    case setupProfile(RegistrationProfileState)

    // MARK: - Non-ViewController steps

    public enum ErrorSheet: Equatable {
        /// We should tell the user their attempt has expired
        /// and they need to start over.
        case sessionInvalidated
        /// The user can no longer submit a verification code.
        /// This could be because the previously sent code expired,
        /// or because they used up their verification code attempts.
        /// In either case, they need to send a new code to proceed.
        case verificationCodeSubmissionUnavailable
        /// All PIN guesses have been exhausted, locking the user out
        /// of their KBS backups.
        case pinGuessesExhausted
        /// A network error occurred. The user can probably fix this by
        /// checking their internet connection.
        case networkError
        /// A generic error occurred. Prefer to use other error types.
        case genericError
        // TODO[Registration]: define other error types.
        case todo
    }

    /// Special cases; should display an error on the current screen, whatever it is.
    /// (If this is returned as the first step, show the splash and then this error).
    case showErrorSheet(ErrorSheet)

    /// Special case, should display a banner on the current screen, whatever it is.
    /// Happens if we get a response from the server we can't parse; we assume this means
    /// an app version update is needed to parse it.
    /// (If this is returned as the first step, show the splash and then this error).
    case appUpdateBanner

    /// Special case; done with the registration flow!
    case done
}
