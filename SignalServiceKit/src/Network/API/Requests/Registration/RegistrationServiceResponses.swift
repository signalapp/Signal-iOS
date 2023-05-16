//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum RegistrationServiceResponses {

    // MARK: - Registration Session Endpoints

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
        case malformedRequest = 422
        case unexpectedError = -1

        static public var unknown: Self { .unexpectedError }
    }

    public enum RequestVerificationCodeResponseCodes: Int, UnknownEnumCodable {
        /// Success. Response body has `RegistrationSession` object.
        case success = 200
        case malformedRequest = 400
        /// No session was found with the given ID. A new session should be initiated.
        case missingSession = 404
        /// The current session state disallows requesting a code.
        /// The client may have to fulfill some challenge before proceeding,
        /// or the session might already be verified. Check the session object to know.
        /// Response body has `RegistrationSession` object.
        case disallowed = 409
        /// May need to wait before trying again; check session object for timeouts.
        /// If no timeout is specified, a different transport or starting a fresh session may be required.
        /// Response body has `RegistrationSession` object.
        case retry = 429
        /// The attempt to send a verification code failed because an external service (e.g. the SMS provider) refused to deliver the code.
        /// Response body has `SendVerificationCodeFailedResponse` with more detailed information.
        case providerFailure = 502
        case unexpectedError = -1

        static public var unknown: Self { .unexpectedError }
    }

    public enum SubmitVerificationCodeResponseCodes: Int, UnknownEnumCodable {
        /// The code was valid, but may not be correct. The
        /// `isVerified` field on the session object indicates
        /// correctness.
        /// Response body has `RegistrationSession` object.
        case success = 200
        /// The code was illegally formatted.
        case malformedRequest = 400
        /// No session was found with the given ID. A new session should be initiated.
        case missingSession = 404
        /// This session will not accept additional verification code submissions either because no code has been sent for this session
        /// (clients must request and presumably receive a verification code before submitting a code)
        /// or because the phone number has already been verified with another code.
        /// Response body has `RegistrationSession` object.
        case newCodeRequired = 409
        /// May need to wait before trying again; check session object for timeouts.
        /// If no timeout is specified, sending a new code or starting a fresh session may be required.
        /// Response body has `RegistrationSession` object.
        case retry = 429
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

    // MARK: - KBS Auth Check

    public enum KBSAuthCheckResponseCodes: Int, UnknownEnumCodable {
        /// Success. Response body has `KBSAuthCheckResponse` object.
        case success = 200
        /// The server couldn't parse the set of credentials.
        case malformedRequest = 422
        /// The POST request body is not valid JSON.
        case invalidJSON = 400
        case unexpectedError = -1

        static public var unknown: Self { .unexpectedError }
    }

    public struct KBSAuthCheckResponse: Codable {
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
            static public var unknown: Self { return .invalid }
        }

        public func result(for credential: KBSAuthCredential) -> Result? {
            let key = "\(credential.credential.username):\(credential.credential.password)"
            return matches[key]
        }
    }

    // MARK: - Account Creation/Change Number

    public enum AccountCreationResponseCodes: Int, UnknownEnumCodable {
        /// Success. Response body has `AccountIdentityResponse`.
        case success = 200
        /// Incorrect request body shape, missing required Authorization header,
        /// or Authorization e164 did not match e164 from session.
        /// Response body has a string error message.
        case malformedRequest = 400
        /// The Authorization header was invalid or the provided credentials were insufficient
        /// to verify ownership of the given phone number.
        /// Response body has an optional string error message.
        case unauthorized = 401
        /// The provided registration recovery password is either incorrect
        /// or registration via reg recovery password is impossible for this number.
        case regRecoveryPasswordRejected = 403
        /// The caller has not explicitly elected to skip transferring data
        /// from another device, but a device transfer is technically possible.
        case deviceTransferPossible = 409
        /// Response body has an optional string error message.
        case invalidArgument = 422
        /// An account with the given phone number already exists and has a registration lock,
        /// and the client has not provided appropriate reglock credentials (either because the
        /// user inputted the wrong PIN, or because the client has the wrong random number
        /// used to generate the master key).
        /// Response body has `RegistrationLockFailureResponse`.
        case reglockFailed = 423
        /// The caller is not permitted to create an account and must wait before trying again.
        /// Response will include a 'retry-after' header.
        case retry = 429
        case unexpectedError = -1

        static public var unknown: Self { .unexpectedError }
    }

    public enum ChangeNumberResponseCodes: Int, UnknownEnumCodable {
        /// Success. Response body has `AccountIdentityResponse`.
        case success = 200
        /// Incorrect request body shape, missing required Authorization header,
        /// or Authorization e164 did not match e164 from session.
        /// Response body has a string error message.
        case malformedRequest = 400
        /// The provided credentials were insufficient to verify ownership of the given phone number.
        case unauthorized = 401
        /// The provided registration recovery password is either incorrect
        /// or registration via reg recovery password is impossible for this number.
        case regRecoveryPasswordRejected = 403
        /// The devices to notify in the request did not match the known
        /// linked devices.
        case mismatchedDevicesToNotify = 409
        /// The devices to notify in the request were correct, but their
        /// provided registrationIds did not match.
        case mismatchedDevicesToNotifyRegistrationIds = 410
        /// Response body has an optional string error message.
        case invalidArgument = 422
        /// An account with the given phone number already exists and has a registration lock,
        /// and the client has not provided appropriate reglock credentials (either because the
        /// user inputted the wrong PIN, or because the client has the wrong random number
        /// used to generate the master key).
        /// Response body has `RegistrationLockFailureResponse`.
        case reglockFailed = 423
        /// The caller is not permitted to change the number and must wait before trying again.
        /// Response will include a 'retry-after' header.
        case retry = 429
        case unexpectedError = -1

        static public var unknown: Self { .unexpectedError }
    }

    public struct AccountIdentityResponse: Codable, Equatable {
        /// The users account identifier.
        public let aci: UUID
        /// The user's phone number identifier.
        public let pni: UUID
        /// The phone number associated with the PNI.
        public let e164: E164
        /// The username associated with the ACI.
        public let username: String?
        /// Whether the account has any data in SVR.
        public let hasPreviouslyUsedSVR: Bool

        public init(aci: UUID, pni: UUID, e164: E164, username: String?, hasPreviouslyUsedSVR: Bool) {
            self.aci = aci
            self.pni = pni
            self.e164 = e164
            self.username = username
            self.hasPreviouslyUsedSVR = hasPreviouslyUsedSVR
        }

        public enum CodingKeys: String, CodingKey {
            case aci = "uuid"
            case pni
            case e164 = "number"
            case username
            case hasPreviouslyUsedSVR = "storageCapable"
        }
    }

    public struct RegistrationLockFailureResponse: Codable {
        /// Time remaining until the registration lock expires and the account
        /// can be taken over.
        public let timeRemainingMs: Int
        /// A credential with which the client can talk to KBS server to
        /// recover the KBS master key, and from it the reglock token,
        /// using the user's PIN.
        /// NOTE: this is NOT an SVR2 credential.
        public let kbsAuthCredential: KBSAuthCredential

        public enum CodingKeys: String, CodingKey {
            case timeRemainingMs = "timeRemaining"
            case kbsAuthCredential = "backupCredentials"
        }

        public init(
            timeRemainingMs: Int,
            kbsAuthCredential: KBSAuthCredential
        ) {
            self.timeRemainingMs = timeRemainingMs
            self.kbsAuthCredential = kbsAuthCredential
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            timeRemainingMs = try container.decode(Int.self, forKey: .timeRemainingMs)
            let credential = try container.decode(RemoteAttestation.Auth.self, forKey: .kbsAuthCredential)
            kbsAuthCredential = KBSAuthCredential(credential: credential)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(timeRemainingMs, forKey: .timeRemainingMs)
            try container.encode(kbsAuthCredential.credential, forKey: .kbsAuthCredential)
        }
    }

    // MARK: Check Proxy Connection

    public enum CheckProxyConnectionResponseCodes: Int, UnknownEnumCodable {
        case connected = 400
        case failure = -1

        static public var unknown: Self { .failure }

        public init(rawValue: RawValue) {
            switch rawValue {
            case 200..<300:
                self = .connected
            case 400..<500:
                self = .connected
            default:
                self = .failure
            }
        }
    }
}
