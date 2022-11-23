//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

final class CreditOrDebitCardDonationViewControllerTest: XCTestCase {
    // MARK: - Formatting tests

    func testFormatCardNumber() {
        // We test this by "round-tripping".
        let testCases: [String] = [
            "",
            // American Express
            "37",
            "3782 ",
            "3782 822463 ",
            "3782 822463 10005",
            "3782 822463 100051234",
            // UnionPay
            "6200 ",
            "6200 0",
            "6200 0000 00",
            "6200 0000 0000 000",
            "6200 0000 0000 0000",
            "6200 0000 0000 0000000",
            // Other types
            "42",
            "4242 4242 ",
            "4242 4242 4242 4242",
            "4242 4242 4242 4242424"
        ]

        for testCase in testCases {
            let reformatted = CreditOrDebitCardDonationViewController.formatCardNumber(
                unformatted: testCase.asciiDigitsOnly
            )
            XCTAssertEqual(reformatted, testCase)
        }
    }

    func testFormatExpirationDate() {
        // We test this by "round-tripping".
        let testCases: [String] = [
            "",
            "0",
            "1",
            "2/",
            "9/",
            "01/",
            "02/",
            "10/",
            "11/",
            "12/",
            "1/3",
            "1/9",
            "2/3",
            "2/00",
            "2/34",
            "01/00",
            "01/23",
            "02/00",
            "02/34",
            "10/98",
            "12/34",
            // These cases aren't that important because they're invalid.
            // If these tests fail, that's probably fine.
            // We mostly want to ensure they don't crash.
            "1/345",
            "0/0",
            "0/000"
        ]

        for testCase in testCases {
            let reformatted = CreditOrDebitCardDonationViewController.formatExpirationDate(
                unformatted: testCase.asciiDigitsOnly
            )
            XCTAssertEqual(reformatted, testCase)
        }
    }

    // MARK: - Form state tests

    // Field validity is largely tested elsewhere
    // (for example, the specifics of CVV validation).

    private static func nextYearTwoDigits() -> String {
        let calendar = Calendar(identifier: .iso8601)
        let currentYear = calendar.component(.year, from: Date())
        let nextYear = currentYear + 1
        return String(String(nextYear).suffix(2))
    }

    private static func validRawExpiration() -> String {
        " 09 / \(nextYearTwoDigits()) "
    }

    private func assertFullyValid(
        _ formState: CreditOrDebitCardDonationViewController.FormState,
        _ message: String = "Form state not fully valid"
    ) {
        switch formState {
        case .fullyValid:
            break
        case .invalid, .potentiallyValid:
            XCTFail(message)
        }
    }

    private func fs(
        cardNumber: String = "4242424242424242",
        isCardNumberFieldFocused: Bool = false,
        expirationDate: String = CreditOrDebitCardDonationViewControllerTest.validRawExpiration(),
        cvv: String = "123"
    ) -> CreditOrDebitCardDonationViewController.FormState {
        CreditOrDebitCardDonationViewController.formState(
            cardNumber: cardNumber,
            isCardNumberFieldFocused: isCardNumberFieldFocused,
            expirationDate: expirationDate,
            cvv: cvv
        )
    }

    func testFormStateFullForm() {
        XCTAssertEqual(fs(cardNumber: "x", cvv: "x"), .invalid(invalidFields: [.cardNumber, .cvv]))
        XCTAssertEqual(fs(cvv: ""), .potentiallyValid)
        XCTAssertEqual(fs(), .fullyValid(creditOrDebitCard: .init(
            cardNumber: "4242424242424242",
            expirationMonth: 9,
            expirationTwoDigitYear: UInt8(Self.nextYearTwoDigits())!,
            cvv: "123"
        )))
    }

    func testFormStateCardNumber() {
        XCTAssertEqual(fs(cardNumber: "x"), .invalid(invalidFields: [.cardNumber]))
        XCTAssertEqual(fs(cardNumber: ""), .potentiallyValid)
        XCTAssertEqual(fs(cardNumber: "123"), .potentiallyValid)
        assertFullyValid(fs(cardNumber: " 4111 1111 1111 1111 "))
    }

    func testFormStateExpirationDate() {
        let year = Self.nextYearTwoDigits()

        let invalids: [String] = [
            "x",
            "13\(year)",
            "09\(year)0",
            "009\(year)",
            "13 / \(year)",
            "09 / \(year)0",
            "009 / \(year)",
            "09 / \(year)x",
            "09 / \(year) /",
            "00 / \(year)"
        ]
        for expirationDate in invalids {
            XCTAssertEqual(
                fs(expirationDate: expirationDate),
                .invalid(invalidFields: [.expirationDate]),
                expirationDate
            )
        }

        let potentiallyValids: [String] = [
            "",
            "0",
            "1",
            "09",
            "13",
            "09 /",
            "1 / 3",
            "0 / \(year)"
        ]
        for expirationDate in potentiallyValids {
            XCTAssertEqual(
                fs(expirationDate: expirationDate),
                .potentiallyValid,
                expirationDate
            )
        }

        let fullyValids: [String] = [
            "1\(year)",
            "9\(year)",
            "09\(year)",
            " 12 \(year) ",
            "1 / \(year)",
            "9 / \(year)",
            "09 / \(year)",
            "  12   /   \(year)  "
        ]
        for expirationDate in fullyValids {
            assertFullyValid(fs(expirationDate: expirationDate), expirationDate)
        }
    }

    func testFormStateCvv() {
        XCTAssertEqual(fs(cvv: "x"), .invalid(invalidFields: [.cvv]))
        XCTAssertEqual(fs(cvv: ""), .potentiallyValid)
        XCTAssertEqual(fs(cvv: "12"), .potentiallyValid)
        assertFullyValid(fs(cvv: " 123 "))

        let amexCard = "378282246310005"
        XCTAssertEqual(fs(cardNumber: amexCard, cvv: "123"), .potentiallyValid)
        assertFullyValid(fs(cardNumber: amexCard, cvv: " 1234 "))
    }
}
