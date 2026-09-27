//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum OWSRequestFactory {

    static let textSecureAccountsAPI = "v1/accounts"
    static let textSecureAttributesAPI = "v1/accounts/attributes/"
    static let textSecureKeysAPI = "v2/keys"
    static let textSecureSignedKeysAPI = "v2/keys/signed"
    static let textSecureDirectoryAPI = "v1/directory"
    static let textSecure2FAAPI = "v1/accounts/pin"
    static let textSecureRegistrationLockV2API = "v1/accounts/registration_lock"
    static let textSecureGiftBadgePricesAPI = "v1/subscription/boost/amounts/gift"

    public static let textSecureHTTPTimeOut: TimeInterval = 10

    // MARK: - Other

    static func currencyConversionRequest() -> TSRequest {
        return TSRequest(url: URL(string: "v1/payments/conversions")!, method: "GET", parameters: [:])
    }

    static func getRemoteConfigRequest(eTag: String?) -> TSRequest {
        var request = TSRequest(url: URL(string: "v2/config/")!, method: "GET", parameters: [:])
        if let eTag {
            request.headers["If-None-Match"] = eTag
        }
        return request
    }

    public static func callingRelaysRequest() -> TSRequest {
        return TSRequest(url: URL(string: "v2/calling/relays")!, method: "GET", parameters: [:])
    }

    // MARK: - Auth

    static func authCredentialRequest(from fromRedemptionSeconds: UInt64, to toRedemptionSeconds: UInt64) -> TSRequest {
        owsAssertDebug(fromRedemptionSeconds > 0)
        owsAssertDebug(toRedemptionSeconds > 0)

        let path = "v1/certificate/auth/group?redemptionStartSeconds=\(fromRedemptionSeconds)&redemptionEndSeconds=\(toRedemptionSeconds)&v101=true"
        return TSRequest(url: URL(string: path)!, method: "GET", parameters: [:])
    }

    public static func paymentsAuthenticationCredentialRequest() -> TSRequest {
        return TSRequest(url: URL(string: "v1/payments/auth")!, method: "GET", parameters: [:])
    }

    static func remoteAttestationAuthRequestForCDSI() -> TSRequest {
        return TSRequest(url: URL(string: "v2/directory/auth")!, method: "GET", parameters: [:])
    }

    static func remoteAttestationAuthRequestForSVR2() -> TSRequest {
        return TSRequest(url: URL(string: "v2/svr/auth")!, method: "GET", parameters: [:])
    }

    static func storageAuthRequest(auth: ChatServiceAuth) -> TSRequest {
        var result = TSRequest(url: URL(string: "v1/storage/auth")!, method: "GET", parameters: [:])
        result.auth = .identified(auth)
        return result
    }

    // MARK: - Challenges

    static func pushChallengeRequest() -> TSRequest {
        return TSRequest(url: URL(string: "v1/challenge/push")!, method: "POST", parameters: [:])
    }

    static func pushChallengeResponse(token: String) -> TSRequest {
        return TSRequest(url: URL(string: "v1/challenge")!, method: "PUT", parameters: ["type": "rateLimitPushChallenge", "challenge": token])
    }

    static func recaptchChallengeResponse(serverToken: String, captchaToken: String) -> TSRequest {
        return TSRequest(url: URL(string: "v1/challenge")!, method: "PUT", parameters: ["type": "captcha", "token": serverToken, "captcha": captchaToken])
    }

    // MARK: - Messages

    static func udSenderCertificateRequest(uuidOnly: Bool) -> TSRequest {
        var path = "v1/certificate/delivery"
        if uuidOnly {
            path += "?includeE164=false"
        }
        return TSRequest(url: URL(string: path)!, method: "GET", parameters: [:])
    }

    static func accountRequest(serviceId: ServiceId) -> TSRequest {
        var request = TSRequest(url: URL(string: "v1/accounts/account/\(serviceId.serviceIdString)")!, method: "HEAD")
        request.auth = .anonymous
        return request
    }

    // MARK: - Registration

    struct RegistrationRecoveryPassword: Encodable {
        let wrappedValue: SignalServiceKit.RegistrationRecoveryPassword

        init(_ wrappedValue: SignalServiceKit.RegistrationRecoveryPassword) {
            self.wrappedValue = wrappedValue
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(self.wrappedValue.canonicalStringRepresentation)
        }
    }

    struct RegistrationLock: Encodable {
        let wrappedValue: SignalServiceKit.RegistrationLock

        init(_ wrappedValue: SignalServiceKit.RegistrationLock) {
            self.wrappedValue = wrappedValue
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(self.wrappedValue.canonicalStringRepresentation)
        }
    }

    static func enableRegistrationLockV2Request(token: SignalServiceKit.RegistrationLock, logger: PrefixedLogger) -> TSRequest {
        let url = URL(string: textSecureRegistrationLockV2API)!
        return TSRequest(
            url: url,
            method: HTTPMethod.put.methodName,
            parameters: [
                "registrationLock": token.canonicalStringRepresentation,
            ],
            logger: logger,
        )
    }

    static func disableRegistrationLockV2Request() -> TSRequest {
        let url = URL(string: textSecureRegistrationLockV2API)!
        return TSRequest(
            url: url,
            method: HTTPMethod.delete.methodName,
            parameters: [:],
        )
    }

    static func unregisterAccountRequest() -> TSRequest {
        let path = "\(self.textSecureAccountsAPI)/me"
        return TSRequest(url: URL(string: path)!, method: "DELETE", parameters: [:])
    }

    static let batchIdentityCheckElementsLimit = 1000
    static func batchIdentityCheckRequest(elements: [[String: String]]) -> TSRequest {
        precondition(elements.count <= batchIdentityCheckElementsLimit)
        var request = TSRequest(
            url: .init(string: "v1/profile/identity_check/batch")!,
            method: HTTPMethod.post.methodName,
            parameters: ["elements": elements],
        )
        request.auth = .anonymous
        return request
    }

    // MARK: - Devices

    static func deviceProvisioningCode() -> TSRequest {
        return TSRequest(
            url: URL(string: "v1/devices/provisioning/code")!,
            method: "GET",
            parameters: nil,
        )
    }

    static func provisionDevice(withMessageBody messageBody: Data, ephemeralDeviceId: String) -> TSRequest {
        owsAssertDebug(!messageBody.isEmpty)
        owsAssertDebug(!ephemeralDeviceId.isEmpty)

        return .init(
            url: URL(string: "v1/provisioning/\(ephemeralDeviceId)")!,
            method: "PUT",
            parameters: ["body": messageBody.base64EncodedString()],
        )
    }

    // MARK: - Donations

    /// Creates a new suscriberID record on the server. If the subscriberID
    /// already exists, extends its TTL.
    ///
    /// - Parameter donationPermit
    /// Required to create a new subscriberID; optional for an existing one.
    static func setSubscriberID(
        _ subscriberID: Data,
        donationPermit: DonationPermit?,
    ) -> TSRequest {
        var result = TSRequest(
            url: URL(string: "v1/subscription/\(subscriberID.asBase64Url)")!,
            method: "PUT",
            parameters: nil,
        )
        if let donationPermit {
            result.headers["Donation-Permit"] = donationPermit.serializedPermit.base64EncodedString()
        }
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURL(sensitiveValues: [subscriberID.asBase64Url]))
        return result
    }

    static func deleteSubscriberID(_ subscriberID: Data) -> TSRequest {
        var result = TSRequest(
            url: URL(string: "v1/subscription/\(subscriberID.asBase64Url)")!,
            method: "DELETE",
            parameters: nil,
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURL(sensitiveValues: [subscriberID.asBase64Url]))
        return result
    }

    static func subscriptionSetDefaultPaymentMethod(
        subscriberId: Data,
        processor: String,
        paymentMethodId: String,
    ) -> TSRequest {
        var result = TSRequest(
            url: URL(string: "v1/subscription/\(subscriberId.asBase64Url)/default_payment_method/\(processor)/\(paymentMethodId)")!,
            method: "POST",
            parameters: nil,
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURL(sensitiveValues: [
            subscriberId.asBase64Url,
            paymentMethodId,
        ]))
        return result
    }

    static func subscriptionSetDefaultIDEALPaymentMethod(
        subscriberId: Data,
        setupIntentId: String,
    ) -> TSRequest {
        var result = TSRequest(
            url: URL(string: "v1/subscription/\(subscriberId.asBase64Url)/default_payment_method_for_ideal/\(setupIntentId)")!,
            method: "POST",
            parameters: nil,
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURL(sensitiveValues: [
            subscriberId.asBase64Url,
            setupIntentId,
        ]))
        return result
    }

    static func subscriptionCreateStripePaymentMethodRequest(
        subscriberID: Data,
        donationPermit: DonationPermit,
    ) -> TSRequest {
        var result = TSRequest(
            url: URL(string: "v1/subscription/\(subscriberID.asBase64Url)/create_payment_method")!,
            method: "POST",
            parameters: nil,
        )
        result.headers["Donation-Permit"] = donationPermit.serializedPermit.base64EncodedString()
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURL(sensitiveValues: [subscriberID.asBase64Url]))
        return result
    }

    static func subscriptionCreatePaypalPaymentMethodRequest(
        subscriberID: Data,
        returnURL: URL,
        cancelURL: URL,
    ) -> TSRequest {
        var result = TSRequest(
            url: URL(string: "v1/subscription/\(subscriberID.asBase64Url)/create_payment_method/paypal")!,
            method: "POST",
            parameters: [
                "returnUrl": returnURL.absoluteString,
                "cancelUrl": cancelURL.absoluteString,
            ],
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURL(sensitiveValues: [subscriberID.asBase64Url]))
        return result
    }

    static func subscriptionSetSubscriptionLevelRequest(
        subscriberID: Data,
        level: UInt,
        currency: String,
        idempotencyKey: String,
    ) -> TSRequest {
        var result = TSRequest(
            url: URL(string: "v1/subscription/\(subscriberID.asBase64Url)/level/\(level)/\(currency)/\(idempotencyKey)")!,
            method: "PUT",
            parameters: nil,
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURL(sensitiveValues: [
            subscriberID.asBase64Url,
            idempotencyKey,
        ]))
        return result
    }

    static func subscriptionReceiptCredentialsRequest(
        subscriberID: Data,
        receiptCredentialRequest: ReceiptCredentialRequest,
    ) -> TSRequest {
        var result = TSRequest(
            url: URL(string: "v1/subscription/\(subscriberID.asBase64Url)/receipt_credentials")!,
            method: "POST",
            parameters: [
                "receiptCredentialRequest": receiptCredentialRequest.serialize().base64EncodedString(),
            ],
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURL(sensitiveValues: [subscriberID.asBase64Url]))
        return result
    }

    static func subscriptionRedeemReceiptCredential(
        receiptCredentialPresentation: Data,
        displayBadgesOnProfile: Bool,
    ) -> TSRequest {
        return TSRequest(
            url: URL(string: "v1/donation/redeem-receipt")!,
            method: "POST",
            parameters: [
                "receiptCredentialPresentation": receiptCredentialPresentation.base64EncodedString(),
                "visible": displayBadgesOnProfile,
                "primary": false,
            ],
        )
    }

    static func boostReceiptCredentials(
        paymentIntentID: String,
        paymentProcessor: DonationPaymentProcessor,
        receiptCredentialRequest: ReceiptCredentialRequest,
    ) -> TSRequest {
        var result = TSRequest(
            url: URL(string: "v1/subscription/boost/receipt_credentials")!,
            method: "POST",
            parameters: [
                "paymentIntentId": paymentIntentID,
                "receiptCredentialRequest": receiptCredentialRequest.serialize().base64EncodedString(),
                "processor": paymentProcessor.rawValue,
            ],
        )
        result.auth = .anonymous
        return result
    }

    public static func bankMandateRequest(bankTransferType: StripePaymentMethod.BankTransfer) -> TSRequest {
        var result = TSRequest(
            url: URL(string: "v1/subscription/bank_mandate/\(bankTransferType.rawValue)")!,
            method: "GET",
            parameters: nil,
        )
        result.headers[HttpHeaders.acceptLanguageHeaderKey] = HttpHeaders.acceptLanguageHeaderValue
        result.auth = .anonymous
        return result
    }

    // MARK: - Keys

    struct IdentityKey: Encodable {
        let wrappedValue: LibSignalClient.IdentityKey

        init(_ wrappedValue: LibSignalClient.IdentityKey) {
            self.wrappedValue = wrappedValue
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(self.wrappedValue.publicKey.serialize().base64EncodedString())
        }
    }

    struct PreKey: Encodable {
        let wrappedValue: LibSignalClient.PreKeyRecord

        init(_ wrappedValue: LibSignalClient.PreKeyRecord) {
            self.wrappedValue = wrappedValue
        }

        private enum CodingKeys: String, CodingKey {
            case keyId
            case publicKey
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.wrappedValue.id, forKey: .keyId)
            try container.encode(self.wrappedValue.publicKey().serialize().base64EncodedStringWithoutPadding(), forKey: .publicKey)
        }
    }

    struct SignedPreKey: Encodable {
        let wrappedValue: LibSignalClient.SignedPreKeyRecord

        init(_ wrappedValue: LibSignalClient.SignedPreKeyRecord) {
            self.wrappedValue = wrappedValue
        }

        private enum CodingKeys: String, CodingKey {
            case keyId
            case publicKey
            case signature
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.wrappedValue.id, forKey: .keyId)
            try container.encode(self.wrappedValue.publicKey().serialize().base64EncodedStringWithoutPadding(), forKey: .publicKey)
            try container.encode(self.wrappedValue.signature.base64EncodedStringWithoutPadding(), forKey: .signature)
        }
    }

    struct KyberPreKey: Encodable {
        let wrappedValue: LibSignalClient.KyberPreKeyRecord

        init(_ wrappedValue: LibSignalClient.KyberPreKeyRecord) {
            self.wrappedValue = wrappedValue
        }

        private enum CodingKeys: String, CodingKey {
            case keyId
            case publicKey
            case signature
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.wrappedValue.id, forKey: .keyId)
            try container.encode(self.wrappedValue.publicKey().serialize().base64EncodedStringWithoutPadding(), forKey: .publicKey)
            try container.encode(self.wrappedValue.signature.base64EncodedStringWithoutPadding(), forKey: .signature)
        }
    }

    static func availablePreKeysCountRequest(for identity: OWSIdentity) -> TSRequest {
        var path = self.textSecureKeysAPI
        if let queryParam = queryParam(for: identity) {
            path += "?" + queryParam
        }
        return TSRequest(url: URL(string: path)!, method: "GET", parameters: [:])
    }

    static func recipientPreKeyRequest(serviceId: ServiceId, deviceId: String, auth: TSRequest.SealedSenderAuth?) -> TSRequest {
        let path = "\(self.textSecureKeysAPI)/\(serviceId.serviceIdString)/\(deviceId)"

        var request = TSRequest(url: URL(string: path)!, method: "GET", parameters: [:])
        if let auth {
            request.auth = .sealedSender(auth)
        }
        return request
    }

    /// If a username and password are both provided, those are used for the request's
    /// Authentication header. Otherwise, the default header is used (whatever's on
    /// TSAccountManager).
    static func registerPrekeysRequest(
        identity: OWSIdentity,
        signedPreKeyRecord: LibSignalClient.SignedPreKeyRecord?,
        prekeyRecords: [LibSignalClient.PreKeyRecord]?,
        pqLastResortPreKeyRecord: LibSignalClient.KyberPreKeyRecord?,
        pqPreKeyRecords: [LibSignalClient.KyberPreKeyRecord]?,
        auth: ChatServiceAuth,
    ) -> TSRequest {
        var path = textSecureKeysAPI
        if let queryParam = queryParam(for: identity) {
            path = path.appending("?\(queryParam)")
        }

        var request = SetKeysRequest()
        if let signedPreKeyRecord {
            request.signedPreKey = OWSRequestFactory.SignedPreKey(signedPreKeyRecord)
        }
        if let prekeyRecords {
            request.preKeys = prekeyRecords.map { OWSRequestFactory.PreKey($0) }
        }
        if let pqLastResortPreKeyRecord {
            request.pqLastResortPreKey = OWSRequestFactory.KyberPreKey(pqLastResortPreKeyRecord)
        }
        if let pqPreKeyRecords {
            request.pqPreKeys = pqPreKeyRecords.map { OWSRequestFactory.KyberPreKey($0) }
        }

        var result = TSRequest(
            url: URL(string: path)!,
            method: "PUT",
            body: .encodable(request),
        )
        result.auth = .identified(auth)
        result.timeoutInterval = 45
        return result
    }

    private struct SetKeysRequest: Encodable {
        var signedPreKey: OWSRequestFactory.SignedPreKey?
        var preKeys: [OWSRequestFactory.PreKey]?
        var pqLastResortPreKey: OWSRequestFactory.KyberPreKey?
        var pqPreKeys: [OWSRequestFactory.KyberPreKey]?
    }

    static func queryParam(for identity: OWSIdentity) -> String? {
        switch identity {
        case .aci:
            return nil
        case .pni:
            return "identity=pni"
        }
    }

    // MARK: - Profiles

    static func getUnversionedProfileRequest(serviceId: ServiceId, auth: TSRequest.Auth) -> TSRequest {
        let path = "v1/profile/\(serviceId.serviceIdString)"
        var request = TSRequest(url: URL(string: path)!, method: "GET", parameters: [:])
        request.auth = auth
        return request
    }

    static func getVersionedProfileRequest(
        aci: Aci,
        profileKeyVersion: String,
        credentialRequest: Data?,
        auth: TSRequest.Auth,
    ) -> TSRequest {
        var components = [String]()
        components.append(aci.serviceIdString)
        components.append(profileKeyVersion)
        if let credentialRequest, !credentialRequest.isEmpty {
            components.append(credentialRequest.hexadecimalString + "?credentialType=expiringProfileKey")
        }

        let path = "v1/profile/\(components.joined(separator: "/"))"

        var request = TSRequest(url: URL(string: path)!, method: "GET", parameters: [:])
        request.auth = auth
        return request
    }

    public static func setVersionedProfileRequest(
        name: ProfileValue?,
        bio: ProfileValue?,
        bioEmoji: ProfileValue?,
        hasAvatar: Bool,
        sameAvatar: Bool,
        paymentAddress: ProfileValue?,
        phoneNumberSharing: ProfileValue,
        visibleBadgeIds: [String],
        version: String,
        commitment: Data,
        auth: ChatServiceAuth,
    ) -> TSRequest {
        var parameters: [String: Any] = [
            "avatar": hasAvatar,
            "sameAvatar": sameAvatar,
            "badgeIds": visibleBadgeIds,
            "commitment": commitment.base64EncodedString(),
            "phoneNumberSharing": phoneNumberSharing.encryptedBase64Value,
            "version": version,
        ]
        if let name {
            parameters["name"] = name.encryptedBase64Value
        }
        if let bio {
            parameters["about"] = bio.encryptedBase64Value
        }
        if let bioEmoji {
            parameters["aboutEmoji"] = bioEmoji.encryptedBase64Value
        }
        if let paymentAddress {
            parameters["paymentAddress"] = paymentAddress.encryptedBase64Value
        }
        var request = TSRequest(url: URL(string: "v1/profile/")!, method: "PUT", parameters: parameters)
        request.auth = .identified(auth)
        return request
    }
}
