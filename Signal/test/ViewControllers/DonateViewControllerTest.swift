//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal
@testable import SignalMessaging

final class DonateViewControllerTest: SignalBaseTest {
    typealias State = DonateViewController.State

    // MARK: - One time fixtures

    private struct OneTimeFixtures {
        static let badge: ProfileBadge = try! ProfileBadge(jsonDictionary: [
            "id": "BOOST",
            "category": "donor",
            "name": "A Boost",
            "description": "A boost badge!",
            "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"]
        ])

        static let minimums: [Currency.Code: FiatMoney] = [
            "USD": 10.as("USD"),
            "AUD": 30.as("AUD")
        ]

        static let presets: [Currency.Code: DonationUtilities.Preset] = [
            "USD": .init(currencyCode: "USD", amounts: [10.as("USD"), 20.as("USD")]),
            "AUD": .init(currencyCode: "AUD", amounts: [30.as("AUD"), 40.as("AUD")])
        ]

        static func configWithDefaults(
            level: UInt = 12,
            badge: ProfileBadge = badge,
            minimums: [Currency.Code: FiatMoney] = minimums,
            presets: [Currency.Code: DonationUtilities.Preset] = presets
        ) -> State.OneTimeConfiguration {
            .init(
                level: level,
                badge: badge,
                presetAmounts: presets,
                minimumAmountsByCurrency: minimums,
                maximumAmountViaSepa: FiatMoney(currencyCode: "EUR", value: 10.000)
            )
        }
    }

    // MARK: - Monthly fixtures

    private struct MonthlyFixtures {
        static let badgeOne: ProfileBadge = try! .init(jsonDictionary: [
            "id": "test-badge-1",
            "category": "donor",
            "name": "Test Badge 1",
            "description": "First test badge",
            "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"]
        ])

        static let badgeTwo: ProfileBadge = try! .init(jsonDictionary: [
            "id": "test-badge-2",
            "category": "donor",
            "name": "Test Badge 2",
            "description": "Second test badge",
            "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"]
        ])

        static let amountsOne: [Currency.Code: FiatMoney] = [
            "USD": 1.as("USD"),
            "GBP": 2.as("GBP"),
            "EUR": 3.as("EUR")
        ]

        static let amountsTwo: [Currency.Code: FiatMoney] = [
            "USD": 4.as("USD"),
            "EUR": 5.as("EUR")
        ]

        static func levelOneWithDefaults(
            level: UInt = 1,
            name: String = "First Level",
            badge: ProfileBadge = badgeOne,
            amounts: [Currency.Code: FiatMoney] = amountsOne
        ) -> SubscriptionLevel {
            .init(
                level: level,
                name: name,
                badge: badge,
                amounts: amounts
            )
        }

        static func levelTwoWithDefaults(
            level: UInt = 2,
            name: String = "Second Level",
            badge: ProfileBadge = badgeTwo,
            amounts: [Currency.Code: FiatMoney] = amountsTwo
        ) -> SubscriptionLevel {
            .init(
                level: level,
                name: name,
                badge: badge,
                amounts: amounts
            )
        }

        static let subscriptionLevels: [SubscriptionLevel] = [
            levelOneWithDefaults(),
            levelTwoWithDefaults()
        ]

        static func configWithDefaults(
            subscriptionLevels: [SubscriptionLevel] = subscriptionLevels
        ) -> State.MonthlyConfiguration {
            .init(levels: subscriptionLevels)
        }
    }

    // MARK: - Payment methods fixtures

    private struct PaymentMethodsFixtures {
        static let supportedPaymentMethodsByCurrency: [Currency.Code: Set<DonationPaymentMethod>] = [
            "USD": [.applePay, .creditOrDebitCard, .paypal],
            "AUD": [.applePay, .creditOrDebitCard, .paypal],
            "EUR": [.applePay, .creditOrDebitCard]
        ]

        static func configWithDefaults(
            paymentMethods: [Currency.Code: Set<DonationPaymentMethod>] = supportedPaymentMethodsByCurrency
        ) -> State.PaymentMethodsConfiguration {
            .init(supportedPaymentMethodsByCurrency: paymentMethods)
        }
    }

    // MARK: - Subscription fixtures

    private static func subscription(
        at level: UInt,
        isPaymentProcessing: Bool = false,
        paymentMethod: String = "CARD"
    ) -> Subscription {
        try! .init(
            subscriptionDict: [
                "level": level,
                "currency": isPaymentProcessing ? "EUR" : "USD",
                "amount": 12,
                "endOfCurrentPeriod": TimeInterval(1234),
                "billingCycleAnchor": TimeInterval(5678),
                "active": true,
                "cancelAtPeriodEnd": false,
                "status": "active",
                "processor": "STRIPE",
                "paymentMethod": paymentMethod,
                "paymentProcessing": isPaymentProcessing
            ],
            chargeFailureDict: nil
        )
    }

    // MARK: -

    private static let defaultOneTimeConfig = OneTimeFixtures.configWithDefaults()
    private static let defaultMonthlyConfig = MonthlyFixtures.configWithDefaults()
    private static let defaultPaymentMethodsConfig = PaymentMethodsFixtures.configWithDefaults()

    private static var localNumber: String = "+17735550100"

    private var initializing: State { .init(donateMode: .oneTime) }

    private var loading: State { initializing.loading() }

    private var loadFailed: State { loading.loadFailed() }

    private var loadedWithoutSubscription: State {
        loading.loaded(
            oneTimeConfig: Self.defaultOneTimeConfig,
            monthlyConfig: Self.defaultMonthlyConfig,
            paymentMethodsConfig: Self.defaultPaymentMethodsConfig,
            currentMonthlySubscription: nil,
            subscriberID: nil,
            previousMonthlySubscriptionCurrencyCode: nil,
            previousMonthlySubscriptionPaymentMethod: nil,
            oneTimeBoostReceiptCredentialRequestError: nil,
            recurringSubscriptionReceiptCredentialRequestError: nil,
            pendingIDEALOneTimeDonation: nil,
            pendingIDEALSubscription: nil,
            locale: Locale(identifier: "en-US"),
            localNumber: Self.localNumber
        )
    }

    private var loadedWithSubscription: State {
        loading.loaded(
            oneTimeConfig: Self.defaultOneTimeConfig,
            monthlyConfig: Self.defaultMonthlyConfig,
            paymentMethodsConfig: Self.defaultPaymentMethodsConfig,
            currentMonthlySubscription: Self.subscription(at: 2),
            subscriberID: Data([1, 2, 3]),
            previousMonthlySubscriptionCurrencyCode: "USD",
            previousMonthlySubscriptionPaymentMethod: .applePay,
            oneTimeBoostReceiptCredentialRequestError: nil,
            recurringSubscriptionReceiptCredentialRequestError: nil,
            pendingIDEALOneTimeDonation: nil,
            pendingIDEALSubscription: nil,
            locale: Locale(identifier: "en-US"),
            localNumber: Self.localNumber
        )
    }

    func loadWithDefaults(
        oneTimeConfig: State.OneTimeConfiguration = defaultOneTimeConfig,
        monthlyConfig: State.MonthlyConfiguration = defaultMonthlyConfig,
        paymentMethodsConfig: State.PaymentMethodsConfiguration = defaultPaymentMethodsConfig,
        currentMonthlySubscription: Subscription? = subscription(at: 2),
        subscriberID: Data? = Data([1, 2, 3]),
        previousMonthlySubscriptionCurrencyCode: Currency.Code? = nil,
        locale: Locale = Locale(identifier: "en-US")
    ) -> State {
        loading.loaded(
            oneTimeConfig: oneTimeConfig,
            monthlyConfig: monthlyConfig,
            paymentMethodsConfig: paymentMethodsConfig,
            currentMonthlySubscription: currentMonthlySubscription,
            subscriberID: subscriberID,
            previousMonthlySubscriptionCurrencyCode: previousMonthlySubscriptionCurrencyCode,
            previousMonthlySubscriptionPaymentMethod: .applePay,
            oneTimeBoostReceiptCredentialRequestError: nil,
            recurringSubscriptionReceiptCredentialRequestError: nil,
            pendingIDEALOneTimeDonation: nil,
            pendingIDEALSubscription: nil,
            locale: locale,
            localNumber: Self.localNumber
        )
    }

    func loadWithPaymentsProcessing(
        recurringProcessingViaSubscription: Bool,
        recurringProcessingViaError: Bool
    ) -> State {
        let recurringError: ReceiptCredentialRequestError? = {
            guard recurringProcessingViaError else { return nil }

            return ReceiptCredentialRequestError(
                errorCode: .paymentStillProcessing,
                chargeFailureCodeIfPaymentFailed: nil,
                badge: MonthlyFixtures.badgeOne,
                amount: FiatMoney(currencyCode: "EUR", value: 5),
                paymentMethod: .sepa
            )
        }()

        return loading.loaded(
            oneTimeConfig: Self.defaultOneTimeConfig,
            monthlyConfig: Self.defaultMonthlyConfig,
            paymentMethodsConfig: Self.defaultPaymentMethodsConfig,
            currentMonthlySubscription: Self.subscription(
                at: 2,
                isPaymentProcessing: recurringProcessingViaSubscription,
                paymentMethod: "SEPA_DEBIT"
            ),
            subscriberID: Data([1, 2, 3]),
            previousMonthlySubscriptionCurrencyCode: nil,
            previousMonthlySubscriptionPaymentMethod: .applePay,
            oneTimeBoostReceiptCredentialRequestError: ReceiptCredentialRequestError(
                errorCode: .paymentStillProcessing,
                chargeFailureCodeIfPaymentFailed: nil,
                badge: OneTimeFixtures.badge,
                amount: FiatMoney(currencyCode: "EUR", value: 100),
                paymentMethod: .sepa
            ),
            recurringSubscriptionReceiptCredentialRequestError: recurringError,
            pendingIDEALOneTimeDonation: nil,
            pendingIDEALSubscription: nil,
            locale: Locale(identifier: "en-US"),
            localNumber: Self.localNumber
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
        XCTAssertEqual(onOneTime.selectedProfileBadge, Self.defaultOneTimeConfig.badge)

        let onMonthly = loadedWithoutSubscription.selectDonateMode(.monthly)
        let levels = Self.defaultMonthlyConfig.levels
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
        XCTAssertEqual(oneTime?.selectedPreset, Self.defaultOneTimeConfig.presetAmounts["USD"])
        XCTAssertEqual(oneTime?.selectedAmount, .nothingSelected(currencyCode: "USD"))
        XCTAssertEqual(oneTime?.profileBadge, Self.defaultOneTimeConfig.badge)
        XCTAssertEqual(monthly?.subscriptionLevels, Self.defaultMonthlyConfig.levels)
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
            Self.defaultMonthlyConfig.levels.first!
        )
    }

    func testLoadedSubscriptionLevelWithStillSupportedSubscription() {
        XCTAssertEqual(
            loadedWithSubscription.monthly?.selectedSubscriptionLevel,
            Self.defaultMonthlyConfig.levels[1]
        )
    }

    func testLoadedSubscriptionLevelWithSubscriptionTheServerNoLongerLists() {
        let state = loadWithDefaults(currentMonthlySubscription: Self.subscription(at: 99))
        XCTAssertEqual(
            state.monthly?.selectedSubscriptionLevel,
            Self.defaultMonthlyConfig.levels.first!
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

    func testSupportedPaymentMethods() {
        let oneTimeConfig = OneTimeFixtures.configWithDefaults(
            minimums: [
                "USD": 10.as("USD"),
                "EUR": 200.as("EUR")
            ],
            presets: [
                "USD": .init(currencyCode: "USD", amounts: [10.as("USD"), 20.as("USD")]),
                "EUR": .init(currencyCode: "EUR", amounts: [200.as("EUR"), 400.as("EUR")])
            ]
        )

        let monthlyConfig = MonthlyFixtures.configWithDefaults(
            subscriptionLevels: [
                MonthlyFixtures.levelOneWithDefaults(
                    amounts: [
                        "USD": 15.as("USD"),
                        "EUR": 250.as("EUR")
                    ]
                )
            ]
        )

        let paymentMethodsConfig = PaymentMethodsFixtures.configWithDefaults(
            paymentMethods: [
                "USD": [.paypal, .applePay],
                "EUR": []
            ]
        )

        var state = loadWithDefaults(
            oneTimeConfig: oneTimeConfig,
            monthlyConfig: monthlyConfig,
            paymentMethodsConfig: paymentMethodsConfig
        )

        // If a currency has no payment methods, it should not be supported.

        state = state.selectDonateMode(.oneTime)
        XCTAssertEqual(
            state.supportedCurrencyCodes,
            ["USD"],
            "Only USD should be supported for one-time, as only it has any payment methods!"
        )

        state = state.selectDonateMode(.monthly)
        XCTAssertEqual(
            state.supportedCurrencyCodes,
            ["USD"],
            "Only USD should be supported for monthly, as only it has any payment methods!"
        )

        // If the selected currency has supported payment methods, payment
        // requests should return them - unless they are disabled globally
        // for that type of payment.

        state = state.selectCurrencyCode("USD")
        state = state.selectOneTimeAmount(.choseCustomAmount(amount: 123.as("USD")))
        state = state.selectSubscriptionLevel(monthlyConfig.levels.first!)

        let oneTimePaymentRequest = state.oneTime!.paymentRequest
        switch oneTimePaymentRequest {
        case let .canContinue(amount, supportedPaymentMethods):
            XCTAssertEqual(amount, 123.as("USD"))
            XCTAssertEqual(supportedPaymentMethods, [.paypal, .applePay])
        default:
            XCTFail("Unexpectedly invalid one-time payment request! \(oneTimePaymentRequest)")
        }

        let monthlyPaymentRequest = state.monthly!.paymentRequest!
        XCTAssertEqual(monthlyPaymentRequest.amount, 15.as("USD"))
        XCTAssertEqual(monthlyPaymentRequest.supportedPaymentMethods, [.paypal, .applePay])
    }

    func testPaymentProcessing() {
        let oneTimeProcessing = loadWithPaymentsProcessing(
            recurringProcessingViaSubscription: false,
            recurringProcessingViaError: false
        )

        switch oneTimeProcessing.oneTime!.paymentRequest {
        case let .alreadyHasPaymentProcessing(paymentMethod):
            XCTAssertEqual(paymentMethod, .sepa)
        case .noAmountSelected, .amountIsTooSmall, .canContinue, .awaitingIDEALAuthorization:
            XCTFail("Should be payment processing!")
        }

        /// Simulates a payment that has not yet processed.
        let recurringProcessingViaSubscription = loadWithPaymentsProcessing(
            recurringProcessingViaSubscription: true,
            recurringProcessingViaError: true
        )

        XCTAssertEqual(
            recurringProcessingViaSubscription.monthly!.paymentProcessingWithPaymentMethod,
            .sepa
        )

        /// Simulates a payment that has processed, but our client hasn't yet
        /// redeemed a badge for it.
        let recurringProcessingOnlyViaError = loadWithPaymentsProcessing(
            recurringProcessingViaSubscription: false,
            recurringProcessingViaError: true
        )

        XCTAssertEqual(
            recurringProcessingOnlyViaError.monthly!.paymentProcessingWithPaymentMethod,
            .sepa
        )
    }
}

fileprivate extension Int {
    func `as`(_ currencyCode: Currency.Code) -> FiatMoney {
        FiatMoney(currencyCode: currencyCode, value: Decimal(self))
    }
}
