//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum RegistrationRequestFactory {

    // MARK: - Session API

    /// See `RegistrationServiceResponses.BeginSessionResponseCodes` for possible responses.
    public static func beginSessionRequest(
        e164: E164,
        pushToken: String?,
        mcc: String?,
        mnc: String?,
        logger: PrefixedLogger,
    ) -> TSRequest {
        let urlPathComponents = URLPathComponents(
            ["v1", "verification", "session"],
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        var parameters: [String: Any] = [
            "number": e164.stringValue,
        ]
        if let pushToken {
            owsAssertDebug(!pushToken.isEmpty)
            parameters["pushToken"] = pushToken
            parameters["pushTokenType"] = "apn"
        }
        if let mcc {
            parameters["mcc"] = mcc
        }
        if let mnc {
            parameters["mnc"] = mnc
        }

        var result = TSRequest(url: url, method: "POST", parameters: parameters, logger: logger)
        result.auth = .registration(nil)
        return result
    }

    /// See `RegistrationServiceResponses.FetchSessionResponseCodes` for possible responses.
    public static func fetchSessionRequest(
        sessionId: String,
        logger: PrefixedLogger,
    ) -> TSRequest {
        owsAssertDebug(!sessionId.isEmpty)

        let urlPathComponents = URLPathComponents(
            ["v1", "verification", "session", sessionId],
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        var result = TSRequest(url: url, method: "GET", parameters: nil, logger: logger)
        result.auth = .registration(nil)
        redactSessionIdFromLogs(sessionId, in: &result)
        return result
    }

    /// See `RegistrationServiceResponses.FulfillChallengeResponseCodes` for possible responses.
    /// TODO[Registration]: this can also take an APNS token to resend a push challenge. Push token challenges
    /// are  best-effort, but as an optimization we may want to do that.
    public static func fulfillChallengeRequest(
        sessionId: String,
        captchaToken: String?,
        pushChallengeToken: String?,
        logger: PrefixedLogger,
    ) -> TSRequest {
        owsAssertDebug(!sessionId.isEmpty)
        owsAssertDebug(!captchaToken.isEmptyOrNil || !pushChallengeToken.isEmptyOrNil)

        let urlPathComponents = URLPathComponents(
            ["v1", "verification", "session", sessionId],
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        var parameters: [String: Any] = [:]
        if let captchaToken {
            parameters["captcha"] = captchaToken
        }
        if let pushChallengeToken {
            parameters["pushChallenge"] = pushChallengeToken
        }

        var result = TSRequest(url: url, method: "PATCH", parameters: parameters, logger: logger)
        result.auth = .registration(nil)
        redactSessionIdFromLogs(sessionId, in: &result)
        return result
    }

    public enum VerificationCodeTransport: String {
        case sms
        case voice
    }

    /// See `RegistrationServiceResponses.RequestVerificationCodeResponseCodes` for possible responses.
    ///
    /// - parameter languageCode: Language in which the client prefers to receive SMS or voice verification messages
    ///       If nil, english is used.
    /// - parameter countryCode: If provided, combined with language code.
    public static func requestVerificationCodeRequest(
        sessionId: String,
        languageCode: String?,
        countryCode: String?,
        transport: VerificationCodeTransport,
        logger: PrefixedLogger,
    ) -> TSRequest {
        owsAssertDebug(!sessionId.isEmpty)

        let urlPathComponents = URLPathComponents(
            ["v1", "verification", "session", sessionId, "code"],
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let parameters: [String: Any] = [
            "transport": transport.rawValue,
            "client": "ios",
        ]

        var languageCodes = [String]()
        if let languageCode {
            if let countryCode {
                languageCodes.append("\(languageCode)-\(countryCode)")
            }
            languageCodes.append(languageCode)
        }
        if !languageCodes.contains("en") {
            languageCodes.append("en")
        }

        let languageHeader: String = HttpHeaders.formatAcceptLanguageHeader(languageCodes)

        var result = TSRequest(url: url, method: "POST", parameters: parameters, logger: logger)
        result.auth = .registration(nil)
        result.headers[HttpHeaders.acceptLanguageHeaderKey] = languageHeader
        redactSessionIdFromLogs(sessionId, in: &result)
        return result
    }

    /// See `RegistrationServiceResponses.SubmitVerificationCodeResponseCodes` for possible responses.
    public static func submitVerificationCodeRequest(
        sessionId: String,
        code: String,
        logger: PrefixedLogger,
    ) -> TSRequest {
        owsAssertDebug(!sessionId.isEmpty)
        owsAssertDebug(!code.isEmpty)

        let urlPathComponents = URLPathComponents(
            ["v1", "verification", "session", sessionId, "code"],
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let parameters: [String: Any] = [
            "code": code,
        ]

        var result = TSRequest(url: url, method: "PUT", parameters: parameters, logger: logger)
        result.auth = .registration(nil)
        redactSessionIdFromLogs(sessionId, in: &result)
        return result
    }

    // MARK: - SVR2 Auth Check

    public static func svr2AuthCredentialCheckRequest(
        e164: E164,
        credentials: [SVR2AuthCredential],
        logger: PrefixedLogger,
    ) -> TSRequest {
        owsAssertDebug(!credentials.isEmpty)

        let urlPathComponents = URLPathComponents(
            ["v2", "svr", "auth", "check"],
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let parameters: [String: Any] = [
            "number": e164.stringValue,
            "passwords": credentials.map {
                "\($0.credential.username):\($0.credential.password)"
            },
        ]

        var result = TSRequest(url: url, method: "POST", parameters: parameters, logger: logger)
        result.auth = .registration(nil)
        return result
    }

    // MARK: - Account Creation/Change Number

    public enum VerificationMethod {
        /// The ID of an existing, validated RegistrationSession.
        case sessionId(E164, String)
        case recoveryPassword(RegistrationIdentifier, RegistrationRecoveryPassword)
    }

    public struct ApnRegistrationId: Codable {
        public let apnsToken: String

        public init(apnsToken: String) {
            self.apnsToken = apnsToken
        }

        public enum CodingKeys: String, CodingKey {
            case apnsToken = "apnRegistrationId"
        }
    }

    /// Create an account, or re-register if one exists.
    ///
    /// - parameter verificationMethod: A way to verify phone number and account ownership.
    /// - parameter e164: The phone number being registered for.
    /// - parameter accountAttributes: Attributes for the account, same as those in
    ///   `updatePrimaryDeviceAttributesRequest`.
    /// - parameter skipDeviceTransfer: If true, indicates that the end user has elected
    ///   not to transfer data from another device even though a device transfer is technically possible
    ///   given the capabilities of the calling device and the device associated with the existing account (if any).
    ///   If false and if a device transfer is technically possible, the registration request will fail with an HTTP/409
    ///   response indicating that the client should prompt the user to transfer data from an existing device.
    /// - parameter apnRegistrationId: Apple Push Notification Service token(s) for the server to send
    ///   push notifications to. Either this must be non-nil, or `AccountAttributes.isManualMessageFetchEnabled`
    ///   must be true, otherwise the request will fail.
    /// - parameter prekeyBundles: Prekey information to include in the request; mirrors the requests to `v2/keys`.
    public static func createAccountRequest(
        verificationMethod: VerificationMethod,
        authPassword: String,
        accountAttributes: AccountAttributes,
        skipDeviceTransfer: Bool,
        apnRegistrationId: ApnRegistrationId?,
        aciPreKeyBundle: RegistrationPreKeyUploadBundle,
        pniPreKeyBundle: RegistrationPreKeyUploadBundle,
        logger: PrefixedLogger,
    ) -> TSRequest {
        owsAssertDebug((apnRegistrationId != nil) != accountAttributes.isManualMessageFetchEnabled)

        let urlPathComponents = URLPathComponents(
            ["v1", "registration"],
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        var request = RegistrationRequest(
            accountAttributes: accountAttributes,
            skipDeviceTransfer: skipDeviceTransfer,
            aciIdentityKey: OWSRequestFactory.IdentityKey(aciPreKeyBundle.identityKeyPair.identityKey),
            aciSignedPreKey: OWSRequestFactory.SignedPreKey(aciPreKeyBundle.signedPreKey),
            aciPqLastResortPreKey: OWSRequestFactory.KyberPreKey(aciPreKeyBundle.lastResortPreKey),
            pniIdentityKey: OWSRequestFactory.IdentityKey(pniPreKeyBundle.identityKeyPair.identityKey),
            pniSignedPreKey: OWSRequestFactory.SignedPreKey(pniPreKeyBundle.signedPreKey),
            pniPqLastResortPreKey: OWSRequestFactory.KyberPreKey(pniPreKeyBundle.lastResortPreKey),
            apnToken: apnRegistrationId,
        )

        let username: String
        switch verificationMethod {
        case .sessionId(let phoneNumber, let sessionId):
            username = phoneNumber.stringValue
            request.sessionId = sessionId
        case .recoveryPassword(let identifier, let recoveryPassword):
            switch identifier {
            case .phoneNumber(let phoneNumber):
                username = phoneNumber.stringValue
            }
            request.recoveryPassword = OWSRequestFactory.RegistrationRecoveryPassword(recoveryPassword)
        }

        var result = TSRequest(url: url, method: "POST", body: .encodable(request), logger: logger)
        // As odd as this is, it is to spec.
        result.auth = .registration((username: username, password: authPassword))
        result.headers["X-Signal-Agent"] = "OWI"
        return result
    }

    struct RegistrationRequest: Encodable {
        var sessionId: String?
        var recoveryPassword: OWSRequestFactory.RegistrationRecoveryPassword?
        var accountAttributes: AccountAttributes
        var skipDeviceTransfer: Bool
        var aciIdentityKey: OWSRequestFactory.IdentityKey
        var aciSignedPreKey: OWSRequestFactory.SignedPreKey
        var aciPqLastResortPreKey: OWSRequestFactory.KyberPreKey
        var pniIdentityKey: OWSRequestFactory.IdentityKey
        var pniSignedPreKey: OWSRequestFactory.SignedPreKey
        var pniPqLastResortPreKey: OWSRequestFactory.KyberPreKey
        var apnToken: ApnRegistrationId?
    }

    /// Update the phone number on an account.
    ///
    /// - parameter verificationMethod: A way to verify phone number and account ownership.
    /// - parameter e164: The phone number to change to.
    /// - parameter reglockToken: If reglock is enabled, required to succeed. Derived from the
    ///   kbs master key.
    /// - parameter pniChangeNumberParameters: pni related params used to inform
    ///   linked device of the change number and rotated pni keys.
    public static func changeNumberRequest(
        verificationMethod: VerificationMethod,
        reglockToken: RegistrationLock?,
        pniChangeNumberParameters: PniDistribution.Parameters,
        logger: PrefixedLogger,
    ) -> TSRequest {
        let urlPathComponents = URLPathComponents(
            ["v2", "accounts", "number"],
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let newPhoneNumber: E164
        switch verificationMethod {
        case .sessionId(let _newPhoneNumber, _):
            newPhoneNumber = _newPhoneNumber
        case .recoveryPassword(.phoneNumber(let _newPhoneNumber), _):
            newPhoneNumber = _newPhoneNumber
        }

        var request = ChangeNumberRequest(
            number: newPhoneNumber,
            reglock: reglockToken.map { OWSRequestFactory.RegistrationLock($0) },
            pniIdentityKey: OWSRequestFactory.IdentityKey(pniChangeNumberParameters.pniIdentityKey),
            devicePniSignedPrekeys: pniChangeNumberParameters.devicePniSignedPreKeys.mapKeys(injectiveTransform: { "\($0)" }).mapValues {
                return OWSRequestFactory.SignedPreKey($0)
            },
            devicePniPqLastResortPrekeys: pniChangeNumberParameters.devicePniPqLastResortPreKeys.mapKeys(injectiveTransform: { "\($0)" }).mapValues {
                return OWSRequestFactory.KyberPreKey($0)
            },
            deviceMessages: pniChangeNumberParameters.deviceMessages,
            pniRegistrationIds: pniChangeNumberParameters.pniRegistrationIds.mapKeys(injectiveTransform: { "\($0)" }),
        )

        switch verificationMethod {
        case .sessionId(_, let sessionId):
            request.sessionId = sessionId
        case .recoveryPassword(_, let recoveryPassword):
            request.recoveryPassword = OWSRequestFactory.RegistrationRecoveryPassword(recoveryPassword)
        }

        return TSRequest(url: url, method: "PUT", body: .encodable(request), logger: logger)
    }

    private struct ChangeNumberRequest: Encodable {
        var number: E164
        var sessionId: String?
        var recoveryPassword: OWSRequestFactory.RegistrationRecoveryPassword?
        var reglock: OWSRequestFactory.RegistrationLock?
        var pniIdentityKey: OWSRequestFactory.IdentityKey
        var devicePniSignedPrekeys: [String: OWSRequestFactory.SignedPreKey]
        var devicePniPqLastResortPrekeys: [String: OWSRequestFactory.KyberPreKey]
        var deviceMessages: [DeviceMessage]
        var pniRegistrationIds: [String: UInt32]
    }

    // MARK: - Helpers

    private static func redactSessionIdFromLogs(_ sessionId: String, in request: inout TSRequest) {
        request.applyRedactionStrategy(.redactURL(sensitiveValues: [sessionId]))
    }
}
