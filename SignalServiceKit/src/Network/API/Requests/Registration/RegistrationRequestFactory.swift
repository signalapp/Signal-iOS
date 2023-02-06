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
        pushToken: String?
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
}
