//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum RegistrationServiceResponses {

    // MARK: - Registration Session Endpoints

    public enum FetchSessionResponseCodes: Int, UnknownEnumCodable {
        /// Success. Response body has `RegistrationSession` object.
        case success = 200
        /// No session was found with the given ID. A new session should be initiated.
        case missingSession = 404
        case unexpectedError = -1

        public static var unknown: Self { .unexpectedError }
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

    // MARK: - SVR2 Auth Check

    public struct SVR2AuthCheckResponse: Codable {
        public let matches: [String: Result]

        public enum Result: String, UnknownEnumCodable {
            /// At most one credential will be marked as a `match` per request.
            /// Clients should use this credential when re-registering the associated phone number.
            case match
            /// The provided credential is valid and should be retained by the client,
            /// but cannot be used to re-register the provided number.
            case notMatch = "not-match"
            /// Indicates that the credential may not be used to re-register any phone number and should be discarded.
            case invalid

            // Server API explicitly says clients should treat unrecognized values as invalid.
            public static var unknown: Self { return .invalid }
        }

        public func result(for credential: SVR2AuthCredential) -> Result? {
            let key = "\(credential.credential.username):\(credential.credential.password)"
            return matches[key]
        }
    }

    // MARK: - Account Creation/Change Number

    public struct RegistrationLockFailureResponse: Decodable {
        /// Time remaining until the registration lock expires and the account
        /// can be taken over.
        public let timeRemainingMs: Int
        /// A credential with which the client can talk to SVR2 server to
        /// recover the SVR master key, and from it the reglock token,
        /// using the user's PIN.
        public let svr2AuthCredential: SVR2AuthCredential

        public enum CodingKeys: String, CodingKey {
            case timeRemainingMs = "timeRemaining"
            case svr2AuthCredential = "svr2Credentials"
        }

        public init(
            timeRemainingMs: Int,
            svr2AuthCredential: SVR2AuthCredential,
        ) {
            self.timeRemainingMs = timeRemainingMs
            self.svr2AuthCredential = svr2AuthCredential
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            timeRemainingMs = try container.decode(Int.self, forKey: .timeRemainingMs)
            let svr2Credential = try container.decode(RemoteAttestationAuth.self, forKey: .svr2AuthCredential)
            self.svr2AuthCredential = .init(credential: svr2Credential)
        }
    }
}
