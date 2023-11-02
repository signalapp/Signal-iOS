//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

final class PaymentDetailsValidityTest: XCTestCase {
    typealias CardType = CreditAndDebitCards.CardType
    typealias Validity = CreditAndDebitCards.Validity

    func testCardType() {
        func cardType(_ number: String) -> CardType {
            CreditAndDebitCards.cardType(ofNumber: number)
        }

        let amex: [String] = ["34", "37", "343452000000306", "371449635398431", "378282246310005"]
        for number in amex {
            XCTAssertEqual(cardType(number), .americanExpress)
        }

        let unionpay: [String] = ["62", "81", "6200000000000004"]
        for number in unionpay {
            XCTAssertEqual(cardType(number), .unionPay)
        }

        let other: [String] = [
            "",
            "X",
            "4",
            "4111111111111111",
            "4242424242424242",
            "5555555555554444",
            "2223003122003222",
            "6011111111111117",
            "3056930009020004",
            "3566002020360505"
        ]
        for number in other {
            XCTAssertEqual(cardType(number), .other)
        }
    }

    func testCardTypeCvvCount() {
        XCTAssertEqual(CardType.americanExpress.cvvCount, 4)
        XCTAssertEqual(CardType.unionPay.cvvCount, 3)
        XCTAssertEqual(CardType.other.cvvCount, 3)
    }

    func testValidityOfNumber() {
        func n(_ number: String, focused: Bool = false) -> Validity {
            CreditAndDebitCards.validity(ofNumber: number, isNumberFieldFocused: focused)
        }

        // Typing
        XCTAssertEqual(n(""), .potentiallyValid)
        XCTAssertEqual(n("4"), .potentiallyValid)
        XCTAssertEqual(n("42"), .potentiallyValid)
        XCTAssertEqual(n("42424242424"), .potentiallyValid)

        // Fully valid
        XCTAssertEqual(n("424242424242"), .fullyValid)
        XCTAssertEqual(n("424242424242424242"), .fullyValid)

        // Luhn-invalid cards
        XCTAssertEqual(n("4242424242424"), .invalid(()))
        XCTAssertEqual(n("4242424242424", focused: true), .potentiallyValid)

        // UnionPay cards
        XCTAssertEqual(n("6200000000000004"), .fullyValid)
        XCTAssertEqual(n("6200000000000005"), .fullyValid)

        // Too long
        XCTAssertEqual(n("42424242424242424242"), .invalid(()))

        // Invalid characters
        XCTAssertEqual(n("X"), .invalid(()))
        XCTAssertEqual(n("42X"), .invalid(()))
        XCTAssertEqual(n("424242424242X"), .invalid(()))
        XCTAssertEqual(n("4242 4242 4242 4242"), .invalid(()))
    }

    func testValidityOfExpirationDate() {
        func d(_ month: String, _ year: String, currentYear: Int = 2020) -> Validity {
            CreditAndDebitCards.validity(
                ofExpirationMonth: month,
                andYear: year,
                currentMonth: 3,
                currentYear: currentYear
            )
        }

        XCTAssertEqual(d("", ""), .potentiallyValid)
        XCTAssertEqual(d("0", ""), .potentiallyValid)
        XCTAssertEqual(d("1", ""), .potentiallyValid)
        XCTAssertEqual(d("9", ""), .potentiallyValid)
        XCTAssertEqual(d("01", ""), .potentiallyValid)
        XCTAssertEqual(d("09", ""), .potentiallyValid)
        XCTAssertEqual(d("12", ""), .potentiallyValid)
        XCTAssertEqual(d("", "0"), .potentiallyValid)
        XCTAssertEqual(d("", "1"), .potentiallyValid)
        XCTAssertEqual(d("", "9"), .potentiallyValid)
        XCTAssertEqual(d("", "00"), .potentiallyValid)
        XCTAssertEqual(d("", "01"), .potentiallyValid)
        XCTAssertEqual(d("", "99"), .potentiallyValid)

        XCTAssertEqual(d("3", "20"), .fullyValid)
        XCTAssertEqual(d("03", "20"), .fullyValid)
        XCTAssertEqual(d("4", "20"), .fullyValid)
        XCTAssertEqual(d("12", "20"), .fullyValid)
        XCTAssertEqual(d("3", "21"), .fullyValid)
        XCTAssertEqual(d("3", "40"), .fullyValid)

        XCTAssertEqual(d("2", "20"), .invalid(()))
        XCTAssertEqual(d("3", "41"), .invalid(()))
        XCTAssertEqual(d("3", "41", currentYear: 2021), .fullyValid)
        XCTAssertEqual(d("01", "99", currentYear: 2098), .fullyValid)
        XCTAssertEqual(d("3", "00", currentYear: 2099), .fullyValid)
        XCTAssertEqual(d("4", "00", currentYear: 2099), .fullyValid)
        XCTAssertEqual(d("3", "19", currentYear: 2099), .fullyValid)
        XCTAssertEqual(d("12", "19", currentYear: 2099), .fullyValid)

        XCTAssertEqual(d("00", "20"), .invalid(()))
        XCTAssertEqual(d("X", ""), .invalid(()))
        XCTAssertEqual(d("1X", ""), .invalid(()))
        XCTAssertEqual(d("123", ""), .invalid(()))
        XCTAssertEqual(d("", "X"), .invalid(()))
        XCTAssertEqual(d("", "2X"), .invalid(()))
        XCTAssertEqual(d("", "202"), .invalid(()))
        XCTAssertEqual(d("", "2020"), .invalid(()))
        XCTAssertEqual(d("X", "X"), .invalid(()))
        XCTAssertEqual(d(" 3", "40"), .invalid(()))
        XCTAssertEqual(d("3", " 40"), .invalid(()))
    }

    func testValidityOfCvv() {
        func c(_ cvv: String, _ cardType: CardType) -> Validity {
            CreditAndDebitCards.validity(ofCvv: cvv, cardType: cardType)
        }

        let threeDigitTypes: [CardType] = [.unionPay, .other]
        for cardType in threeDigitTypes {
            XCTAssertEqual(c("", cardType), .potentiallyValid)
            XCTAssertEqual(c("1", cardType), .potentiallyValid)
            XCTAssertEqual(c("12", cardType), .potentiallyValid)
            XCTAssertEqual(c("123", cardType), .fullyValid)
            XCTAssertEqual(c("1234", cardType), .invalid(()))
        }

        XCTAssertEqual(c("", .americanExpress), .potentiallyValid)
        XCTAssertEqual(c("1", .americanExpress), .potentiallyValid)
        XCTAssertEqual(c("12", .americanExpress), .potentiallyValid)
        XCTAssertEqual(c("123", .americanExpress), .potentiallyValid)
        XCTAssertEqual(c("1234", .americanExpress), .fullyValid)
        XCTAssertEqual(c("12345", .americanExpress), .invalid(()))

        XCTAssertEqual(c("X", .other), .invalid(()))
        XCTAssertEqual(c("1X", .other), .invalid(()))
        XCTAssertEqual(c("X1", .other), .invalid(()))
        XCTAssertEqual(c(" 123", .other), .invalid(()))
    }

    // TODO: [SEPA] Test SEPA validation
}

extension PaymentMethodFieldValidity: Equatable {
    public static func == (lhs: PaymentMethodFieldValidity<Invalidity>, rhs: PaymentMethodFieldValidity<Invalidity>) -> Bool where Invalidity: Equatable {
        switch (lhs, rhs) {
        case (.potentiallyValid, .potentiallyValid):
            return true
        case (.fullyValid, .fullyValid):
            return true
        case let (.invalid(invalidLHS), .invalid(invalidRHS)):
            return invalidLHS == invalidRHS
        default:
            return false
        }
    }

    public static func == (lhs: PaymentMethodFieldValidity<Invalidity>, rhs: PaymentMethodFieldValidity<Invalidity>) -> Bool {
        switch (lhs, rhs) {
        case (.potentiallyValid, .potentiallyValid):
            return true
        case (.fullyValid, .fullyValid):
            return true
        case (.invalid, .invalid):
            return true
        default:
            return false
        }
    }
}
