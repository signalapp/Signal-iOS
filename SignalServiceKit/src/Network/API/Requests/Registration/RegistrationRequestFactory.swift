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

    // TODO: Share this well-defined struct with the other endpoints that use it.
    // Previously it was defined in code that constructs the dictionary, not as an
    // explicit struct, and used in more than one request.
    public struct AccountAttributes: Codable {
        /// This is a hex-encoded random sequence of 16 bytes we generate locally,
        /// include in the register or provision request as both the auth header password
        /// and in these account attributes.
        /// Thereafter we include it in authenticated requests to the server for identification.
        public let authKey: String

        /// All Signal-iOS clients support voice
        public let voice: Bool = true

        /// All Signal-iOS clients support voice
        public let video: Bool = true

        /// Devices that don't support push must tell the server they fetch messages manually.
        public let isManualMessageFetchEnabled: Bool

        /// A randomly generated ID that is associated with the user's ACI that identifies
        /// a single registration and is sent to e.g. message recipients. If this changes, it tells
        /// you the sender has re-registered, and is cheaper to compare than doing full key comparison.
        public let registrationId: UInt32

        /// A randomly generated ID that is associated with the user's PNI that identifies
        /// a single registration and is sent to e.g. message recipients. If this changes, it tells
        /// you the sender has re-registered, and is cheaper to compare than doing full key comparison.
        public let pniRegistrationId: UInt32

        /// Base64-encoded SMKUDAccessKey generated from the user's profile key.
        public let unidentifiedAccessKey: String?

        /// Whether the user allows sealed sender messages to come from arbitrary senders.
        public let unrestrictedUnidentifiedAccess: Bool

        /// Reglock token derived from KBS master key, if reglock is enabled.
        ///
        /// NOTE: previously, we'd include the pin in this object if the reglock token
        /// was not included but a v1 pin was set. This new formal struct is only used with
        /// v2-compliant clients, so that is ignored.
        public let registrationLockToken: String?

        /// The device name the user entered for a linked device, encrypted with the user's ACI key pair.
        /// Unused (nil) on primary device requests.
        public let encryptedDeviceName: String?

        /// Whether the user has opted to allow their account to be discoverable by phone number.
        public let discoverableByPhoneNumber: Bool

        public let capabilities: Capabilities

        public enum CodingKeys: String, CodingKey {
            case authKey = "AuthKey"
            case voice
            case video
            case isManualMessageFetchEnabled = "fetchesMessages"
            case registrationId
            case pniRegistrationId
            case unidentifiedAccessKey
            case unrestrictedUnidentifiedAccess
            case registrationLockToken = "registrationLock"
            case encryptedDeviceName = "name"
            case discoverableByPhoneNumber
            case capabilities
        }

        public init(
            authKey: String,
            isManualMessageFetchEnabled: Bool,
            registrationId: UInt32,
            pniRegistrationId: UInt32,
            unidentifiedAccessKey: String?,
            unrestrictedUnidentifiedAccess: Bool,
            registrationLockToken: String?,
            encryptedDeviceName: String?,
            discoverableByPhoneNumber: Bool,
            canReceiveGiftBadges: Bool = RemoteConfig.canReceiveGiftBadges
        ) {
            self.authKey = authKey
            self.isManualMessageFetchEnabled = isManualMessageFetchEnabled
            self.registrationId = registrationId
            self.pniRegistrationId = pniRegistrationId
            self.unidentifiedAccessKey = unidentifiedAccessKey
            self.unrestrictedUnidentifiedAccess = unrestrictedUnidentifiedAccess
            self.registrationLockToken = registrationLockToken
            self.encryptedDeviceName = encryptedDeviceName
            self.discoverableByPhoneNumber = discoverableByPhoneNumber
            self.capabilities = Capabilities(canReceiveGiftBadges: canReceiveGiftBadges)
        }

        public struct Capabilities: Codable {
            public let gv2 = true
            public let gv2_2 = true
            public let gv2_3 = true
            public let transfer = true
            public let announcementGroup = true
            public let senderKey = true
            public let stories = true
            public let canReceiveGiftBadges: Bool
            // Every user going through the *new* registration
            // code paths should have this true.
            public let hasKBSBackups = true
            public let changeNumber = true

            public enum CodingKeys: String, CodingKey {
                case gv2
                case gv2_2 = "gv2-2"
                case gv2_3 = "gv2-3"
                case transfer
                case announcementGroup
                case senderKey
                case stories
                case canReceiveGiftBadges = "giftBadges"
                case hasKBSBackups = "storage"
                case changeNumber
            }
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
    public static func createAccountRequest(
        verificationMethod: VerificationMethod,
        e164: String,
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
        result.authPassword = accountAttributes.authKey
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
