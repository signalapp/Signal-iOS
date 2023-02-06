//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum RegistrationServiceResponses {

    public enum BeginSessionResponseCodes: Int, UnknownEnumCodable {
        /// Success. Response body has `RegistrationSession` object.
        case success = 200
        case missingArgument = 400
        case invalidArgument = 422
        /// The caller is not permitted to create a verification session and must wait before trying again.
        /// Response will include a 'retry-after' header.
        case retry = 429
        case unexpectedError = -1

        static public var unknown: Self { .unexpectedError }
    }

    public enum FetchSessionResponseCodes: Int, UnknownEnumCodable {
        /// Success. Response body has `RegistrationSession` object.
        case success = 200
        /// No session was found with the given ID. A new session should be initiated.
        case missingSession = 404
        case unexpectedError = -1

        static public var unknown: Self { .unexpectedError }
    }

    public enum FulfillChallengeResponseCodes: Int, UnknownEnumCodable {
        /// Success. Response body has `RegistrationSession` object.
        case success = 200
        /// E.g. the challenge token provided did not match.
        /// Response body has `RegistrationSession` object.
        case notAccepted = 403
        /// No session was found with the given ID. A new session should be initiated.
        case missingSession = 404
        case invalidArgument = 422
        case unexpectedError = -1

        static public var unknown: Self { .unexpectedError }
    }

    public enum RequestVerificationCodeResponseCodes: Int, UnknownEnumCodable {
        /// Success. Response body has `RegistrationSession` object.
        case success = 200
        case transportInvalid = 400
        /// No session was found with the given ID. A new session should be initiated.
        case missingSession = 404
        /// The client must fulfill some challenge before proceeding (found on the session object).
        /// Response body has `RegistrationSession` object.
        case challengeRequired = 409
        /// May need to wait before trying again; check session object for timeouts.
        /// If no timeout is specified, a different transport or starting a fresh session may be required.
        /// Response body has `RegistrationSession` object.
        case notPermitted = 429
        /// The attempt to send a verification code failed because an external service (e.g. the SMS provider) refused to deliver the code.
        /// Response body has `SendVerificationCodeFailedResponse` with more detailed information.
        case providerFailure = 502
        case unexpectedError = -1

        static public var unknown: Self { .unexpectedError }
    }

    public enum SubmitVerificationCodeResponseCodes: Int, UnknownEnumCodable {
        /// Success. Response body has `RegistrationSession` object.
        case success = 200
        case codeInvalid = 400
        /// No session was found with the given ID. A new session should be initiated.
        case missingSession = 404
        /// This session will not accept additional verification code submissions either because no code has been sent for this session
        /// (clients must request and presumably receive a verification code before submitting a code)
        /// or because the phone number has already been verified with another code.
        /// Response body has `RegistrationSession` object.
        case codeNotYetSent = 409
        /// May need to wait before trying again; check session object for timeouts.
        /// If no timeout is specified, starting a fresh session may be required.
        /// Response body has `RegistrationSession` object.
        case notPermitted = 429
        case unexpectedError = -1

        static public var unknown: Self { .unexpectedError }
    }

    public struct RegistrationSession: Codable {
        /// An opaque identifier for this session.
        /// Clients will need to provide this ID to the API for subsequent operations.
        /// The identifier will be made of URL-safe characters and will be less than 1024 bytes in length.
        public let id: String

        /// The time at which a client will next be able to request a verification SMS for this session.
        /// If null, no further requests to send a verification SMS will be accepted.
        /// Units are seconds from current time given in `X-Signal-Timestamp` header.
        public let nextSms: Int?

        /// The time at which a client will next be able to request a verification phone call for this session.
        /// If null, no further requests to make a verification phone call will be accepted.
        /// Units are seconds from current time given in `X-Signal-Timestamp` header.
        public let nextCall: Int?

        /// The time at which a client will next be able to submit a verification code for this session.
        /// If null, no further attempts to submit a verification code will be accepted in the scope of this session.
        /// Units are seconds from current time given in `X-Signal-Timestamp` header.
        public let nextVerificationAttempt: Int?

        /// Indicates whether clients are allowed to request verification code delivery via any transport mechanism.
        /// If false, clients should provide the information listed in the `requestedInformation` list until
        /// this field is `true` or the list of requested information contains no more options the client can fulfill.
        /// If true, clients must still abide by the time limits set in `nextSms`, `nextCall`, and so on.
        public let allowedToRequestCode: Bool

        /// A list of additional information a client may be required to provide before requesting verification code delivery.
        /// Additional requirements may appear in the future, and clients must be prepared to handle these cases gracefully
        /// (e.g. by prompting users to update their copy of the app if unrecognized values appear in this list).
        public let requestedInformation: [Challenge]

        /// Indicates whether the caller has submitted a correct verification code for this session.
        public let verified: Bool

        public enum Challenge: String, UnknownEnumCodable {
            case unknown
            case captcha
            case pushChallenge
        }
    }

    public struct SendVerificationCodeFailedResponse: Codable {
        /// Indicates whether the failure was permanent.
        /// If true, clients should not retry the request without modification
        /// (practically, this most likely means clients will need to ask users to re-enter their phone number).
        /// If false, clients may retry the request after a reasonable delay.
        public let permanentFailure: Bool

        /// An identifier that indicates the cause of the failure.
        /// This identifier is provided on a best-effort basis; it may or may not be present, and may include
        /// values not recognized by the current version of the client.
        /// Clients should be prepared to handle missing or unrecognized values.
        public let reason: Reason?

        public enum Reason: String, UnknownEnumCodable {
            case unknown
            /// The provider understood the request, but declined to deliver a verification SMS/call.
            /// (potentially due to fraud prevention rules)
            case providerRejected
            /// The provider could not be reached or did not respond to the request to send a verification code in a timely manner
            case providerUnavailable
            /// Some part of the request was not understood or accepted by the provider.
            /// (e.g. the provider did not recognize the phone number as a valid number for the selected transport)
            case illegalArgument
        }
    }
}
