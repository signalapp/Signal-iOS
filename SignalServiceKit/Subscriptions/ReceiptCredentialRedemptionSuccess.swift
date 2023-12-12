//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Represents a successful receipt credential request and the subsequent
/// redemption of that receipt credential.
///
/// These are persisted in the ``SubscriptionReceiptCredentialRequestResultStore``
/// by the ``ReceiptCredentialRedemptionJobQueue``'s
/// ``SubscriptionReceiptCredentailRedemptionOperation``.
public struct ReceiptCredentialRedemptionSuccess: Codable {
    public let badgesSnapshotBeforeJob: ProfileBadgesSnapshot
    public let badge: ProfileBadge
    public let paymentMethod: DonationPaymentMethod?

    public init(
        badgesSnapshotBeforeJob: ProfileBadgesSnapshot,
        badge: ProfileBadge,
        paymentMethod: DonationPaymentMethod?
    ) {
        self.badgesSnapshotBeforeJob = badgesSnapshotBeforeJob
        self.badge = badge
        self.paymentMethod = paymentMethod
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case badgesSnapshotBeforeJob
        case badge
        case paymentMethod
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        badgesSnapshotBeforeJob = try container.decode(ProfileBadgesSnapshot.self, forKey: .badgesSnapshotBeforeJob)
        badge = try container.decode(ProfileBadge.self, forKey: .badge)
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod).map { rawValue throws in
            guard let paymentMethod = DonationPaymentMethod(rawValue: rawValue) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: [CodingKeys.paymentMethod],
                    debugDescription: "Unexpected payment method raw value: \(rawValue)"
                ))
            }

            return paymentMethod
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(badgesSnapshotBeforeJob, forKey: .badgesSnapshotBeforeJob)
        try container.encode(badge, forKey: .badge)
        try container.encodeIfPresent(paymentMethod?.rawValue, forKey: .paymentMethod)
    }
}
