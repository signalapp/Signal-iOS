//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

/// Legacy persisted data contained a full `ProfileBadge` JSON blob, which we've
/// since migrated to persisting only the badge's ID. These tests cover decoding
/// both the legacy and current representations.
struct DonationReceiptCredentialResultCodableTest {

    /// A full `ProfileBadge` blob, as it would have been persisted before we
    /// migrated to persisting only the badge ID.
    private static let legacyBadgeJSON: String = """
    {
        "id": "BOOST",
        "rawCategory": "donor",
        "localizedName": "Boost",
        "localizedDescriptionFormatString": "%@ supports Signal with a donation.",
        "resourcePath": "boost.png",
        "badgeVariant": "xxhdpi",
        "localization": "en",
        "duration": 2592000
    }
    """

    // MARK: - DonationReceiptCredentialRedemptionSuccess

    @Test
    func testDecodeSuccessWithLegacyBadge() throws {
        let json = """
        {
            "badgesSnapshotBeforeJob": {
                "existingBadges": [
                    { "id": "R_MEDIUM", "isVisible": true }
                ]
            },
            "badge": \(Self.legacyBadgeJSON),
            "paymentMethod": "sepa"
        }
        """

        let success = try JSONDecoder().decode(
            DonationReceiptCredentialRedemptionSuccess.self,
            from: Data(json.utf8),
        )

        #expect(success.badgeID == "BOOST")
        #expect(success.paymentMethod == .sepa)
        #expect(success.badgesSnapshotBeforeJob.existingBadges.map(\.id) == ["R_MEDIUM"])
    }

    @Test
    func testDecodeSuccessWithBadgeID() throws {
        let json = """
        {
            "badgesSnapshotBeforeJob": { "existingBadges": [] },
            "badgeID": "BOOST",
            "paymentMethod": "sepa"
        }
        """

        let success = try JSONDecoder().decode(
            DonationReceiptCredentialRedemptionSuccess.self,
            from: Data(json.utf8),
        )

        #expect(success.badgeID == "BOOST")
        #expect(success.paymentMethod == .sepa)
        #expect(success.badgesSnapshotBeforeJob.existingBadges.isEmpty)
    }

    @Test
    func testSuccessRoundTrips() throws {
        let success = DonationReceiptCredentialRedemptionSuccess(
            badgesSnapshotBeforeJob: ProfileBadgesSnapshot(existingBadges: [
                ProfileBadgesSnapshot.Badge(id: "R_MEDIUM", isVisible: false),
            ]),
            badgeID: "BOOST",
            paymentMethod: .creditOrDebitCard,
        )

        let encoded = try JSONEncoder().encode(success)
        let decoded = try JSONDecoder().decode(
            DonationReceiptCredentialRedemptionSuccess.self,
            from: encoded,
        )

        #expect(decoded.badgeID == "BOOST")
        #expect(decoded.paymentMethod == .creditOrDebitCard)
        #expect(decoded.badgesSnapshotBeforeJob.existingBadges.map(\.id) == ["R_MEDIUM"])
        #expect(decoded.badgesSnapshotBeforeJob.existingBadges.map(\.isVisible) == [false])
    }

    // MARK: - DonationReceiptCredentialRequestError

    @Test
    func testDecodeErrorWithLegacyBadge() throws {
        let json = """
        {
            "errorCode": 402,
            "chargeFailureCodeIfPaymentFailed": "card_declined",
            "badge": \(Self.legacyBadgeJSON),
            "amount": { "currencyCode": "USD", "value": 12.5 },
            "paymentMethod": "creditOrDebitCard",
            "timestampMs": 1234567890000
        }
        """

        let error = try JSONDecoder().decode(
            DonationReceiptCredentialRequestError.self,
            from: Data(json.utf8),
        )

        #expect(error.badgeID == "BOOST")
        #expect(error.errorCode == .paymentFailed)
        #expect(error.chargeFailureCodeIfPaymentFailed == "card_declined")
        #expect(error.amount == FiatMoney(currencyCode: "USD", value: 12.5))
        #expect(error.paymentMethod == .creditOrDebitCard)
        #expect(error.creationDate == Date(millisecondsSince1970: 1234567890000))
    }

    @Test
    func testDecodeErrorWithBadgeID() throws {
        let json = """
        {
            "errorCode": 204,
            "badgeID": "BOOST",
            "amount": { "currencyCode": "EUR", "value": 5 },
            "paymentMethod": "sepa",
            "timestampMs": 1234567890000
        }
        """

        let error = try JSONDecoder().decode(
            DonationReceiptCredentialRequestError.self,
            from: Data(json.utf8),
        )

        #expect(error.badgeID == "BOOST")
        #expect(error.errorCode == .paymentStillProcessing)
        #expect(error.chargeFailureCodeIfPaymentFailed == nil)
        #expect(error.amount == FiatMoney(currencyCode: "EUR", value: 5))
        #expect(error.paymentMethod == .sepa)
    }

    @Test
    func testErrorRoundTrips() throws {
        let error = DonationReceiptCredentialRequestError(
            errorCode: .paymentFailed,
            chargeFailureCodeIfPaymentFailed: "card_declined",
            badgeID: "BOOST",
            amount: FiatMoney(currencyCode: "USD", value: 12.5),
            paymentMethod: .creditOrDebitCard,
            now: Date(millisecondsSince1970: 1234567890000),
        )

        let encoded = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(
            DonationReceiptCredentialRequestError.self,
            from: encoded,
        )

        #expect(decoded == error)
    }
}
