//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalMessaging

class SubscriptionChargeFailureTest: XCTestCase {
    typealias ChargeFailure = Subscription.ChargeFailure

    func testNilInit() {
        let chargeFailure = ChargeFailure()
        XCTAssertNil(chargeFailure.code)
    }

    func testStringInit() {
        let chargeFailure = ChargeFailure(code: "foo bar")
        XCTAssertEqual(chargeFailure.code, "foo bar")
    }

    func testJsonInit() {
        let chargeFailure = ChargeFailure(jsonDictionary: ["code": "foo"])
        XCTAssertEqual(chargeFailure.code, "foo")

        let strangeInputs: [[String: Any]] = [[:], ["no code": "missing"], ["code": 123]]
        for jsonDictionary in strangeInputs {
            let chargeFailure = ChargeFailure(jsonDictionary: jsonDictionary)
            XCTAssertNil(chargeFailure.code)
        }
    }
}

class SubscriptionTest: XCTestCase {
    let subscriptionDict: [String: Any] = {
        let endOfCurrentPeriodRawValue: Double = 1618881836
        let billingCycleAnchorRawValue: Double = 1587345836
        return [
            "level": 123,
            "currency": "USD",
            "amount": 500,
            "endOfCurrentPeriod": endOfCurrentPeriodRawValue,
            "billingCycleAnchor": billingCycleAnchorRawValue,
            "active": true,
            "cancelAtPeriodEnd": false,
            "status": "active"
        ]
    }()

    func testJsonInit() throws {
        let subscription = try Subscription(subscriptionDict: subscriptionDict,
                                            chargeFailureDict: nil)

        XCTAssertEqual(subscription.level, 123)
        XCTAssertEqual(subscription.currency, "USD")
        XCTAssertEqual(subscription.amount, 500)
        XCTAssertEqual(subscription.endOfCurrentPeriod, 1618881836)
        XCTAssertEqual(subscription.billingCycleAnchor, 1587345836)
        XCTAssertTrue(subscription.active)
        XCTAssertFalse(subscription.cancelAtEndOfPeriod)
        XCTAssertEqual(subscription.status, .active)
        XCTAssertNil(subscription.chargeFailure)
    }

    func testJsonInitWithUnexpectedStatus() throws {
        var subscriptionDictWithUnexpectedStatus = subscriptionDict
        subscriptionDictWithUnexpectedStatus["status"] = "unexpected!!"

        let subscription = try Subscription(subscriptionDict: subscriptionDictWithUnexpectedStatus,
                                            chargeFailureDict: nil)

        XCTAssertEqual(subscription.status, .unknown)
        XCTAssertNil(subscription.chargeFailure)
    }

    func testChargeFailure() throws {
        let subscription = try Subscription(subscriptionDict: subscriptionDict,
                                            chargeFailureDict: ["code": "foo bar"])
        XCTAssertEqual(subscription.chargeFailure?.code, "foo bar")

        let strangeChargeFailures: [[String: Any]] = [[:], ["no code": "missing"], ["code": 123]]
        for chargeFailureDict in strangeChargeFailures {
            let subscription = try Subscription(subscriptionDict: subscriptionDict,
                                                chargeFailureDict: chargeFailureDict)
            XCTAssertNotNil(subscription.chargeFailure)
            XCTAssertNil(subscription.chargeFailure?.code)
        }
    }
}

class BadgeIdsTest: XCTestCase {
    func testSubscriptionContains() {
        let testCases: [(String, Bool)] = [
            ("R_LOW", true),
            ("R_MED", true),
            ("R_HIGH", true),
            ("BOOST", false),
            ("GIFT", false),
            ("OTHER", false),
            ("", false)
        ]
        for (badgeId, shouldMatch) in testCases {
            XCTAssertEqual(SubscriptionBadgeIds.contains(badgeId), shouldMatch, "\(badgeId)")
        }
    }

    func testBoostContains() {
        let testCases: [(String, Bool)] = [
            ("R_LOW", false),
            ("R_MED", false),
            ("R_HIGH", false),
            ("BOOST", true),
            ("GIFT", false),
            ("OTHER", false),
            ("", false)
        ]
        for (badgeId, shouldMatch) in testCases {
            XCTAssertEqual(BoostBadgeIds.contains(badgeId), shouldMatch, "\(badgeId)")
        }
    }
}

class SubscriptionManagerTest: XCTestCase {
    func testParseSuggestedBoostAmountsResponse() throws {
        let parse = { try SubscriptionManager.parseSuggestedBoostAmountsResponse(body: $0) }

        XCTAssertThrowsError(try parse(nil))
        XCTAssertThrowsError(try parse([]))
        XCTAssertThrowsError(try parse("USD"))

        XCTAssertEqual(try parse([:]), [:])
        XCTAssertEqual(
            try parse([
                "USD": [Double]([1, 2.3]),
                "JPY": [Double]([4, 5]),
                "xyz": [Double]([6, 7]),
                "": [Double]([8]),
                "BAD": Double(9),
                "SAD": "10",
                "RAD": [],
                "MAD": [Double]([1, 0, 2])
            ]),
            [
                "USD": .init(currencyCode: "USD", amounts: [1, 2.3]),
                "JPY": .init(currencyCode: "JPY", amounts: [4, 5]),
                "XYZ": .init(currencyCode: "XYZ", amounts: [6, 7])
            ]
        )
    }

    func testParseGiftBadgePricesResponse() throws {
        let parse = { try SubscriptionManager.parseGiftBadgePricesResponse(body: $0) }

        XCTAssertThrowsError(try parse(nil))
        XCTAssertThrowsError(try parse([]))
        XCTAssertThrowsError(try parse("USD"))

        XCTAssertEqual(try parse([:]), [:])
        XCTAssertEqual(
            try parse([
                "USD": Double(1.2),
                "JPY": Double(3),
                "xyz": Double(4),
                "": Double(8),
                "BAD": "9",
                "MAD": 0,
                "SAD": -1
            ]),
            [
                "USD": 1.2,
                "JPY": 3,
                "XYZ": 4
            ]
        )
    }
}
