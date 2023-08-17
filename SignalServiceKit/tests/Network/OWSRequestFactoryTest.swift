//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class OWSRequestFactoryTest: XCTestCase {
    private func getUdAccessKey() throws -> SMKUDAccessKey {
        let profileKey = Data(count: Int(kAES256_KeyByteLength))
        let result = try? SMKUDAccessKey(profileKey: profileKey)
        return try XCTUnwrap(result)
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

    // MARK: - Account

    func testEnable2FARequestWithPin() {
        let request = OWSRequestFactory.enable2FARequest(withPin: "90210")

        XCTAssertEqual(request.url?.path, "v1/accounts/pin")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.parameters as! [String: String], ["pin": "90210"])
        XCTAssertTrue(request.shouldHaveAuthorizationHeaders)
    }

    // MARK: - Devices

    func testDeviceProvisioning() {
        let request = OWSRequestFactory.provisionDevice(
            withMessageBody: .init([1, 2, 3]),
            ephemeralDeviceId: "foo bar"
        )

        XCTAssertEqual(request.url?.relativeString, "v1/provisioning/foo%20bar")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.parameters as! [String: String], ["body": "AQID"])
        XCTAssertTrue(request.shouldHaveAuthorizationHeaders)
    }

    // MARK: - Message requests

    func testSubmitMessageRequest() throws {
        let udAccessKey = try getUdAccessKey()

        let serviceId = Aci.randomForTesting()

        let request = OWSRequestFactory.submitMessageRequest(
            withServiceId: ServiceIdObjC.wrapValue(serviceId),
            messages: [],
            timestamp: 1234,
            udAccessKey: udAccessKey,
            isOnline: true,
            isUrgent: false,
            isStory: false
        )

        let url = try XCTUnwrap(request.url, "request.url")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(url.path, "v1/messages/\(serviceId.serviceIdString)")
        XCTAssertEqual(Set(request.parameters.keys), Set(["messages", "timestamp", "online", "urgent"]))
        XCTAssertEqual(request.parameters["messages"] as? NSArray, [])
        XCTAssertEqual(request.parameters["timestamp"] as? UInt, 1234)
        XCTAssertEqual(request.parameters["online"] as? Bool, true)
        XCTAssertEqual(request.parameters["urgent"] as? Bool, false)
        XCTAssertEqual(try queryItemsAsDictionary(url: url), ["story": "false"])
        XCTAssertEqual(request.allHTTPHeaderFields?["Unidentified-Access-Key"], udAccessKey.keyData.base64EncodedString())
    }

    func testSubmitMultiRecipientMessageRequest() throws {
        let ciphertext = try XCTUnwrap("hello".data(using: .utf8))
        let udAccessKey = try getUdAccessKey()

        let request = OWSRequestFactory.submitMultiRecipientMessageRequest(
            ciphertext: ciphertext,
            compositeUDAccessKey: udAccessKey,
            timestamp: 1234,
            isOnline: true,
            isUrgent: false,
            isStory: false
        )

        let url = try XCTUnwrap(request.url, "request.url")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(url.path, "v1/messages/multi_recipient")
        XCTAssertEqual(try queryItemsAsDictionary(url: url), ["ts": "1234", "online": "true", "urgent": "false", "story": "false"])
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/vnd.signal-messenger.mrm")
        XCTAssertEqual(request.allHTTPHeaderFields?["Unidentified-Access-Key"], udAccessKey.keyData.base64EncodedString())
        XCTAssertEqual(request.httpBody, ciphertext)
    }

    // MARK: - Donations

    func testDonationConfiguration() {
        let request = OWSRequestFactory.donationConfiguration()

        XCTAssertEqual(request.url?.path, "v1/subscription/configuration")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertFalse(request.shouldHaveAuthorizationHeaders)
    }

    func testBoostStripeCreatePaymentIntentWithAmount() {
        let request = OWSRequestFactory.boostStripeCreatePaymentIntent(
            integerMoneyValue: 123,
            inCurrencyCode: "CHF",
            level: 456
        )

        XCTAssertEqual(request.url?.path, "v1/subscription/boost/create")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(Set(request.parameters.keys), Set(["currency", "amount", "level"]))
        XCTAssertEqual(request.parameters["currency"] as? String, "chf")
        XCTAssertEqual(request.parameters["amount"] as? UInt, 123)
        XCTAssertEqual(request.parameters["level"] as? UInt64, 456)
        XCTAssertFalse(request.shouldHaveAuthorizationHeaders)
    }

    func testBoostPaypalCreatePaymentIntentWithAmount() {
        let request = OWSRequestFactory.boostPaypalCreatePayment(
            integerMoneyValue: 123,
            inCurrencyCode: "CHF",
            level: 456,
            returnUrl: URL(string: "https://example.com/approved")!,
            cancelUrl: URL(string: "https://example.com/canceled")!
        )

        XCTAssertEqual(request.url?.path, "v1/subscription/boost/paypal/create")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(Set(request.parameters.keys), Set([
            "currency", "amount", "level",
            "returnUrl", "cancelUrl"
        ]))
        XCTAssertEqual(request.parameters["currency"] as? String, "chf")
        XCTAssertEqual(request.parameters["amount"] as? UInt, 123)
        XCTAssertEqual(request.parameters["level"] as? UInt64, 456)
        XCTAssertEqual(request.parameters["returnUrl"] as? String, "https://example.com/approved")
        XCTAssertEqual(request.parameters["cancelUrl"] as? String, "https://example.com/canceled")
        XCTAssertFalse(request.shouldHaveAuthorizationHeaders)
    }

    func testSetSubscriberID() {
        let request = OWSRequestFactory.setSubscriberID(.init([255, 128]))

        XCTAssertEqual(request.url?.path, "v1/subscription/_4A")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertFalse(request.shouldHaveAuthorizationHeaders)
    }

    func testDeleteSubscriberID() {
        let request = OWSRequestFactory.deleteSubscriberID(.init([255, 128]))

        XCTAssertEqual(request.url?.path, "v1/subscription/_4A")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertFalse(request.shouldHaveAuthorizationHeaders)
    }

    func testSubscriptionSetDefaultPaymentMethod() {
        let request = OWSRequestFactory.subscriptionSetDefaultPaymentMethod(
            subscriberID: Data([255, 128]),
            processor: "STRIPE",
            paymentID: "xyz"
        )

        XCTAssertEqual(request.url?.path, "v1/subscription/_4A/default_payment_method/STRIPE/xyz")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertFalse(request.shouldHaveAuthorizationHeaders)
    }

    // MARK: - Spam

    func testReportSpamFromUuid() {
        let request = OWSRequestFactory.reportSpam(
            from: Aci.constantForTesting("37EBAFB5-91D6-4C63-BFF7-82F540856386"),
            withServerGuid: "abc 123",
            reportingToken: nil
        )

        XCTAssertEqual(
            request.url?.relativeString,
            "v1/messages/report/37ebafb5-91d6-4c63-bff7-82f540856386/abc%20123"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.parameters as! [String: String], [:])
        XCTAssertTrue(request.shouldHaveAuthorizationHeaders)
    }

    func testReportSpamFromUuidWithEmptyServerGuid() {
        // This will probably never happen, but if the server wants, this should be allowed.
        let request = OWSRequestFactory.reportSpam(
            from: Aci.constantForTesting("EB7B0432-BE7F-4A62-9859-4D7835D0D724"),
            withServerGuid: "",
            reportingToken: nil
        )

        XCTAssertEqual(
            request.url?.relativeString,
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

        XCTAssertEqual(request.url?.path, "v1/accounts/username_hash/reserve")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.parameters as! [String: [String]], ["usernameHashes": ["boba", "fett"]])
        XCTAssertTrue(request.shouldHaveAuthorizationHeaders)
    }

    func testConfirmReservedUsername() {
        let request = OWSRequestFactory.confirmReservedUsernameRequest(
            reservedUsernameHash: "jango",
            reservedUsernameZKProof: "fett",
            encryptedUsernameForLink: "aa?".data(using: .utf8)! // Force a character that's special in base64Url
        )

        XCTAssertEqual(request.url?.path, "v1/accounts/username_hash/confirm")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.parameters as! [String: String], [
            "usernameHash": "jango",
            "zkProof": "fett",
            "encryptedUsername": "YWE_" // base64Url
        ])
        XCTAssertTrue(request.shouldHaveAuthorizationHeaders)
    }

    func testDeleteExistingUsername() {
        let request = OWSRequestFactory.deleteExistingUsernameRequest()

        XCTAssertEqual(request.url?.path, "v1/accounts/username_hash")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.parameters as! [String: String], [:])
        XCTAssertTrue(request.shouldHaveAuthorizationHeaders)
    }

    func testLookupAciForUsername() {
        let request = OWSRequestFactory.lookupAciUsernameRequest(usernameHashToLookup: "obi-wan")

        XCTAssertEqual(request.url?.path, "v1/accounts/username_hash/obi-wan")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.parameters as! [String: String], [:])
        XCTAssertFalse(request.shouldHaveAuthorizationHeaders)
    }

    func testSetUsernameLink() {
        let request = OWSRequestFactory.setUsernameLinkRequest(
            encryptedUsername: "aa?".data(using: .utf8)! // Force a character that's special in base64Url
        )

        XCTAssertEqual(request.url?.path, "v1/accounts/username_link")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.parameters as! [String: String], [
            "usernameLinkEncryptedValue": "YWE_" // base64Url
        ])
        XCTAssertTrue(request.shouldHaveAuthorizationHeaders)
    }

    func testLookupUsernameLink() {
        let handle = UUID()
        let request = OWSRequestFactory.lookupUsernameLinkRequest(handle: handle)

        XCTAssertEqual(request.url?.path, "v1/accounts/username_link/\(handle)")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.parameters as! [String: String], [:])
        XCTAssertFalse(request.shouldHaveAuthorizationHeaders)
    }
}
