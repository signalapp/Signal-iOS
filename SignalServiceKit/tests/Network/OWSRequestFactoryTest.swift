//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class OWSRequestFactoryTest: XCTestCase {
    private func getUdAccessKey() -> SMKUDAccessKey {
        let profileKey = Aes256Key(data: Data(count: Int(Aes256Key.keyByteLength)))!
        return SMKUDAccessKey(profileKey: profileKey)
    }

    private func queryItemsAsDictionary(url: URL) throws -> [String: String] {
        let urlComponents = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false), "URL components")
        let queryItems = urlComponents.queryItems ?? []
        var result = [String: String]()
        for queryItem in queryItems {
            XCTAssertNil(result[queryItem.name], "Duplicate query item \(queryItem.name)")
            result[queryItem.name] = queryItem.value
        }
        return result
    }

    // MARK: - Devices

    func testDeviceProvisioning() {
        let request = OWSRequestFactory.provisionDevice(
            withMessageBody: .init([1, 2, 3]),
            ephemeralDeviceId: "foo bar"
        )

        XCTAssertEqual(request.url.relativeString, "v1/provisioning/foo%20bar")
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.parameters as! [String: String], ["body": "AQID"])
    }

    // MARK: - Message requests

    func testSubmitMessageRequest() throws {
        let udAccessKey = getUdAccessKey()

        let serviceId = Aci.randomForTesting()

        let request = OWSRequestFactory.submitMessageRequest(
            serviceId: serviceId,
            messages: [],
            timestamp: 1234,
            isOnline: true,
            isUrgent: false,
            auth: .accessKey(udAccessKey)
        )

        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.url.path, "v1/messages/\(serviceId.serviceIdString)")
        XCTAssertEqual(Set(request.parameters.keys), Set(["messages", "timestamp", "online", "urgent"]))
        XCTAssertEqual(request.parameters["messages"] as? NSArray, [])
        XCTAssertEqual(request.parameters["timestamp"] as? UInt64, 1234)
        XCTAssertEqual(request.parameters["online"] as? Bool, true)
        XCTAssertEqual(request.parameters["urgent"] as? Bool, false)
        XCTAssertEqual(try queryItemsAsDictionary(url: request.url), ["story": "false"])
    }

    // MARK: - Donations

    func testDonationConfiguration() {
        let request = OWSRequestFactory.donationConfiguration()

        XCTAssertEqual(request.url.path, "v1/subscription/configuration")
        XCTAssertEqual(request.method, "GET")
    }

    func testBoostStripeCreatePaymentIntentWithAmount() {
        let testCases: [(paymentMethod: OWSRequestFactory.StripePaymentMethod, expectedValue: String)] = [
            (.card, "CARD"),
            (.bankTransfer(.sepa), "SEPA_DEBIT"),
        ]

        for (paymentMethod, expectedPaymentMethodValue) in testCases {
            let request = OWSRequestFactory.boostStripeCreatePaymentIntent(
                integerMoneyValue: 123,
                inCurrencyCode: "CHF",
                level: 456,
                paymentMethod: paymentMethod
            )

            XCTAssertEqual(request.url.path, "v1/subscription/boost/create")
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(Set(request.parameters.keys), Set(["currency", "amount", "level", "paymentMethod"]))
            XCTAssertEqual(request.parameters["currency"] as? String, "chf")
            XCTAssertEqual(request.parameters["amount"] as? UInt, 123)
            XCTAssertEqual(request.parameters["level"] as? UInt64, 456)
            XCTAssertEqual(request.parameters["paymentMethod"] as? String, expectedPaymentMethodValue)
        }
    }

    func testBoostPaypalCreatePaymentIntentWithAmount() {
        let request = OWSRequestFactory.boostPaypalCreatePayment(
            integerMoneyValue: 123,
            inCurrencyCode: "CHF",
            level: 456,
            returnUrl: URL(string: "https://example.com/approved")!,
            cancelUrl: URL(string: "https://example.com/canceled")!
        )

        XCTAssertEqual(request.url.path, "v1/subscription/boost/paypal/create")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Set(request.parameters.keys), Set([
            "currency", "amount", "level",
            "returnUrl", "cancelUrl"
        ]))
        XCTAssertEqual(request.parameters["currency"] as? String, "chf")
        XCTAssertEqual(request.parameters["amount"] as? UInt, 123)
        XCTAssertEqual(request.parameters["level"] as? UInt64, 456)
        XCTAssertEqual(request.parameters["returnUrl"] as? String, "https://example.com/approved")
        XCTAssertEqual(request.parameters["cancelUrl"] as? String, "https://example.com/canceled")
    }

    func testSetSubscriberID() {
        let request = OWSRequestFactory.setSubscriberID(.init([255, 128]))

        XCTAssertEqual(request.url.path, "v1/subscription/_4A")
        XCTAssertEqual(request.method, "PUT")
    }

    func testDeleteSubscriberID() {
        let request = OWSRequestFactory.deleteSubscriberID(.init([255, 128]))

        XCTAssertEqual(request.url.path, "v1/subscription/_4A")
        XCTAssertEqual(request.method, "DELETE")
    }

    func testSubscriptionSetDefaultPaymentMethod() {
        let request = OWSRequestFactory.subscriptionSetDefaultPaymentMethod(
            subscriberId: Data([255, 128]),
            processor: "STRIPE",
            paymentMethodId: "xyz"
        )

        XCTAssertEqual(request.url.path, "v1/subscription/_4A/default_payment_method/STRIPE/xyz")
        XCTAssertEqual(request.method, "POST")
    }

    func testSubscriptionCreateStripePaymentMethodRequest() {
        let request = OWSRequestFactory.subscriptionCreateStripePaymentMethodRequest(
            subscriberID: .init([255, 128])
        )

        XCTAssertEqual(request.url.path, "v1/subscription/_4A/create_payment_method")
        XCTAssertEqual(request.method, "POST")
    }

    func testSubscriptionCreatePaypalPaymentMethodRequest() {
        let request = OWSRequestFactory.subscriptionCreatePaypalPaymentMethodRequest(
            subscriberID: .init([255, 128]),
            returnURL: URL(string: "https://example.com/approved")!,
            cancelURL: URL(string: "https://example.com/canceled")!
        )

        XCTAssertEqual(request.url.path, "v1/subscription/_4A/create_payment_method/paypal")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Set(request.parameters.keys), Set([
            "returnUrl", "cancelUrl"
        ]))
        XCTAssertEqual(request.parameters["returnUrl"] as? String, "https://example.com/approved")
        XCTAssertEqual(request.parameters["cancelUrl"] as? String, "https://example.com/canceled")
    }

    func testSubscriptionSetSubscriptionLevelRequest() {
        let request = OWSRequestFactory.subscriptionSetSubscriptionLevelRequest(
            subscriberID: .init([255, 128]),
            level: 123,
            currency: "CHF",
            idempotencyKey: "t3DUeQcC0laEdwMJ"
        )

        XCTAssertEqual(request.url.path, "v1/subscription/_4A/level/123/CHF/t3DUeQcC0laEdwMJ")
        XCTAssertEqual(request.method, "PUT")
    }

    func testSubscriptionReceiptCredentialsRequest() {
        let request = OWSRequestFactory.subscriptionReceiptCredentialsRequest(
            subscriberID: .init([255, 128]),
            request: .init([128, 255])
        )

        XCTAssertEqual(request.url.path, "v1/subscription/_4A/receipt_credentials")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Set(request.parameters.keys), Set(["receiptCredentialRequest"]))
        XCTAssertEqual(request.parameters["receiptCredentialRequest"] as? String, "gP8=")
    }

    func testSubscriptionRedeemReceiptCredential() {
        let request = OWSRequestFactory.subscriptionRedeemReceiptCredential(
            receiptCredentialPresentation: .init([255, 128]),
            displayBadgesOnProfile: false,
        )

        XCTAssertEqual(request.url.path, "v1/donation/redeem-receipt")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Set(request.parameters.keys), Set([
            "receiptCredentialPresentation",
            "visible", "primary",
        ]))
        XCTAssertEqual(request.parameters["receiptCredentialPresentation"] as? String, "/4A=")
        XCTAssertEqual(request.parameters["visible"] as? Bool, false)
        XCTAssertEqual(request.parameters["primary"] as? Bool, false)
    }

    func testBoostReceiptCredentialsWithPaymentIntentId() {
        let request = OWSRequestFactory.boostReceiptCredentials(
            with: "abc_123",
            for: "STRIPE",
            request: .init([128, 255])
        )

        XCTAssertEqual(request.url.path, "v1/subscription/boost/receipt_credentials")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Set(request.parameters.keys), Set([
            "paymentIntentId",
            "receiptCredentialRequest",
            "processor",
        ]))
        XCTAssertEqual(request.parameters["paymentIntentId"] as? String, "abc_123")
        XCTAssertEqual(request.parameters["receiptCredentialRequest"] as? String, "gP8=")
        XCTAssertEqual(request.parameters["processor"] as? String, "STRIPE")
    }

    // MARK: - Spam

    func testReportSpamFromUuid() {
        let request = OWSRequestFactory.reportSpam(
            from: Aci.constantForTesting("37EBAFB5-91D6-4C63-BFF7-82F540856386"),
            withServerGuid: "abc 123",
            reportingToken: nil
        )

        XCTAssertEqual(
            request.url.relativeString,
            "v1/messages/report/37ebafb5-91d6-4c63-bff7-82f540856386/abc%20123"
        )
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.parameters as! [String: String], [:])
    }

    func testReportSpamFromUuidWithEmptyServerGuid() {
        // This will probably never happen, but if the server wants, this should be allowed.
        let request = OWSRequestFactory.reportSpam(
            from: Aci.constantForTesting("EB7B0432-BE7F-4A62-9859-4D7835D0D724"),
            withServerGuid: "",
            reportingToken: nil
        )

        XCTAssertEqual(
            request.url.relativeString,
            "v1/messages/report/eb7b0432-be7f-4a62-9859-4d7835d0d724/"
        )
    }

    func testReportSpamWithReportingToken() {
        let request = OWSRequestFactory.reportSpam(
            from: Aci.randomForTesting(),
            withServerGuid: "abc123",
            reportingToken: .init(data: .init([97, 98, 99]))
        )

        XCTAssertEqual(request.parameters as! [String: String], ["token": "YWJj"])
    }

    // MARK: - Usernames

    func testReserveUsername() {
        let request = OWSRequestFactory.reserveUsernameRequest(usernameHashes: ["boba", "fett"])

        XCTAssertEqual(request.url.path, "v1/accounts/username_hash/reserve")
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.parameters as! [String: [String]], ["usernameHashes": ["boba", "fett"]])
    }

    func testConfirmReservedUsername() {
        let request = OWSRequestFactory.confirmReservedUsernameRequest(
            reservedUsernameHash: "jango",
            reservedUsernameZKProof: "fett",
            encryptedUsernameForLink: "aa?".data(using: .utf8)! // Force a character that's special in base64Url
        )

        XCTAssertEqual(request.url.path, "v1/accounts/username_hash/confirm")
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.parameters as! [String: String], [
            "usernameHash": "jango",
            "zkProof": "fett",
            "encryptedUsername": "YWE_" // base64Url
        ])
    }

    func testDeleteExistingUsername() {
        let request = OWSRequestFactory.deleteExistingUsernameRequest()

        XCTAssertEqual(request.url.path, "v1/accounts/username_hash")
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.parameters as! [String: String], [:])
    }

    func testLookupAciForUsername() {
        let request = OWSRequestFactory.lookupAciUsernameRequest(usernameHashToLookup: "obi-wan")

        XCTAssertEqual(request.url.path, "v1/accounts/username_hash/obi-wan")
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.parameters as! [String: String], [:])
    }

    func testSetUsernameLink() {
        let request = OWSRequestFactory.setUsernameLinkRequest(
            encryptedUsername: "aa?".data(using: .utf8)!, // Force a character that's special in base64Url
            keepLinkHandle: true
        )

        XCTAssertEqual(request.url.path, "v1/accounts/username_link")
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.parameters["usernameLinkEncryptedValue"] as! String, "YWE_") // base64Url
        XCTAssertEqual(request.parameters["keepLinkHandle"] as! Bool, true)
    }

    func testLookupUsernameLink() {
        let handle = UUID()
        let request = OWSRequestFactory.lookupUsernameLinkRequest(handle: handle)

        XCTAssertEqual(request.url.path, "v1/accounts/username_link/\(handle)")
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.parameters as! [String: String], [:])
    }
}
