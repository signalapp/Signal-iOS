//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal
@testable import SignalMessaging

final class DonateViewControllerTest: XCTestCase {
    typealias State = DonateViewController.State

    private static var oneTimePresets: [Currency.Code: DonationUtilities.Preset] = [
        "USD": .init(currencyCode: "USD", amounts: [10.as("USD"), 20.as("USD")]),
        "AUD": .init(currencyCode: "AUD", amounts: [30.as("AUD"), 40.as("AUD")])
    ]

    private static var oneTimeBadge: ProfileBadge {
        try! ProfileBadge(jsonDictionary: [
            "id": "BOOST",
            "category": "donor",
            "name": "A Boost",
            "description": "A boost badge!",
            "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"]
        ])
    }

    private static var monthlySubscriptionLevels: [SubscriptionLevel] {
        [
            try! .init(level: 1, jsonDictionary: [
                "name": "First Level",
                "badge": [
                    "id": "test-badge-1",
                    "category": "donor",
                    "name": "Test Badge 1",
                    "description": "First test badge",
                    "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"]
                ],
                "currencies": ["USD": Double(1), "GBP": Double(2), "EUR": Double(3)]
            ]),
            try! .init(level: 2, jsonDictionary: [
                "name": "Second Level",
                "badge": [
                    "id": "test-badge-2",
                    "category": "donor",
                    "name": "Test Badge 2",
                    "description": "Second test badge",
                    "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"]
                ],
                "currencies": ["USD": Double(4), "EUR": Double(5)]
            ])
        ]
    }

    private static func subscription(at level: UInt) -> Subscription {
        try! .init(
            subscriptionDict: [
                "level": level,
                "currency": "USD",
                "amount": 12,
                "endOfCurrentPeriod": TimeInterval(1234),
                "billingCycleAnchor": TimeInterval(5678),
                "active": true,
                "cancelAtPeriodEnd": false,
                "status": "active"
            ],
            chargeFailureDict: nil
        )
    }

    private var initializing: State { .init(donateMode: .oneTime) }

    private var loading: State { initializing.loading() }

    private var loadFailed: State { loading.loadFailed() }

    private var loadedWithoutSubscription: State {
        loading.loaded(
            oneTimePresets: Self.oneTimePresets,
            oneTimeBadge: Self.oneTimeBadge,
            monthlySubscriptionLevels: Self.monthlySubscriptionLevels,
            currentMonthlySubscription: nil,
            subscriberID: nil,
            lastReceiptRedemptionFailure: .none,
            previousMonthlySubscriptionCurrencyCode: nil,
            locale: Locale(identifier: "en-US")
        )
    }

    private var loadedWithSubscription: State {
        loading.loaded(
            oneTimePresets: Self.oneTimePresets,
            oneTimeBadge: Self.oneTimeBadge,
            monthlySubscriptionLevels: Self.monthlySubscriptionLevels,
            currentMonthlySubscription: Self.subscription(at: 2),
            subscriberID: Data([1, 2, 3]),
            lastReceiptRedemptionFailure: .none,
            previousMonthlySubscriptionCurrencyCode: "USD",
            locale: Locale(identifier: "en-US")
        )
    }

    func loadWithDefaults(
        oneTimePresets: [Currency.Code: DonationUtilities.Preset] = oneTimePresets,
        oneTimeBadge: ProfileBadge? = oneTimeBadge,
        monthlySubscriptionLevels: [SubscriptionLevel] = monthlySubscriptionLevels,
        currentMonthlySubscription: Subscription? = subscription(at: 2),
        subscriberID: Data? = Data([1, 2, 3]),
        previousMonthlySubscriptionCurrencyCode: Currency.Code? = nil,
        locale: Locale = Locale(identifier: "en-US")
    ) -> State {
        loading.loaded(
            oneTimePresets: oneTimePresets,
            oneTimeBadge: oneTimeBadge,
            monthlySubscriptionLevels: monthlySubscriptionLevels,
            currentMonthlySubscription: currentMonthlySubscription,
            subscriberID: subscriberID,
            lastReceiptRedemptionFailure: .none,
            previousMonthlySubscriptionCurrencyCode: previousMonthlySubscriptionCurrencyCode,
            locale: locale
        )
    }

    // MARK: - Initialization

    func testInitialization() {
        XCTAssertEqual(initializing.loadState, .initializing)
    }

    // MARK: - Top-level getters

    func testOneTime() {
        XCTAssertNil(initializing.oneTime)
        XCTAssertNil(loading.oneTime)
        XCTAssertNil(loadFailed.oneTime)
        XCTAssertNotNil(loadedWithoutSubscription.oneTime)
    }

    func testMonthly() {
        XCTAssertNil(initializing.monthly)
        XCTAssertNil(loading.monthly)
        XCTAssertNil(loadFailed.monthly)
        XCTAssertNotNil(loadedWithoutSubscription.monthly)
    }

    func testSelectedCurrencyCode() {
        XCTAssertNil(initializing.selectedCurrencyCode)
        XCTAssertEqual(loadedWithoutSubscription.selectedCurrencyCode, "USD")
    }

    func testSupportedCurrencyCodes() {
        XCTAssertTrue(initializing.supportedCurrencyCodes.isEmpty)

        let onOneTime = loadedWithoutSubscription.selectDonateMode(.oneTime)
        XCTAssertEqual(onOneTime.supportedCurrencyCodes, Set<Currency.Code>(["USD", "AUD"]))

        let onMonthly = loadedWithoutSubscription.selectDonateMode(.monthly)
        XCTAssertEqual(onMonthly.supportedCurrencyCodes, Set<Currency.Code>(["USD", "EUR"]))
    }

    func testSelectedProfileBadge() {
        XCTAssertNil(initializing.selectedCurrencyCode)

        let onOneTime = loadedWithoutSubscription.selectDonateMode(.oneTime)
        XCTAssertEqual(onOneTime.selectedProfileBadge, Self.oneTimeBadge)

        let onMonthly = loadedWithoutSubscription.selectDonateMode(.monthly)
        let levels = Self.monthlySubscriptionLevels
        let selectedSecond = onMonthly.selectSubscriptionLevel(levels.last!)
        XCTAssertEqual(onMonthly.selectedProfileBadge, levels.first!.badge)
        XCTAssertEqual(selectedSecond.selectedProfileBadge, levels.last!.badge)
    }

    func testLoadedDonateMode() {
        XCTAssertNil(initializing.loadedDonateMode)
        XCTAssertNil(loadFailed.loadedDonateMode)

        let onOneTime = loadedWithoutSubscription.selectDonateMode(.oneTime)
        XCTAssertEqual(onOneTime.loadedDonateMode, .oneTime)

        let onMonthly = loadedWithoutSubscription.selectDonateMode(.monthly)
        XCTAssertEqual(onMonthly.loadedDonateMode, .monthly)
    }

    // MARK: - Top-level state changes

    func testLoading() {
        XCTAssertEqual(loading.loadState, .loading)
    }

    func testLoadFailed() {
        XCTAssertEqual(loadFailed.loadState, .loadFailed)
    }

    func testLoadedBoringSettingOfProperties() {
        let oneTime = loadedWithSubscription.oneTime
        let monthly = loadedWithSubscription.monthly
        XCTAssertEqual(oneTime?.selectedPreset, Self.oneTimePresets["USD"])
        XCTAssertEqual(oneTime?.selectedAmount, .nothingSelected(currencyCode: "USD"))
        XCTAssertEqual(oneTime?.profileBadge, Self.oneTimeBadge)
        XCTAssertEqual(monthly?.subscriptionLevels, Self.monthlySubscriptionLevels)
        XCTAssertEqual(monthly?.currentSubscription, Self.subscription(at: 2))
        XCTAssertEqual(monthly?.subscriberID, Data([1, 2, 3]))
    }

    func testLoadedDefaultOneTimeCurrency() {
        let american = loadWithDefaults(locale: Locale(identifier: "en-US"))
        let australian = loadWithDefaults(locale: Locale(identifier: "en-AU"))
        let spanish = loadWithDefaults(locale: Locale(identifier: "es-ES"))
        let korean = loadWithDefaults(locale: Locale(identifier: "kr-KR"))
        XCTAssertEqual(american.oneTime?.selectedCurrencyCode, "USD")
        XCTAssertEqual(australian.oneTime?.selectedCurrencyCode, "AUD")
        XCTAssertEqual(spanish.oneTime?.selectedCurrencyCode, "USD")
        XCTAssertEqual(korean.oneTime?.selectedCurrencyCode, "USD")
    }

    func testLoadedDefaultMonthlyCurrency() {
        let withPreviousCurrency = loadWithDefaults(previousMonthlySubscriptionCurrencyCode: "EUR")
        XCTAssertEqual(withPreviousCurrency.monthly?.selectedCurrencyCode, "EUR")

        let withSubscription = loadWithDefaults(locale: Locale(identifier: "kr-KR"))
        XCTAssertEqual(withSubscription.monthly?.selectedCurrencyCode, "USD")

        let withSupportedLocaleCurrency = loadWithDefaults(
            currentMonthlySubscription: nil,
            locale: Locale(identifier: "es-ES")
        )
        XCTAssertEqual(withSupportedLocaleCurrency.monthly?.selectedCurrencyCode, "EUR")

        let withUnsupportedLocaleCurrency = loadWithDefaults(
            currentMonthlySubscription: nil,
            locale: Locale(identifier: "kr-KR")
        )
        XCTAssertEqual(withUnsupportedLocaleCurrency.monthly?.selectedCurrencyCode, "USD")
    }

    func testLoadedSubscriptionLevelWithNoSubscription() {
        XCTAssertEqual(
            loadedWithoutSubscription.monthly?.selectedSubscriptionLevel,
            Self.monthlySubscriptionLevels.first!
        )
    }

    func testLoadedSubscriptionLevelWithStillSupportedSubscription() {
        XCTAssertEqual(
            loadedWithSubscription.monthly?.selectedSubscriptionLevel,
            Self.monthlySubscriptionLevels[1]
        )
    }

    func testLoadedSubscriptionLevelWithSubscriptionTheServerNoLongerLists() {
        let state = loadWithDefaults(currentMonthlySubscription: Self.subscription(at: 99))
        XCTAssertEqual(
            state.monthly?.selectedSubscriptionLevel,
            Self.monthlySubscriptionLevels.first!
        )
    }

    func testSelectCurrencyCode() {
        let selectedUsd = loadedWithoutSubscription.selectCurrencyCode("USD")
        XCTAssertEqual(selectedUsd.selectDonateMode(.oneTime).selectedCurrencyCode, "USD")
        XCTAssertEqual(selectedUsd.selectDonateMode(.monthly).selectedCurrencyCode, "USD")

        let triedToSelectEur = loadedWithoutSubscription.selectCurrencyCode("EUR")
        XCTAssertEqual(triedToSelectEur.selectDonateMode(.oneTime).selectedCurrencyCode, "USD")
        XCTAssertEqual(triedToSelectEur.selectDonateMode(.monthly).selectedCurrencyCode, "EUR")

        let triedToSelectAud = loadedWithoutSubscription.selectCurrencyCode("AUD")
        XCTAssertEqual(triedToSelectAud.selectDonateMode(.oneTime).selectedCurrencyCode, "AUD")
        XCTAssertEqual(triedToSelectAud.selectDonateMode(.monthly).selectedCurrencyCode, "USD")
    }
}

fileprivate extension Int {
    func `as`(_ currencyCode: Currency.Code) -> FiatMoney {
        FiatMoney(currencyCode: currencyCode, value: Decimal(self))
    }
}
