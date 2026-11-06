//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol RegistrationSessionManager {

    /// Restore any existing registration session that has not been completed and validate it with the server.
    /// If there is no session, or if the session is invalid, returns nil.
    func restoreSession(logger: PrefixedLogger) async -> RegistrationSession?

    /// Begins a new session, first attempting to restore any existing valid session for the same number.
    /// See `Registration.BeginSessionResponse` for possible responses, including errors.
    func beginOrRestoreSession(e164: E164, apnsToken: String?, logger: PrefixedLogger) async throws -> RegistrationSession

    /// Fulfill a challenge for the session (e.g. a captcha).
    func fulfillChallenge(for session: inout RegistrationSession, fulfillment: Registration.ChallengeFulfillment, logger: PrefixedLogger) async throws

    /// Request a verification code be sent to the session's phone number, for some transport.
    func requestVerificationCode(for session: inout RegistrationSession, transport: Registration.CodeTransport, logger: PrefixedLogger) async throws

    /// Submit a verification code that was previously requested.
    func submitVerificationCode(for session: inout RegistrationSession, code: String, logger: PrefixedLogger) async throws

    /// Completes a session, wiping it from future restoration.
    /// Typically called once the session is verified and is used to complete registration.
    /// Note: a session is NOT automatically completed when `RegistrationSession.verified` is true, as the registration
    /// process may be interrupted before using the verified session to actually register. (e.g. the user backgrounds the app).
    func clearPersistedSession(_ transaction: DBWriteTransaction)
}

public enum Registration {

    public enum CodeTransport: String {
        case sms
        case voice
    }

    public enum ChallengeFulfillment: Equatable {
        case captcha(String)
        case pushChallenge(String)
    }

    public static let challengeRejectedErrorCode = 403

    public struct MissingSessionError: Error {
        public init() {}
    }

    public enum RequestVerificationCodeErrorCode: Int {
        case notYetAllowed = 409
        case notEverSupported = 418
        case rateLimited = 429
    }

    public struct RequestRejectedByProviderError: Error {
        public let failureResponse: ServerFailureResponse
    }

    public enum SubmitVerificationCodeErrorCode: Int {
        case notAllowed = 409
        case rateLimited = 429
    }

    public struct CodeRejectedError: Error {
        public init() {}
    }

    public struct ServerFailureResponse: Equatable {
        /// If true, whatever failure occurred isn't likely to be resolved by retrying.
        /// Otherwise a retry after some delay is appropriate. (e.g. let the user retry)
        public let isPermanent: Bool

        public let reason: Reason?

        public enum Reason: String, Equatable {
            /// A service provider rejected sending a code to a phone number,
            /// even though it is valid, e.g. for fraud reasons.
            /// Typically requires resetting the entire session.
            case providerRejected
            /// A provider rejected a phone number as invalid.
            /// Typically requires resetting the entire session.
            case illegalArgument
            /// A provider was unavailable, typically temporary.
            case providerUnavailable
        }
    }

    // TODO: The user-visible error messages don't match the behavior.
    public enum VerificationCodeError: Error {
        /// The user tried to submit a verification code, but we've never actually
        /// sent a code, so no submission could possibly be correct.
        ///
        /// The error that's shown indicates that the code is wrong.
        case wrongCode
        /// The user can no longer submit a verification code. This could be because
        /// the previously sent code expired, or because they used up their
        /// verification code attempts. In either case, they need to send a new code
        /// to proceed.
        ///
        /// The error that's shown indicates too many attempts have been made.
        case tooManyAttempts
        /// We received a session that indicates we won't be able to use it to
        /// request a code.
        case providerFailure
    }

    public struct UnknownChallengeError: Error {
        public init() {}
    }

    /// The user had completed registration, but before finishing
    /// post-registration steps they were deregistered, likely by another device
    /// registering on the same number. The only path forward is to reset
    /// _everything_ and re-register.
    public struct BecameDeregisteredError: Error {
        public let localIdentifiers: ReregisteringLocalIdentifiers

        public init(localIdentifiers: ReregisteringLocalIdentifiers) {
            self.localIdentifiers = localIdentifiers
        }
    }

    public struct DeviceTransferPossibleError: Error {
        public init() {}
    }

    public struct SessionRejectedError: Error {
        public init() {}
    }

    public struct RecoveryPasswordRejectedError: Error {
        public init() {}
    }

    public struct ReceiptCredentialRejectedError: Error {
        public init() {}
    }

    public struct ReglockError: Error {
        public let failureResponse: RegistrationServiceResponses.RegistrationLockFailureResponse

        public init(failureResponse: RegistrationServiceResponses.RegistrationLockFailureResponse) {
            self.failureResponse = failureResponse
        }
    }
}
