//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum OWSRequestFactory {

    static let textSecureAccountsAPI  = "v1/accounts"
    static let textSecureAttributesAPI  = "v1/accounts/attributes/"
    static let textSecureMessagesAPI  = "v1/messages/"
    static let textSecureMultiRecipientMessageAPI  = "v1/messages/multi_recipient"
    static let textSecureKeysAPI  = "v2/keys"
    static let textSecureSignedKeysAPI  = "v2/keys/signed"
    static let textSecureDirectoryAPI  = "v1/directory"
    static let textSecure2FAAPI  = "v1/accounts/pin"
    static let textSecureRegistrationLockV2API  = "v1/accounts/registration_lock"
    static let textSecureGiftBadgePricesAPI = "v1/subscription/boost/amounts/gift"

    static let textSecureHTTPTimeOut: TimeInterval = 10

    // MARK: - Other

    static func allocAttachmentRequestV4() -> TSRequest {
        return TSRequest(url: URL(string: "v4/attachments/form/upload")!, method: "GET", parameters: [:])
    }

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

        let path = "v1/certificate/auth/group?redemptionStartSeconds=\(fromRedemptionSeconds)&redemptionEndSeconds=\(toRedemptionSeconds)"
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

    static func getMessagesRequest() -> TSRequest {
        var request = TSRequest(url: URL(string: "v1/messages")!, method: "GET", parameters: [:])
        StoryManager.appendStoryHeaders(to: &request)
        request.shouldCheckDeregisteredOn401 = true
        return request
    }

    static func acknowledgeMessageDeliveryRequest(serverGuid: String) -> TSRequest {
        owsAssertDebug(!serverGuid.isEmpty)

        let path = "v1/messages/uuid/\(serverGuid)"

        return TSRequest(url: URL(string: path)!, method: "DELETE", parameters: [:])
    }

    static func udSenderCertificateRequest(uuidOnly: Bool) -> TSRequest {
        var path = "v1/certificate/delivery"
        if uuidOnly {
            path += "?includeE164=false"
        }
        return TSRequest(url: URL(string: path)!, method: "GET", parameters: [:])
    }

    static func submitMessageRequest(
        serviceId: ServiceId,
        messages: [DeviceMessage],
        timestamp: UInt64,
        isOnline: Bool,
        isUrgent: Bool,
        auth: TSRequest.SealedSenderAuth?
    ) -> TSRequest {
        // NOTE: messages may be empty; See comments in OWSDeviceManager.
        owsAssertDebug(timestamp > 0)

        let path = "\(self.textSecureMessagesAPI)\(serviceId.serviceIdString)?story=\(auth?.isStory == true ? "true" : "false")"

        // Returns the per-account-message parameters used when submitting a message to
        // the Signal Web Service.
        // See
        // <https://github.com/signalapp/Signal-Server/blob/65da844d70369cb8b44966cfb2d2eb9b925a6ba4/service/src/main/java/org/whispersystems/textsecuregcm/entities/IncomingMessageList.java>.
        let parameters: [String: Any] = [
            "messages": messages.map { $0.requestParameters() },
            "timestamp": timestamp,
            "online": isOnline,
            "urgent": isUrgent
        ]

        var request = TSRequest(url: URL(string: path)!, method: "PUT", parameters: parameters)
        // Use 45 seconds (the maximum time allowed by the pinging logic) to
        // support larger messages. Message sends have automatic retries, so short
        // timeouts aren't useful because errors are invisible for ~24 hours.
        request.timeoutInterval = 45
        if let auth {
            request.auth = .sealedSender(auth)
        }
        return request
    }

    static func submitMultiRecipientMessageRequest(
        ciphertext: Data,
        timestamp: UInt64,
        isOnline: Bool,
        isUrgent: Bool,
        auth: TSRequest.SealedSenderAuth
    ) -> TSRequest {
        owsAssertDebug(timestamp > 0)

        // We build the URL by hand instead of passing the query parameters into the query parameters
        // AFNetworking won't handle both query parameters and an httpBody (which we need here)
        var components = URLComponents(string: self.textSecureMultiRecipientMessageAPI)!
        components.queryItems = [
            URLQueryItem(name: "ts", value: "\(timestamp)"),
            URLQueryItem(name: "online", value: isOnline ? "true" : "false"),
            URLQueryItem(name: "urgent", value: isUrgent ? "true" : "false"),
            URLQueryItem(name: "story", value: auth.isStory ? "true" : "false"),
        ]

        var request = TSRequest(url: components.url!, method: "PUT", parameters: nil)
        // Use 45 seconds (the maximum time allowed by the pinging logic) to
        // support larger messages. Message sends have automatic retries, so short
        // timeouts aren't useful because errors are invisible for ~24 hours.
        request.timeoutInterval = 45
        request.headers["Content-Type"] = "application/vnd.signal-messenger.mrm"
        request.auth = .sealedSender(auth)
        request.body = .data(ciphertext)
        return request
    }

    // MARK: - Registration

    static func disable2FARequest() -> TSRequest {
        return TSRequest(url: URL(string: self.textSecure2FAAPI)!, method: "DELETE", parameters: [:])
    }

    public static func enableRegistrationLockV2Request(token: String) -> TSRequest {
        owsAssertDebug(nil != token.nilIfEmpty)

        let url = URL(string: textSecureRegistrationLockV2API)!
        return TSRequest(url: url,
                         method: HTTPMethod.put.methodName,
                         parameters: [
                "registrationLock": token
            ])
    }

    static func disableRegistrationLockV2Request() -> TSRequest {
        let url = URL(string: textSecureRegistrationLockV2API)!
        return TSRequest(url: url,
                         method: HTTPMethod.delete.methodName,
                         parameters: [:])
    }

    public static func registerForPushRequest(apnsToken: String) -> TSRequest {
        owsAssertDebug(!apnsToken.isEmpty)

        let path = "\(self.textSecureAccountsAPI)/apn"

        return TSRequest(url: URL(string: path)!, method: "PUT", parameters: ["apnRegistrationId": apnsToken])
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
            parameters: nil
        )
    }

    static func provisionDevice(withMessageBody messageBody: Data, ephemeralDeviceId: String) -> TSRequest {
        owsAssertDebug(!messageBody.isEmpty)
        owsAssertDebug(!ephemeralDeviceId.isEmpty)

        return .init(
            url: .init(pathComponents: ["v1", "provisioning", ephemeralDeviceId])!,
            method: "PUT",
            parameters: ["body": messageBody.base64EncodedString()]
        )
    }

    // MARK: - Donations

    static func donationConfiguration() -> TSRequest {
        var result = TSRequest(
            url: .init(string: "v1/subscription/configuration")!,
            method: "GET",
            parameters: nil
        )
        result.auth = .anonymous
        return result
    }

    static func setSubscriberID(_ subscriberID: Data) -> TSRequest {
        var result = TSRequest(
            url: .init(pathComponents: ["v1", "subscription", subscriberID.asBase64Url])!,
            method: "PUT",
            parameters: nil
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func deleteSubscriberID(_ subscriberID: Data) -> TSRequest {
        var result = TSRequest(
            url: .init(pathComponents: ["v1", "subscription", subscriberID.asBase64Url])!,
            method: "DELETE",
            parameters: nil
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionSetDefaultPaymentMethod(
        subscriberId: Data,
        processor: String,
        paymentMethodId: String
    ) -> TSRequest {
        var result = TSRequest(
            url: .init(pathComponents: [
                "v1",
                "subscription",
                subscriberId.asBase64Url,
                "default_payment_method",
                processor,
                paymentMethodId
            ])!,
            method: "POST",
            parameters: nil
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionSetDefaultIDEALPaymentMethod(
        subscriberId: Data,
        setupIntentId: String
    ) -> TSRequest {
        var result = TSRequest(
            url: .init(pathComponents: [
                "v1",
                "subscription",
                subscriberId.asBase64Url,
                "default_payment_method_for_ideal",
                setupIntentId
            ])!,
            method: "POST",
            parameters: nil
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionCreateStripePaymentMethodRequest(subscriberID: Data) -> TSRequest {
        var result = TSRequest(
            url: .init(pathComponents: [
                "v1",
                "subscription",
                subscriberID.asBase64Url,
                "create_payment_method",
            ])!,
            method: "POST",
            parameters: nil
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionCreatePaypalPaymentMethodRequest(
        subscriberID: Data,
        returnURL: URL,
        cancelURL: URL
    ) -> TSRequest {
        var result = TSRequest(
            url: .init(pathComponents: [
                "v1",
                "subscription",
                subscriberID.asBase64Url,
                "create_payment_method",
                "paypal",
            ])!,
            method: "POST",
            parameters: [
                "returnUrl": returnURL.absoluteString,
                "cancelUrl": cancelURL.absoluteString,
            ]
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionSetSubscriptionLevelRequest(
        subscriberID: Data,
        level: UInt,
        currency: String,
        idempotencyKey: String
    ) -> TSRequest {
        var result = TSRequest(
            url: .init(pathComponents: [
                "v1",
                "subscription",
                subscriberID.asBase64Url,
                "level",
                String(level),
                currency,
                idempotencyKey,
            ])!,
            method: "PUT",
            parameters: nil
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionReceiptCredentialsRequest(
        subscriberID: Data,
        request: Data
    ) -> TSRequest {
        var result = TSRequest(
            url: .init(pathComponents: [
                "v1",
                "subscription",
                subscriberID.asBase64Url,
                "receipt_credentials",
            ])!,
            method: "POST",
            parameters: [
                "receiptCredentialRequest": request.base64EncodedString(),
            ]
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionRedeemReceiptCredential(
        receiptCredentialPresentation: Data
    ) -> TSRequest {
        return TSRequest(
            url: .init(pathComponents: [
                "v1",
                "donation",
                "redeem-receipt",
            ])!,
            method: "POST",
            parameters: [
                "receiptCredentialPresentation": receiptCredentialPresentation.base64EncodedString(),
                "visible": DonationSubscriptionManager.displayBadgesOnProfile,
                "primary": false,
            ]
        )
    }

    static func boostReceiptCredentials(
        with paymentIntentID: String,
        for paymentProcessor: String,
        request: Data
    ) -> TSRequest {
        var result = TSRequest(
            url: .init(pathComponents: [
                "v1",
                "subscription",
                "boost",
                "receipt_credentials",
            ])!,
            method: "POST",
            parameters: [
                "paymentIntentId": paymentIntentID,
                "receiptCredentialRequest": request.base64EncodedString(),
                "processor": paymentProcessor,
            ]
        )
        result.auth = .anonymous
        return result
    }

    public static func bankMandateRequest(bankTransferType: StripePaymentMethod.BankTransfer) -> TSRequest {
        var result = TSRequest(
            url: .init(pathComponents: [
                "v1",
                "subscription",
                "bank_mandate",
                bankTransferType.rawValue,
            ])!,
            method: "GET",
            parameters: nil
        )
        result.headers[HttpHeaders.acceptLanguageHeaderKey] = HttpHeaders.acceptLanguageHeaderValue
        result.auth = .anonymous
        return result
    }

    // MARK: - Keys

    static func preKeyRequestParameters(_ preKeyRecord: SignalServiceKit.PreKeyRecord) -> [String: Any] {
        [
            "keyId": preKeyRecord.id,
            "publicKey": preKeyRecord.keyPair.keyPair.publicKey.serialize().base64EncodedStringWithoutPadding()
        ]
    }

    static func signedPreKeyRequestParameters(_ signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord) -> [String: Any] {
        [
            "keyId": signedPreKeyRecord.id,
            "publicKey": signedPreKeyRecord.keyPair.keyPair.publicKey.serialize().base64EncodedStringWithoutPadding(),
            "signature": signedPreKeyRecord.signature.base64EncodedStringWithoutPadding()
        ]
    }

    static func pqPreKeyRequestParameters(_ pqPreKeyRecord: KyberPreKeyRecord) -> [String: Any] {
        [
            "keyId": pqPreKeyRecord.id,
            "publicKey": pqPreKeyRecord.keyPair.publicKey.serialize().base64EncodedStringWithoutPadding(),
            "signature": pqPreKeyRecord.signature.base64EncodedStringWithoutPadding()
        ]
    }

    static func availablePreKeysCountRequest(for identity: OWSIdentity) -> TSRequest {
        var path = self.textSecureKeysAPI
        if let queryParam = queryParam(for: identity) {
            path += "?" + queryParam
        }
        return TSRequest(url: URL(string: path)!, method: "GET", parameters: [:])
    }

    static func recipientPreKeyRequest(serviceId: ServiceId, deviceId: DeviceId, auth: TSRequest.SealedSenderAuth?) -> TSRequest {
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
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord?,
        prekeyRecords: [SignalServiceKit.PreKeyRecord]?,
        pqLastResortPreKeyRecord: KyberPreKeyRecord?,
        pqPreKeyRecords: [KyberPreKeyRecord]?,
        auth: ChatServiceAuth
    ) -> TSRequest {
        var path = textSecureKeysAPI
        if let queryParam = queryParam(for: identity) {
            path = path.appending("?\(queryParam)")
        }

        var parameters = [String: Any]()

        if let signedPreKeyRecord {
            parameters["signedPreKey"] = signedPreKeyRequestParameters(signedPreKeyRecord)
        }
        if let prekeyRecords {
            parameters["preKeys"] = prekeyRecords.map { self.preKeyRequestParameters($0) }
        }
        if let pqLastResortPreKeyRecord {
            parameters["pqLastResortPreKey"] = pqPreKeyRequestParameters(pqLastResortPreKeyRecord)
        }
        if let pqPreKeyRecords {
            parameters["pqPreKeys"] = pqPreKeyRecords.map { self.pqPreKeyRequestParameters($0) }
        }

        var request = TSRequest(
            url: URL(string: path)!,
            method: "PUT",
            parameters: parameters
        )
        request.auth = .identified(auth)
        return request
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
        auth: TSRequest.Auth
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
        auth: ChatServiceAuth
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

// MARK: -

extension DeviceMessage {
    /// Returns the per-device-message parameters when sending a message.
    ///
    /// See <https://github.com/signalapp/Signal-Server/blob/ab26a65/service/src/main/java/org/whispersystems/textsecuregcm/entities/IncomingMessage.java>.
    func requestParameters() -> NSDictionary {
        return [
            "type": type.rawValue,
            "destinationDeviceId": destinationDeviceId.uint32Value,
            "destinationRegistrationId": Int32(bitPattern: destinationRegistrationId),
            "content": content.base64EncodedString()
        ]
    }
}
