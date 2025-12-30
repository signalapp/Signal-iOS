//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing
@testable import SignalServiceKit

struct CurrencyFormatterTest {
    @Test
    func testStableFormats() {
        struct TestCase {
            let money: FiatMoney
            let locale: String
            let expected: String
        }

        let testCases: [TestCase] = [
            TestCase(money: FiatMoney(currencyCode: "USD", value: 1), locale: "en", expected: "$1"),
            TestCase(money: FiatMoney(currencyCode: "USD", value: 1.0), locale: "en", expected: "$1"),
            TestCase(money: FiatMoney(currencyCode: "USD", value: 1.00), locale: "en", expected: "$1"),
            TestCase(money: FiatMoney(currencyCode: "USD", value: 1.4), locale: "en", expected: "$1.40"),
            TestCase(money: FiatMoney(currencyCode: "USD", value: 1.40), locale: "en", expected: "$1.40"),

            TestCase(money: FiatMoney(currencyCode: "EUR", value: 1), locale: "en", expected: "€1"),
            TestCase(money: FiatMoney(currencyCode: "EUR", value: 1.01), locale: "en", expected: "€1.01"),

            TestCase(money: FiatMoney(currencyCode: "EUR", value: 1), locale: "fr", expected: "1 €"),
            TestCase(money: FiatMoney(currencyCode: "EUR", value: 1.01), locale: "fr", expected: "1,01 €"),
            TestCase(money: FiatMoney(currencyCode: "USD", value: 1.01), locale: "fr", expected: "1,01 $US"),

            TestCase(money: FiatMoney(currencyCode: "EUR", value: 1), locale: "nl", expected: "€ 1"),
            TestCase(money: FiatMoney(currencyCode: "EUR", value: 1.01), locale: "nl", expected: "€ 1,01"),
            TestCase(money: FiatMoney(currencyCode: "USD", value: 1.01), locale: "nl", expected: "US$ 1,01"),
        ]

        for testCase in testCases {
            let actual = CurrencyFormatter.format(
                money: testCase.money,
                locale: Locale(identifier: testCase.locale),
            )
            let expected = testCase.expected

            /// `CurrencyFormatter` uses system APIs to do the formatting, which
            /// like to return strings where whitespaces are fun Unicode
            /// characters rather than just a normal space. For equality
            /// comparison purposes, replace all those whitespaces with regular
            /// spaces.
            func sanitizeWhitespace(_ string: String) -> String {
                return String(string.unicodeScalars.map { c -> Character in
                    if CharacterSet.whitespaces.contains(c) {
                        return " "
                    } else {
                        return Character(c)
                    }
                })
            }

            #expect(
                sanitizeWhitespace(actual) == sanitizeWhitespace(expected),
                "\(testCase.money.debugDescription) in \(testCase.locale)",
            )
        }
    }
}
