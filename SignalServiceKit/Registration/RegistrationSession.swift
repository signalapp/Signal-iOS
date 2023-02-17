//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Client-only representation of a RegistrationSessionMetadata object returned by the server
/// in registration endpoint responses.
/// Represents state related to registration, answering questions like "can I request an SMS code?",
/// "if so, when can I request one again?", and "have I submitted a valid verification code?".
///
/// Intentionally distinct from the on-the-wire json definition; this is the one we store on disk
/// and therefore want distinct for the purposes of migrations.
public struct RegistrationSession: Codable, Equatable {
    /// Opaque id required by the server in requests.
    /// URL safe characters only, 1024 bytes max length.
    public let id: String

    /// The phone number (in e164 format) this session was created for.
    public let e164: String

    /// The date at which we received this session metadata from the server.
    /// All durations should be measured against this date.
    public let receivedDate: Date

    /// How long after `receivedDate` we must wait to send another verification sms.
    /// If null, no further SMS requests are allowed within this session.
    public let nextSMS: TimeInterval?

    public var nextSMSDate: Date? {
        return nextSMS.map { receivedDate.addingTimeInterval($0) }
    }

    /// How long after `receivedDate` we must wait to send another verification call.
    /// If null, no further call requests are allowed within this session.
    public let nextCall: TimeInterval?

    public var nextCallDate: Date? {
        return nextCall.map { receivedDate.addingTimeInterval($0) }
    }

    /// How long after `receivedDate` we must wait to submit a sms/call verification code to the server.
    /// If null, no code is available for submission, either because:
    /// 1) No code has ever been sent
    /// 2) A code was sent but it expired
    /// 3) All attempts have been exhausted for the current code
    /// In all of these cases, the next step is requesting a new code, which may change
    /// the value of this field. If a code cannot be requested, the session
    /// can be considered invalid and discarded.
    public let nextVerificationAttempt: TimeInterval?

    public var nextVerificationAttemptDate: Date? {
        return nextSMS.map { receivedDate.addingTimeInterval($0) }
    }

    /// If true, the server believes that there is a code that has been sent, is still valid,
    /// and is waiting to be submitted (and attempts have not been exhausted). The user
    /// should be allowed to submit the code (or resend).
    /// If false, there is no code able to be submitted, a new code _must_ be requested,
    /// and the user should only be given code sending as an option.
    public var hasCodeAvailableToSubmit: Bool {
        return nextVerificationAttempt != nil
    }

    /// If true, `requestedInformation` can be ignored and the user can request a verification code
    /// be sent via sms or call (subject to time limits set by their respective fields.)
    /// If false, the demands in `requestedInformation` must be satisfied before a verification code
    /// will be sent.
    public let allowedToRequestCode: Bool

    public enum Challenge: Codable, Equatable {
        /// A captcha challenge to be shown and completed by the user.
        case captcha
        /// A silent push sent to the client, receipt of which proves AppStore installation validity.
        /// Requires no explicit user action.
        case pushChallenge
    }

    /// If `allowedToRequestCode` is true, the challenges herein should be completed in
    /// FIFO order as possible. e.g. if the client is incapable of completed the first challenge,
    /// it should attempt the second instead.
    /// It's possible not all challenges need be completed to proceed; clients should complete
    /// challenges one at a time and check the new session metadata in the response for
    /// additional challenge requirements, which may be none at all, before proceeding.
    public let requestedInformation: [Challenge]

    /// If true, it means some challenge was provided by the server that this client cannot
    /// interpret. Users should be warned to update the app before completing registration.
    public let hasUnknownChallengeRequiringAppUpdate: Bool

    /// If true, a correct verification code has been submitted in this session
    /// and registration can proceed to account creation.
    public let verified: Bool

    public enum CodingKeys: String, CodingKey {
        case id
        case e164
        case receivedDate
        case nextSMS
        case nextCall
        case nextVerificationAttempt
        case allowedToRequestCode
        case requestedInformation
        case hasUnknownChallengeRequiringAppUpdate
        case verified
    }
}
