//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public enum RegistrationPhoneNumberViewState: Equatable {

    case registration(RegistrationMode)
    case changingNumber(ChangingNumberMode)

    public enum RegistrationMode: Equatable {
        case initialRegistration(InitialRegistration)
        case reregistration(Reregistration)
    }

    public enum ChangingNumberMode: Equatable {
        case initialEntry(ChangeNumberInitialEntry)
        case confirmation(ChangeNumberConfirmation)
    }

    public struct InitialRegistration: Equatable {
        /// previouslyEnteredE164 is if the user entered a number, quit, and came back.
        /// Will be used to pre-populate the entry field.
        let previouslyEnteredE164: E164?
        let validationError: ValidationError?
        let canExitRegistration: Bool
    }

    public struct Reregistration: Equatable {
        let e164: E164
        let validationError: ValidationError?
        let canExitRegistration: Bool
    }

    public struct ChangeNumberInitialEntry: Equatable {
        let oldE164: E164
        let newE164: E164?
        let hasConfirmed: Bool
        let invalidE164Error: ValidationError.InvalidE164?
    }

    public struct ChangeNumberConfirmation: Equatable {
        let oldE164: E164
        let newE164: E164
        let rateLimitedError: ValidationError.RateLimited?
    }

    public enum ValidationError: Equatable {
        case invalidInput(InvalidInput)
        case invalidE164(InvalidE164)
        case rateLimited(RateLimited)

        /// The user typed something that couldn't be parsed.
        public struct InvalidInput: Equatable {
            let invalidCountryCode: String
            let invalidNationalNumber: String
        }

        /// The user submitted something that could be parsed, but local or server
        /// validation rejected it as not a valid number for registration.
        public struct InvalidE164: Equatable {
            let invalidE164: E164
        }

        public struct RateLimited: Equatable {
            let expiration: Date
            let e164: E164
        }
    }
}

extension RegistrationPhoneNumberViewState.ValidationError {

    func warningLabelText(dateProvider: DateProvider) -> String? {
        switch self {
        case let .invalidInput(error):
            return error.warningLabelText()
        case let .invalidE164(error):
            return error.warningLabelText()
        case let .rateLimited(error):
            return error.warningLabelText(dateProvider: dateProvider)
        }
    }
}

extension RegistrationPhoneNumberViewState.ValidationError.InvalidInput {

    func canSubmit(countryCode: String, nationalNumber: String) -> Bool {
        return countryCode != invalidCountryCode || nationalNumber != invalidNationalNumber
    }

    func warningLabelText() -> String {
        return OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_VALIDATION_WARNING",
            comment: "Label indicating that the phone number is invalid in the 'onboarding phone number' view."
        )
    }
}

extension RegistrationPhoneNumberViewState.ValidationError.InvalidE164 {

    func canSubmit(e164: E164?) -> Bool {
        return e164 != invalidE164
    }

    func warningLabelText() -> String {
        return OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_VALIDATION_WARNING",
            comment: "Label indicating that the phone number is invalid in the 'onboarding phone number' view."
        )
    }
}

extension RegistrationPhoneNumberViewState.ValidationError.RateLimited {

    func canSubmit(e164: E164?, dateProvider: DateProvider) -> Bool {
        return dateProvider() >= expiration || e164 != self.e164
    }

    func warningLabelText(dateProvider: DateProvider) -> String {
        let now = dateProvider()
        let rateLimitFormat = OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_RATE_LIMIT_WARNING_FORMAT",
            comment: "Label indicating that registration has been ratelimited. Embeds {{remaining time string}}."
        )

        let retryAfterFormatter: DateFormatter = {
            let result = DateFormatter()
            result.dateFormat = "m:ss"
            result.timeZone = TimeZone(identifier: "UTC")!
            return result
        }()

        let timeRemaining = max(expiration.timeIntervalSince(now), 0)
        let durationString = retryAfterFormatter.string(from: Date(timeIntervalSinceReferenceDate: timeRemaining))
        return String(format: rateLimitFormat, durationString)
    }
}
