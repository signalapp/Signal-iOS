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
    static let textSecureDeviceProvisioningAPIFormat  = "v1/provisioning/%@"
    static let textSecureDevicesAPIFormat  = "v1/devices/%@"
    static let textSecureVersionedProfileAPI  = "v1/profile/"
    static let textSecureProfileAvatarFormAPI  = "v1/profile/form/avatar"
    static let textSecure2FAAPI  = "v1/accounts/pin"
    static let textSecureRegistrationLockV2API  = "v1/accounts/registration_lock"
    static let textSecureBoostStripeCreatePaymentIntent = "v1/subscription/boost/create"
    static let textSecureBoostPaypalCreatePayment = "v1/subscription/boost/paypal/create"
    static let textSecureBoostPaypalConfirmPayment = "v1/subscription/boost/paypal/confirm"
    static let textSecureGiftBadgePricesAPI = "v1/subscription/boost/amounts/gift"

    static let textSecureHTTPTimeOut: TimeInterval = 10

    // MARK: -

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

    /// A request to create a Stripe payment intent for a boost.
    static func boostStripeCreatePaymentIntent(
        integerMoneyValue: UInt,
        inCurrencyCode currencyCode: Currency.Code,
        level: UInt64
    ) -> TSRequest {
        let request = TSRequest(url: URL(string: textSecureBoostStripeCreatePaymentIntent)!,
                                method: HTTPMethod.post.methodName,
                                parameters: ["currency": currencyCode.lowercased(),
                                             "amount": integerMoneyValue,
                                             "level": level])
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    /// A request to create a PayPal payment for a boost.
    static func boostPaypalCreatePayment(
        integerMoneyValue: UInt,
        inCurrencyCode currencyCode: Currency.Code,
        level: UInt64,
        returnUrl: URL,
        cancelUrl: URL
    ) -> TSRequest {
        let request = TSRequest(
            url: URL(string: textSecureBoostPaypalCreatePayment)!,
            method: HTTPMethod.post.methodName,
            parameters: [
                "currency": currencyCode.lowercased(),
                "amount": integerMoneyValue,
                "level": level,
                "returnUrl": returnUrl.absoluteString,
                "cancelUrl": cancelUrl.absoluteString
            ]
        )

        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    /// A request to confirm a PayPal payment for a boost.
    static func boostPaypalConfirmPayment(
        integerMoneyValue: UInt,
        inCurrencyCode currencyCode: Currency.Code,
        level: UInt64,
        payerId: String,
        paymentId: String,
        paymentToken: String
    ) -> TSRequest {
        let request = TSRequest(
            url: URL(string: textSecureBoostPaypalConfirmPayment)!,
            method: HTTPMethod.post.methodName,
            parameters: [
                "currency": currencyCode.lowercased(),
                "amount": integerMoneyValue,
                "level": level,
                "payerId": payerId,
                "paymentId": paymentId,
                "paymentToken": paymentToken
            ]
        )

        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    static let batchIdentityCheckElementsLimit = 1000
    static func batchIdentityCheckRequest(elements: [[String: String]]) -> TSRequest {
        precondition(elements.count <= batchIdentityCheckElementsLimit)
        return .init(url: .init(string: "v1/profile/identity_check/batch")!, method: HTTPMethod.post.methodName, parameters: ["elements": elements])
    }
}
