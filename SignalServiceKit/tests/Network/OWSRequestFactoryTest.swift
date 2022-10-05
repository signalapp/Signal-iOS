//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class OWSRequestFactoryTest: SSKBaseTestSwift {
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

    func testSubmitMessageRequest() throws {
        let udAccessKey = try getUdAccessKey()

        let recipientUuid = UUID()

        let request = OWSRequestFactory.submitMessageRequest(
            with: SignalServiceAddress(uuid: recipientUuid),
            messages: [],
            timestamp: 1234,
            udAccessKey: udAccessKey,
            isOnline: true,
            isUrgent: false,
            isStory: false
        )

        let url = try XCTUnwrap(request.url, "request.url")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(url.path, "v1/messages/\(recipientUuid.uuidString)")
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

    func testBoostCreatePaymentIntentWithAmount() {
        let request = OWSRequestFactory.boostCreatePaymentIntent(withAmount: 123, inCurrencyCode: "CHF", level: 456)

        XCTAssertEqual(request.url?.path, "v1/subscription/boost/create")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(Set(request.parameters.keys), Set(["currency", "amount", "level"]))
        XCTAssertEqual(request.parameters["currency"] as? String, "chf")
        XCTAssertEqual(request.parameters["amount"] as? UInt, 123)
        XCTAssertEqual(request.parameters["level"] as? UInt64, 456)
        XCTAssertFalse(request.shouldHaveAuthorizationHeaders)
    }

    func testGiftBadgePricesRequest() throws {
        let request = OWSRequestFactory.giftBadgePricesRequest()

        XCTAssertEqual(request.url?.path, "v1/subscription/boost/amounts/gift")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertTrue(request.parameters.isEmpty)
    }
}
