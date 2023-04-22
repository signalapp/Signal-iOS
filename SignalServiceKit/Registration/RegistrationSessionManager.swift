//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol RegistrationSessionManager {

    /// Restore any existing registration session that has not been completed and validate it with the server.
    /// If there is no session, or if the session is invalid, returns nil.
    func restoreSession() -> Guarantee<RegistrationSession?>

    /// Begins a new session, first attempting to restore any existing valid session for the same number.
    /// See `Registration.BeginSessionResponse` for possible responses, including errors.
    func beginOrRestoreSession(e164: E164, apnsToken: String?) -> Guarantee<Registration.BeginSessionResponse>

    /// Fulfill a challenge for the session (e.g. a captcha).
    /// See `Registration.UpdateSessionResponse` for possible responses, including errors.
    func fulfillChallenge(for session: RegistrationSession, fulfillment: Registration.ChallengeFulfillment) -> Guarantee<Registration.UpdateSessionResponse>

    /// Request a verification code be sent to the session's phone number, for some transport.
    /// See `Registration.UpdateSessionResponse` for possible responses, including errors.
    func requestVerificationCode(for session: RegistrationSession, transport: Registration.CodeTransport) -> Guarantee<Registration.UpdateSessionResponse>

    /// Submit a verification code that was previously requested.
    /// See `Registration.UpdateSessionResponse` for possible responses, including errors.
    func submitVerificationCode(for session: RegistrationSession, code: String) -> Guarantee<Registration.UpdateSessionResponse>

    /// Completes a session, wiping it from future restoration.
    /// Typically called once the session is verified and is used to complete registration.
    /// Note: a session is NOT automatically completed when `RegistrationSession.verified` is true, as the registration
    /// process may be interrupted before using the verified session to actually register. (e.g. the user backgrounds the app).
    func clearPersistedSession(_ transaction: DBWriteTransaction)
}

public enum Registration {

    public enum CodeTransport: String, Equatable {
        case sms
        case voice
    }

    public enum ChallengeFulfillment: Equatable {
        case captcha(String)
        case pushChallenge(String)
    }

    public enum BeginSessionResponse: Equatable {
        case success(RegistrationSession)
        /// Typically, invalid e164.
        case invalidArgument
        /// The server indicated the client should retry after at least this much time has passed.
        case retryAfter(TimeInterval)
        /// A network failure.
        case networkFailure
        /// Some other generic unknown error.
        case genericError
    }

    /// Collapses a few different error responses possible from the server down to only those
    /// relevant to the registration flow, in other words those that should have distinct error behaviors.
    public enum UpdateSessionResponse: Equatable {
        case success(RegistrationSession)
        /// Some input was incorrect or otherwise rejected; typically
        /// should have the user update and retry.
        /// `RegistrationSession` state should be checked regardless, as
        /// (for example) a new challenge may have been requested.
        case rejectedArgument(RegistrationSession)
        /// This happens when the attempted operation cannot be fulfilled
        /// given the current session state, and a different operation must
        /// be completed first, such as a challenge.
        /// For example, a verification code may have been submitted
        /// despite no code being available for submission.
        case disallowed(RegistrationSession)
        /// The request was made before the required timeout; it should be
        /// made again after the time specified in the `RegistrationSession`.
        case retryAfterTimeout(RegistrationSession)
        /// The provided session has timed out or is otherwise invalid, and a new
        /// session needs to be started, throwing away all current session state.
        case invalidSession
        /// Something went wrong on the server or an external service.
        /// If non-permanent, a retry after some delay is allowed.
        /// Otherwise, registration may not be possible.
        case serverFailure(ServerFailureResponse)
        /// A network failure.
        case networkFailure
        /// Some other generic unknown error.
        case genericError
    }

    public struct ServerFailureResponse: Equatable {
        public let session: RegistrationSession

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
}
