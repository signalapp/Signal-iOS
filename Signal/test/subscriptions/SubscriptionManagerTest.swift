//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest

class SubscriptionTest: XCTestCase {
    let subscriptionJsonDictionary: [String: Any] = {
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
        let subscription = try Subscription(jsonDictionary: subscriptionJsonDictionary,
                                            hasChargeFailure: false)

        XCTAssertEqual(subscription.level, 123)
        XCTAssertEqual(subscription.currency, "USD")
        XCTAssertEqual(subscription.amount, 500)
        XCTAssertEqual(subscription.endOfCurrentPeriod, 1618881836)
        XCTAssertEqual(subscription.billingCycleAnchor, 1587345836)
        XCTAssertTrue(subscription.active)
        XCTAssertFalse(subscription.cancelAtEndOfPeriod)
        XCTAssertEqual(subscription.status, .active)
        XCTAssertFalse(subscription.hasChargeFailure)
    }

    func testJsonInitWithUnexpectedStatus() throws {
        var jsonDictionaryWithUnexpectedStatus = subscriptionJsonDictionary
        jsonDictionaryWithUnexpectedStatus["status"] = "unexpected!!"

        let subscription = try Subscription(jsonDictionary: jsonDictionaryWithUnexpectedStatus,
                                            hasChargeFailure: false)

        XCTAssertEqual(subscription.status, .unknown)
        XCTAssertFalse(subscription.hasChargeFailure)
    }

    func testChargeFailure() throws {
        let subscription = try Subscription(jsonDictionary: subscriptionJsonDictionary,
                                            hasChargeFailure: true)
        XCTAssertTrue(subscription.hasChargeFailure)
    }
}
