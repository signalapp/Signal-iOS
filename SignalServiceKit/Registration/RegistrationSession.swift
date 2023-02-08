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
    /// If null, no further verification code submissions are allowed within this session, typically meaning
    /// the session should be terminated and a new one started.
    public let nextVerificationAttempt: TimeInterval?

    public var nextVerificationAttemptDate: Date? {
        return nextSMS.map { receivedDate.addingTimeInterval($0) }
    }

    /// If true, `requestedInformation` can be ignored and the user can request a verification code
    /// be sent via sms or call (subject to time limits set by their respective fields.)
    /// If false, the demands in `requestedInformation` must be satisfied before a verification code
    /// will be sent.
    public let allowedToRequestCode: Bool

    /// If set, the date at which a verification code was most recently requested.
    /// (Measured against the time that we got a server response from the request.)
    /// Used to determine if a code needs to be sent upon session restoration from disk.
    public let lastCodeRequestDate: Date?

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
        case lastCodeRequestDate
        case requestedInformation
        case hasUnknownChallengeRequiringAppUpdate
        case verified
    }
}
