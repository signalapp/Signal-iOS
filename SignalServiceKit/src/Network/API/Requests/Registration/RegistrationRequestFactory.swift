//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum RegistrationRequestFactory {

    // MARK: - Session API

    /// See `RegistrationServiceResponses.BeginSessionResponseCodes` for possible responses.
    public static func beginSessionRequest(
        e164: String,
        pushToken: String?,
        mcc: String?,
        mnc: String?
    ) -> TSRequest {
        owsAssertDebug(!e164.isEmpty)

        let urlPathComponents = URLPathComponents(
            ["v1", "verification", "session"]
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        var parameters: [String: Any] = [
            "number": e164
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

        let result = TSRequest(url: url, method: "POST", parameters: parameters)
        result.shouldHaveAuthorizationHeaders = false
        return result
    }

    /// See `RegistrationServiceResponses.FetchSessionResponseCodes` for possible responses.
    public static func fetchSessionRequest(
        sessionId: String
    ) -> TSRequest {
        owsAssertDebug(sessionId.isEmpty.negated)

        let urlPathComponents = URLPathComponents(
            ["v1", "verification", "session", sessionId]
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let result = TSRequest(url: url, method: "GET", parameters: nil)
        result.shouldHaveAuthorizationHeaders = false
        return result
    }

    /// See `RegistrationServiceResponses.FulfillChallengeResponseCodes` for possible responses.
    /// TODO[Registration]: this can also take an APNS token to resend a push challenge. Push token challenges
    /// are  best-effort, but as an optimization we may want to do that.
    public static func fulfillChallengeRequest(
        sessionId: String,
        captchaToken: String?,
        pushChallengeToken: String?
    ) -> TSRequest {
        owsAssertDebug(sessionId.isEmpty.negated)
        owsAssertDebug(!captchaToken.isEmptyOrNil || !pushChallengeToken.isEmptyOrNil)

        let urlPathComponents = URLPathComponents(
            ["v1", "verification", "session", sessionId]
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

        let result = TSRequest(url: url, method: "PATCH", parameters: parameters)
        result.shouldHaveAuthorizationHeaders = false
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
        transport: VerificationCodeTransport
    ) -> TSRequest {
        owsAssertDebug(sessionId.isEmpty.negated)

        let urlPathComponents = URLPathComponents(
            ["v1", "verification", "session", sessionId, "code"]
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let parameters: [String: Any] = [
            "transport": transport.rawValue,
            "client": "ios"
        ]

        var languageCodes = [String]()
        if let languageCode {
            if let countryCode {
                languageCodes.append("\(languageCode)-\(countryCode)")
            }
            languageCodes.append(languageCode)
        }
        if languageCodes.contains("en").negated {
            languageCodes.append("en")
        }

        let languageHeader: String = OWSHttpHeaders.formatAcceptLanguageHeader(languageCodes)

        let result = TSRequest(url: url, method: "POST", parameters: parameters)
        result.shouldHaveAuthorizationHeaders = false
        result.setValue(languageHeader, forHTTPHeaderField: OWSHttpHeaders.acceptLanguageHeaderKey)
        return result
    }

    /// See `RegistrationServiceResponses.SubmitVerificationCodeResponseCodes` for possible responses.
    public static func submitVerificationCodeRequest(
        sessionId: String,
        code: String
    ) -> TSRequest {
        owsAssertDebug(sessionId.isEmpty.negated)
        owsAssertDebug(code.isEmpty.negated)

        let urlPathComponents = URLPathComponents(
            ["v1", "verification", "session", sessionId, "code"]
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let parameters: [String: Any] = [
            "code": code
        ]

        let result = TSRequest(url: url, method: "PUT", parameters: parameters)
        result.shouldHaveAuthorizationHeaders = false
        return result
    }

    // MARK: - KBS Auth Check

    public static func kbsAuthCredentialCheckRequest(
        e164: String,
        credentials: [KBSAuthCredential]
    ) -> TSRequest {
        owsAssertDebug(!credentials.isEmpty)

        let urlPathComponents = URLPathComponents(
            ["v1", "backup", "auth", "check"]
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let parameters: [String: Any] = [
            "number": e164,
            "passwords": credentials.map {
                "\($0.username):\($0.credential.password)"
            }
        ]

        let result = TSRequest(url: url, method: "POST", parameters: parameters)
        result.shouldHaveAuthorizationHeaders = false
        return result
    }

    // MARK: - Account Creation/Change Number

    public enum VerificationMethod {
        /// The ID of an existing, validated RegistrationSession.
        case sessionId(String)
        /// Base64 encoded registration recovery password (derived from KBS master secret).
        case recoveryPassword(String)
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
    public static func createAccountRequest(
        verificationMethod: VerificationMethod,
        e164: String,
        authPassword: String,
        accountAttributes: AccountAttributes,
        skipDeviceTransfer: Bool
    ) -> TSRequest {
        let urlPathComponents = URLPathComponents(
            ["v1", "registration"]
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let accountAttributesData = try! JSONEncoder().encode(accountAttributes)
        let accountAttributesDict = try! JSONSerialization.jsonObject(with: accountAttributesData, options: .fragmentsAllowed) as! [String: Any]

        var parameters: [String: Any] = [
            "accountAttributes": accountAttributesDict,
            "skipDeviceTransfer": skipDeviceTransfer
        ]
        switch verificationMethod {
        case .sessionId(let sessionId):
            parameters["sessionId"] = sessionId
        case .recoveryPassword(let recoveryPassword):
            parameters["recoveryPassword"] = recoveryPassword
        }

        let result = TSRequest(url: url, method: "POST", parameters: parameters)
        result.shouldHaveAuthorizationHeaders = true
        result.addValue("OWI", forHTTPHeaderField: "X-Signal-Agent")
        // As odd as this is, it is to spec.
        result.authUsername = e164
        result.authPassword = authPassword
        return result
    }

    // TODO[Registration]: Extra PNI-related fields aren't being set right now.
    // pniIdentityKey, deviceMessages, devicePniSignedPrekeys, pniRegistrationIds
    // They are required and requests will fail until they are set.
    /// Update the phone number on an account.
    ///
    /// - parameter verificationMethod: A way to verify phone number and account ownership.
    /// - parameter e164: The phone number to change to.
    /// - parameter reglockToken: If reglock is enabled, required to succeed. Derived from the
    ///   kbs master key.
    public static func changeNumberRequest(
        verificationMethod: VerificationMethod,
        e164: String,
        reglockToken: String?
    ) -> TSRequest {
        let urlPathComponents = URLPathComponents(
            ["v2", "accounts", "number"]
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        var parameters: [String: Any] = [
            "number": e164
        ]
        switch verificationMethod {
        case .sessionId(let sessionId):
            parameters["sessionId"] = sessionId
        case .recoveryPassword(let recoveryPassword):
            parameters["recoveryPassword"] = recoveryPassword
        }
        if let reglockToken {
            parameters["reglock"] = reglockToken
        }

        // TODO: Extra PNI-related fields aren't being set right now.
        // pniIdentityKey, deviceMessages, devicePniSignedPrekeys, pniRegistrationIds
        // They are required and requests will fail until they are set.

        let result = TSRequest(url: url, method: "PUT", parameters: parameters)
        result.shouldHaveAuthorizationHeaders = true
        return result
    }

    public static func updatePrimaryDeviceAccountAttributesRequest(
        _ accountAttributes: AccountAttributes,
        auth: ChatServiceAuth
    ) -> TSRequest {
        let urlPathComponents = URLPathComponents(
            ["v1", "accounts", "attributes"]
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        // The request expects the AccountAttributes to be the root object.
        // Serialize it to JSON then get the key value dict to do that.
        let data = try! JSONEncoder().encode(accountAttributes)
        let parameters = try! JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as! [String: Any]

        let result = TSRequest(url: url, method: "PUT", parameters: parameters)
        result.shouldHaveAuthorizationHeaders = true
        result.setAuth(auth)
        return result
    }
}
