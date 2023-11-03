//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public extension OWSRequestFactory {

    static let textSecureAccountsAPI  = "v1/accounts"
    static let textSecureAttributesAPI  = "v1/accounts/attributes/"
    static let textSecureMessagesAPI  = "v1/messages/"
    static let textSecureMultiRecipientMessageAPI  = "v1/messages/multi_recipient"
    static let textSecureKeysAPI  = "v2/keys"
    static let textSecureSignedKeysAPI  = "v2/keys/signed"
    static let textSecureDirectoryAPI  = "v1/directory"
    static let textSecureDevicesAPIFormat  = "v1/devices/%@"
    static let textSecureVersionedProfileAPI  = "v1/profile/"
    static let textSecureProfileAvatarFormAPI  = "v1/profile/form/avatar"
    static let textSecure2FAAPI  = "v1/accounts/pin"
    static let textSecureRegistrationLockV2API  = "v1/accounts/registration_lock"
    static let textSecureGiftBadgePricesAPI = "v1/subscription/boost/amounts/gift"

    static let textSecureHTTPTimeOut: TimeInterval = 10

    // MARK: - Registration

    static func enable2FARequest(withPin pin: String) -> TSRequest {
        owsAssertBeta(!pin.isEmpty)
        return .init(url: URL(string: textSecure2FAAPI)!, method: "PUT", parameters: ["pin": pin])
    }

    static func enableRegistrationLockV2Request(token: String) -> TSRequest {
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

    static let batchIdentityCheckElementsLimit = 1000
    static func batchIdentityCheckRequest(elements: [[String: String]]) -> TSRequest {
        precondition(elements.count <= batchIdentityCheckElementsLimit)
        return .init(url: .init(string: "v1/profile/identity_check/batch")!, method: HTTPMethod.post.methodName, parameters: ["elements": elements])
    }

    // MARK: - Capabilities

    @nonobjc
    static func updateLinkedDeviceCapabilitiesRequest(for capabilities: AccountAttributes.Capabilities) -> TSRequest {
        // If you are updating capabilities for a primary device, use `updateAccountAttributes` instead
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        owsAssertDebug(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == false)
        return TSRequest(url: URL(string: "v1/devices/capabilities")!, method: "PUT", parameters: capabilities.requestParameters)
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

    @nonobjc
    static func deleteDeviceRequest(
        _ device: OWSDevice
    ) -> TSRequest {
        return TSRequest(
            url: URL(string: "/v1/devices/\(device.deviceId)")!,
            method: HTTPMethod.delete.methodName,
            parameters: nil
        )
    }

    // MARK: - Donations

    static func donationConfiguration() -> TSRequest {
        let result = TSRequest(
            url: .init(string: "v1/subscription/configuration")!,
            method: "GET",
            parameters: nil
        )
        result.shouldHaveAuthorizationHeaders = false
        return result
    }

    static func setSubscriberID(_ subscriberID: Data) -> TSRequest {
        let result = TSRequest(
            url: .init(pathComponents: ["v1", "subscription", subscriberID.asBase64Url])!,
            method: "PUT",
            parameters: nil
        )
        result.shouldHaveAuthorizationHeaders = false
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func deleteSubscriberID(_ subscriberID: Data) -> TSRequest {
        let result = TSRequest(
            url: .init(pathComponents: ["v1", "subscription", subscriberID.asBase64Url])!,
            method: "DELETE",
            parameters: nil
        )
        result.shouldHaveAuthorizationHeaders = false
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionSetDefaultPaymentMethod(
        subscriberID: Data,
        processor: String,
        paymentID: String
    ) -> TSRequest {
        let result = TSRequest(
            url: .init(pathComponents: [
                "v1",
                "subscription",
                subscriberID.asBase64Url,
                "default_payment_method",
                processor,
                paymentID
            ])!,
            method: "POST",
            parameters: nil
        )
        result.shouldHaveAuthorizationHeaders = false
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionGetCurrentSubscriptionLevelRequest(subscriberID: Data) -> TSRequest {
        let result = TSRequest(
            url: .init(pathComponents: [
                "v1",
                "subscription",
                subscriberID.asBase64Url,
            ])!,
            method: "GET",
            parameters: nil
        )
        result.shouldHaveAuthorizationHeaders = false
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionCreateStripePaymentMethodRequest(subscriberID: Data) -> TSRequest {
        let result = TSRequest(
            url: .init(pathComponents: [
                "v1",
                "subscription",
                subscriberID.asBase64Url,
                "create_payment_method",
            ])!,
            method: "POST",
            parameters: nil
        )
        result.shouldHaveAuthorizationHeaders = false
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionCreatePaypalPaymentMethodRequest(
        subscriberID: Data,
        returnURL: URL,
        cancelURL: URL
    ) -> TSRequest {
        let result = TSRequest(
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
        result.shouldHaveAuthorizationHeaders = false
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionSetSubscriptionLevelRequest(
        subscriberID: Data,
        level: UInt,
        currency: String,
        idempotencyKey: String
    ) -> TSRequest {
        let result = TSRequest(
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
        result.shouldHaveAuthorizationHeaders = false
        result.applyRedactionStrategy(.redactURLForSuccessResponses())
        return result
    }

    static func subscriptionReceiptCredentialsRequest(
        subscriberID: Data,
        request: Data
    ) -> TSRequest {
        let result = TSRequest(
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
        result.shouldHaveAuthorizationHeaders = false
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
                "visible": self.subscriptionManager.displayBadgesOnProfile,
                "primary": false,
            ]
        )
    }

    static func boostReceiptCredentials(
        with paymentIntentID: String,
        for paymentProcessor: String,
        request: Data
    ) -> TSRequest {
        let result = TSRequest(
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
        result.shouldHaveAuthorizationHeaders = false
        return result
    }

    @nonobjc
    static func bankMandateRequest(bankTransferType: StripePaymentMethod.BankTransfer) -> TSRequest {
        let result = TSRequest(
            url: .init(pathComponents: [
                "v1",
                "subscription",
                "bank_mandate",
                bankTransferType.rawValue,
            ])!,
            method: "GET",
            parameters: nil
        )
        result.addValue(OWSHttpHeaders.acceptLanguageHeaderValue, forHTTPHeaderField: OWSHttpHeaders.acceptLanguageHeaderKey)
        result.shouldHaveAuthorizationHeaders = false
        return result
    }
}

// MARK: - Messages

extension DeviceMessage {
    /// Returns the per-device-message parameters when sending a message.
    ///
    /// See <https://github.com/signalapp/Signal-Server/blob/ab26a65/service/src/main/java/org/whispersystems/textsecuregcm/entities/IncomingMessage.java>.
    @objc
    func requestParameters() -> NSDictionary {
        return [
            "type": type.rawValue,
            "destinationDeviceId": destinationDeviceId,
            "destinationRegistrationId": Int32(bitPattern: destinationRegistrationId),
            "content": serializedMessage.base64EncodedString()
        ]
    }
}

// MARK: - Keys

extension OWSRequestFactory {
    @objc
    static func preKeyRequestParameters(_ preKeyRecord: PreKeyRecord) -> [String: Any] {
        [
            "keyId": preKeyRecord.id,
            "publicKey": preKeyRecord.keyPair.publicKey.prependKeyType().base64EncodedStringWithoutPadding()
        ]
    }

    @objc
    static func signedPreKeyRequestParameters(_ signedPreKeyRecord: SignedPreKeyRecord) -> [String: Any] {
        [
            "keyId": signedPreKeyRecord.id,
            "publicKey": signedPreKeyRecord.keyPair.publicKey.prependKeyType().base64EncodedStringWithoutPadding(),
            "signature": signedPreKeyRecord.signature.base64EncodedStringWithoutPadding()
        ]
    }

    static func pqPreKeyRequestParameters(_ pqPreKeyRecord: KyberPreKeyRecord) -> [String: Any] {
        [
            "keyId": pqPreKeyRecord.id,
            "publicKey": Data(pqPreKeyRecord.keyPair.publicKey.serialize()).base64EncodedStringWithoutPadding(),
            "signature": pqPreKeyRecord.signature.base64EncodedStringWithoutPadding()
        ]
    }

    /// If a username and password are both provided, those are used for the request's
    /// Authentication header. Otherwise, the default header is used (whatever's on
    /// TSAccountManager).
    static func registerPrekeysRequest(
        identity: OWSIdentity,
        identityKey: Data,
        signedPreKeyRecord: SignedPreKeyRecord?,
        prekeyRecords: [PreKeyRecord]?,
        pqLastResortPreKeyRecord: KyberPreKeyRecord?,
        pqPreKeyRecords: [KyberPreKeyRecord]?,
        auth: ChatServiceAuth
    ) -> TSRequest {
        owsAssertDebug(identityKey.count > 0)

        var path = textSecureKeysAPI
        if let queryParam = queryParam(for: identity) {
            path = path.appending("?\(queryParam)")
        }

        var parameters = [String: Any]()

        parameters["identityKey"] = identityKey.prependKeyType().base64EncodedStringWithoutPadding()
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

        let request = TSRequest(
            url: URL(string: path)!,
            method: "PUT",
            parameters: parameters
        )
        request.setAuth(auth)
        return request
    }

    @objc
    static func queryParam(for identity: OWSIdentity) -> String? {
        switch identity {
        case .aci:
            return nil
        case .pni:
            return "identity=pni"
        }
    }

    public static func verifySecondaryDeviceRequest(
        verificationCode: String,
        phoneNumber: String,
        authPassword: String,
        attributes: AccountAttributes,
        apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
        prekeyBundles: RegistrationPreKeyUploadBundles
    ) -> TSRequest {
        owsAssertDebug(verificationCode.isEmpty.negated)
        owsAssertDebug(phoneNumber.isEmpty.negated)
        owsAssertDebug(apnRegistrationId != nil || attributes.isManualMessageFetchEnabled)

        let urlPathComponents = URLPathComponents(
            ["v1", "devices", "link"]
        )

        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let jsonEncoder = JSONEncoder()
        let accountAttributesData = try! jsonEncoder.encode(attributes)
        let accountAttributesDict = try! JSONSerialization.jsonObject(with: accountAttributesData, options: .fragmentsAllowed) as! [String: Any]

        let parameters: [String: Any] = [
            "verificationCode": verificationCode,
            "accountAttributes": accountAttributesDict,
            "aciSignedPreKey": OWSRequestFactory.signedPreKeyRequestParameters(prekeyBundles.aci.signedPreKey),
            "pniSignedPreKey": OWSRequestFactory.signedPreKeyRequestParameters(prekeyBundles.pni.signedPreKey),
            "aciPqLastResortPreKey": OWSRequestFactory.pqPreKeyRequestParameters(prekeyBundles.aci.lastResortPreKey),
            "pniPqLastResortPreKey": OWSRequestFactory.pqPreKeyRequestParameters(prekeyBundles.pni.lastResortPreKey)
        ]

        let result = TSRequest(url: url, method: "PUT", parameters: parameters)
        // The "verify code" request handles auth differently.
        result.authUsername = phoneNumber
        result.authPassword = authPassword
        return result
    }
}
