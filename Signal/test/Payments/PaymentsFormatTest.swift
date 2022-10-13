//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit
@testable import SignalMessaging
@testable import Signal
@testable import MobileCoin

class PaymentsFormatTest: SignalBaseTest {

    override func setUp() {
        super.setUp()

        SSKEnvironment.shared.paymentsHelperRef = PaymentsHelperImpl()
        SUIEnvironment.shared.paymentsRef = PaymentsImpl()
    }

    func test_formatAsFiatCurrency() {
        let paymentAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: 12345 * PaymentsConstants.picoMobPerMob)
        let conversionSingle = CurrencyConversionInfo(currencyCode: "ZQ",
                                                      name: "Fake currency",
                                                      conversionRate: 1,
                                                      conversionDate: Date())
        let conversionDouble = CurrencyConversionInfo(currencyCode: "ZQ",
                                                      name: "Fake currency",
                                                      conversionRate: 2,
                                                      conversionDate: Date())

        do {
            // USA
            let locale: Locale = Locale(identifier: "en_US")
            XCTAssertEqual("12,345.00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                           currencyConversionInfo: conversionSingle,
                                                                           locale: locale)!)
            XCTAssertEqual("24,690.00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                           currencyConversionInfo: conversionDouble,
                                                                           locale: locale)!)
        }

        do {
            // UK
            //
            // From: https://en.wikipedia.org/wiki/Decimal_separator#Hindu.E2.80.93Arabic_numeral_system
            // 1,234,567.89 United Kingdom
            //
            // NOTE: The United Kingdom supports multiple ways of formatting currency.
            let locale: Locale = Locale(identifier: "en_GB")
            XCTAssertEqual("12,345.00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                            currencyConversionInfo: conversionSingle,
                                                                            locale: locale)!)
            XCTAssertEqual("24,690.00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                            currencyConversionInfo: conversionDouble,
                                                                            locale: locale)!)
        }

        do {
            // France
            //
            // From: https://en.wikipedia.org/wiki/Decimal_separator#Hindu.E2.80.93Arabic_numeral_system
            // 1234567,89    SI style (French version), France
            //
            // NOTE: NumberFormatter uses a 'NARROW NO-BREAK SPACE' (U+202F) as a grouping separator.
            // https://www.fileformat.info/info/unicode/char/202f/index.htm
            let locale: Locale = Locale(identifier: "fr_FR")
            XCTAssertEqual("12 345,00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                              currencyConversionInfo: conversionSingle,
                                                                              locale: locale)!)
            XCTAssertEqual("24 690,00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                              currencyConversionInfo: conversionDouble,
                                                                              locale: locale)!)
        }

        do {
            // Switzerland (French)
            //
            // From: https://en.wikipedia.org/wiki/Decimal_separator#Hindu.E2.80.93Arabic_numeral_system
            //        1'234'567.89    Switzerland (computing), Liechtenstein.
            //        1'234'567,89    Switzerland (handwriting), Italy (handwriting).
            //
            // NOTE: Swiss formatting depends on the language used.
            // NOTE: NumberFormatter uses a 'NARROW NO-BREAK SPACE' (U+202F) as a grouping separator.
            // https://www.fileformat.info/info/unicode/char/202f/index.htm
            let locale: Locale = Locale(identifier: "fr_CH")
            XCTAssertEqual("12 345,00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                              currencyConversionInfo: conversionSingle,
                                                                              locale: locale)!)
            XCTAssertEqual("24 690,00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                              currencyConversionInfo: conversionDouble,
                                                                              locale: locale)!)
        }

        do {
            // Switzerland (German)
            //
            // From: https://en.wikipedia.org/wiki/Decimal_separator#Hindu.E2.80.93Arabic_numeral_system
            //        1'234'567.89    Switzerland (computing), Liechtenstein.
            //        1'234'567,89    Switzerland (handwriting), Italy (handwriting).
            //
            // NOTE: Swiss formatting depends on the language used.
            let locale: Locale = Locale(identifier: "de_CH")
            XCTAssertEqual("12’345.00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                              currencyConversionInfo: conversionSingle,
                                                                              locale: locale)!)
            XCTAssertEqual("24’690.00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                              currencyConversionInfo: conversionDouble,
                                                                              locale: locale)!)
        }

        do {
            // Switzerland (Swiss German)
            //
            // From: https://en.wikipedia.org/wiki/Decimal_separator#Hindu.E2.80.93Arabic_numeral_system
            //        1'234'567.89    Switzerland (computing), Liechtenstein.
            //        1'234'567,89    Switzerland (handwriting), Italy (handwriting).
            //
            // NOTE: Swiss formatting depends on the language used.
            let locale: Locale = Locale(identifier: "gsw_CH")
            XCTAssertEqual("12’345.00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                              currencyConversionInfo: conversionSingle,
                                                                              locale: locale)!)
            XCTAssertEqual("24’690.00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                              currencyConversionInfo: conversionDouble,
                                                                              locale: locale)!)
        }

        do {
            // Germany
            //
            // From: https://en.wikipedia.org/wiki/Decimal_separator#Hindu.E2.80.93Arabic_numeral_system
            //        1.234.567,89    Germany
            let locale: Locale = Locale(identifier: "de_DE")
            XCTAssertEqual("12.345,00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                              currencyConversionInfo: conversionSingle,
                                                                              locale: locale)!)
            XCTAssertEqual("24.690,00", PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentAmount,
                                                                              currencyConversionInfo: conversionDouble,
                                                                              locale: locale)!)
        }
    }
}
