//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

/// Legacy persisted data contained full `DonationSubscriptionLevel` JSON blobs
/// for the new/old subscription levels, which we've since migrated to persisting
/// only the raw levels. These tests cover decoding both the legacy and current
/// representations.
struct PendingMonthlyIDEALDonationCodableTest {

    /// A full `DonationSubscriptionLevel` blob, as it would have been persisted
    /// before we migrated to persisting only the raw level.
    private static func legacyLevelJSON(rawLevel: UInt) -> String {
        return """
        {
            "level": \(rawLevel),
            "badge": {
                "id": "R_MEDIUM",
                "rawCategory": "donor",
                "localizedName": "Signal Sustainer",
                "localizedDescriptionFormatString": "%@ supports Signal with a donation.",
                "resourcePath": "medium.png",
                "badgeVariant": "xxhdpi",
                "localization": "en",
                "duration": 2592000
            },
            "amounts": {
                "USD": { "currencyCode": "USD", "value": 5 }
            }
        }
        """
    }

    /// base64 of a 32-byte all-zero subscriber ID.
    private static let subscriberIdBase64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

    @Test
    func testDecodeWithLegacyLevels() throws {
        let json = """
        {
            "subscriberId": "\(Self.subscriberIdBase64)",
            "clientSecret": "secret",
            "setupIntentId": "intent",
            "newSubscriptionLevel": \(Self.legacyLevelJSON(rawLevel: 500)),
            "oldSubscriptionLevel": \(Self.legacyLevelJSON(rawLevel: 200)),
            "amount": { "currencyCode": "EUR", "value": 5 },
            "createDate": 700000000
        }
        """

        let donation = try JSONDecoder().decode(
            PendingMonthlyIDEALDonation.self,
            from: Data(json.utf8),
        )

        #expect(donation.subscriberId == Data(base64Encoded: Self.subscriberIdBase64))
        #expect(donation.clientSecret == "secret")
        #expect(donation.setupIntentId == "intent")
        #expect(donation.newSubscriptionLevel == 500)
        #expect(donation.oldSubscriptionLevel == 200)
        #expect(donation.amount == FiatMoney(currencyCode: "EUR", value: 5))
    }

    @Test
    func testDecodeWithLegacyLevelsMissingOldLevel() throws {
        let json = """
        {
            "subscriberId": "\(Self.subscriberIdBase64)",
            "clientSecret": "secret",
            "setupIntentId": "intent",
            "newSubscriptionLevel": \(Self.legacyLevelJSON(rawLevel: 500)),
            "amount": { "currencyCode": "EUR", "value": 5 },
            "createDate": 700000000
        }
        """

        let donation = try JSONDecoder().decode(
            PendingMonthlyIDEALDonation.self,
            from: Data(json.utf8),
        )

        #expect(donation.newSubscriptionLevel == 500)
        #expect(donation.oldSubscriptionLevel == nil)
    }

    @Test
    func testDecodeWithCurrentLevels() throws {
        let json = """
        {
            "subscriberId": "\(Self.subscriberIdBase64)",
            "clientSecret": "secret",
            "setupIntentId": "intent",
            "newSubscriptionLevelRaw": 500,
            "oldSubscriptionLevelRaw": 200,
            "amount": { "currencyCode": "EUR", "value": 5 },
            "createDate": 700000000
        }
        """

        let donation = try JSONDecoder().decode(
            PendingMonthlyIDEALDonation.self,
            from: Data(json.utf8),
        )

        #expect(donation.newSubscriptionLevel == 500)
        #expect(donation.oldSubscriptionLevel == 200)
    }

    @Test
    func testDecodeWithCurrentLevelsMissingOldLevel() throws {
        let json = """
        {
            "subscriberId": "\(Self.subscriberIdBase64)",
            "clientSecret": "secret",
            "setupIntentId": "intent",
            "newSubscriptionLevelRaw": 500,
            "amount": { "currencyCode": "EUR", "value": 5 },
            "createDate": 700000000
        }
        """

        let donation = try JSONDecoder().decode(
            PendingMonthlyIDEALDonation.self,
            from: Data(json.utf8),
        )

        #expect(donation.newSubscriptionLevel == 500)
        #expect(donation.oldSubscriptionLevel == nil)
    }

    @Test
    func testRoundTrips() throws {
        let donation = PendingMonthlyIDEALDonation(
            subscriberId: Data(base64Encoded: Self.subscriberIdBase64)!,
            clientSecret: "secret",
            setupIntentId: "intent",
            newSubscriptionLevel: 500,
            oldSubscriptionLevel: 200,
            amount: FiatMoney(currencyCode: "EUR", value: 5),
        )

        let encoded = try JSONEncoder().encode(donation)
        let decoded = try JSONDecoder().decode(
            PendingMonthlyIDEALDonation.self,
            from: encoded,
        )

        #expect(decoded == donation)
    }

    @Test
    func testRoundTripsWithoutOldLevel() throws {
        let donation = PendingMonthlyIDEALDonation(
            subscriberId: Data(base64Encoded: Self.subscriberIdBase64)!,
            clientSecret: "secret",
            setupIntentId: "intent",
            newSubscriptionLevel: 500,
            oldSubscriptionLevel: nil,
            amount: FiatMoney(currencyCode: "EUR", value: 5),
        )

        let encoded = try JSONEncoder().encode(donation)
        let decoded = try JSONDecoder().decode(
            PendingMonthlyIDEALDonation.self,
            from: encoded,
        )

        #expect(decoded == donation)
    }
}
