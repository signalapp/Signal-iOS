//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public extension OWSRequestFactory {

    static let textSecureAccountsAPI  = "v1/accounts"
    static let textSecureAttributesAPI  = "v1/accounts/attributes/"
    static let textSecureMessagesAPI  = "v1/messages/"
    static let textSecureMultiRecipientMessageAPI  = "v1/messages/multi_recipient"
    static let textSecureKeysAPI  = "v2/keys"
    static let textSecureSignedKeysAPI  = "v2/keys/signed"
    static let textSecureDirectoryAPI  = "v1/directory"
    static let textSecureDeviceProvisioningCodeAPI  = "v1/devices/provisioning/code"
    static let textSecureDevicesAPIFormat  = "v1/devices/%@"
    static let textSecureVersionedProfileAPI  = "v1/profile/"
    static let textSecureProfileAvatarFormAPI  = "v1/profile/form/avatar"
    static let textSecure2FAAPI  = "v1/accounts/pin"
    static let textSecureRegistrationLockV2API  = "v1/accounts/registration_lock"
    static let textSecureGiftBadgePricesAPI = "v1/subscription/boost/amounts/gift"

    static let textSecureHTTPTimeOut: TimeInterval = 10

    // MARK: - Registration

    static func requestPreauthChallenge(
        e164: String,
        pushToken: String,
        isVoipToken: Bool
    ) -> TSRequest {
        owsAssertDebug(!e164.isEmpty)
        owsAssertDebug(!pushToken.isEmpty)

        let urlPathComponents = URLPathComponents(
            ["v1", "accounts", "apn", "preauth", pushToken, e164]
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        urlComponents.queryItems = [.init(name: "voip", value: isVoipToken ? "true" : "false")]
        let url = urlComponents.url!

        let result = TSRequest(url: url, method: "GET", parameters: nil)
        result.shouldHaveAuthorizationHeaders = false
        return result
    }

    static func enable2FARequest(withPin pin: String) -> TSRequest {
        owsAssertBeta(!pin.isEmpty)
        return .init(url: URL(string: textSecure2FAAPI)!, method: "PUT", parameters: ["pin": pin])
    }

    static func changePhoneNumberRequest(newPhoneNumberE164: String,
                                         verificationCode: String,
                                         registrationLock: String?) -> TSRequest {
        owsAssertDebug(nil != newPhoneNumberE164.strippedOrNil)
        owsAssertDebug(nil != verificationCode.strippedOrNil)

        let url = URL(string: "\(textSecureAccountsAPI)/number")!
        var parameters: [String: Any] = [
            "number": newPhoneNumberE164,
            "code": verificationCode
        ]
        if let registrationLock = registrationLock?.strippedOrNil {
            parameters["reglock"] = registrationLock
        }

        return TSRequest(url: url,
                  method: HTTPMethod.put.methodName,
                  parameters: parameters)
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

    // MARK: - Devices

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
        result.shouldRedactUrlInLogs = true
        return result
    }
}
