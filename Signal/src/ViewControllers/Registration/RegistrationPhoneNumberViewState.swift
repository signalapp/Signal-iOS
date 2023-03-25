//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
    }

    public struct Reregistration: Equatable {
        let e164: E164
        let validationError: ValidationError?
    }

    public struct ChangeNumberInitialEntry: Equatable {
        let oldE164: E164
        let newE164: E164?
        let hasConfirmed: Bool
        let invalidNumberError: ValidationError.InvalidNumber?
    }

    public struct ChangeNumberConfirmation: Equatable {
        let oldE164: E164
        let newE164: E164
        let rateLimitedError: ValidationError.RateLimited?
    }

    public enum ValidationError: Equatable {
        case invalidNumber(InvalidNumber)
        case rateLimited(RateLimited)

        public struct InvalidNumber: Equatable {
            let invalidE164: E164
        }

        public struct RateLimited: Equatable {
            let expiration: Date
        }
    }
}

extension RegistrationPhoneNumberViewState.ValidationError {

    func canSubmit(e164: E164, dateProvider: DateProvider) -> Bool {
        switch self {
        case let .invalidNumber(error):
            return error.canSubmit(e164: e164)
        case let .rateLimited(error):
            return error.canSubmit(dateProvider: dateProvider)
        }
    }

    func warningLabelText(dateProvider: DateProvider) -> String? {
        switch self {
        case .invalidNumber(let error):
            return error.warningLabelText
        case let .rateLimited(error):
            return error.warningLabelText(dateProvider: dateProvider)
        }
    }
}

extension RegistrationPhoneNumberViewState.ValidationError.InvalidNumber {

    func canSubmit(e164: E164) -> Bool {
        return e164 != invalidE164
    }

    var warningLabelText: String {
        return OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_VALIDATION_WARNING",
            comment: "Label indicating that the phone number is invalid in the 'onboarding phone number' view."
        )
    }
}

extension RegistrationPhoneNumberViewState.ValidationError.RateLimited {

    func canSubmit(dateProvider: DateProvider) -> Bool {
        return dateProvider() >= expiration
    }

    func warningLabelText(dateProvider: DateProvider) -> String? {
        let now = dateProvider()
        if now >= expiration {
            return nil
        }
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
