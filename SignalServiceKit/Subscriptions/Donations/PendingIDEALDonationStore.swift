//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - PendingOneTimeIDEALDonation

public struct PendingOneTimeIDEALDonation: Codable, Equatable {
    public let amount: FiatMoney
    public let paymentIntentId: String
    public let createDate: Date

    public init(
        paymentIntentId: String,
        amount: FiatMoney,
    ) {
        self.paymentIntentId = paymentIntentId
        self.amount = amount
        self.createDate = Date()
    }
}

// MARK: - PendingMonthlyIDEALDonation

public struct PendingMonthlyIDEALDonation: Codable, Equatable {
    public let subscriberId: Data
    public let clientSecret: String
    public let setupIntentId: String
    public let newSubscriptionLevel: UInt
    public let oldSubscriptionLevel: UInt?
    public let amount: FiatMoney
    public let createDate: Date

    public init(
        subscriberId: Data,
        clientSecret: String,
        setupIntentId: String,
        newSubscriptionLevel: UInt,
        oldSubscriptionLevel: UInt?,
        amount: FiatMoney,
    ) {
        self.subscriberId = subscriberId
        self.clientSecret = clientSecret
        self.setupIntentId = setupIntentId
        self.newSubscriptionLevel = newSubscriptionLevel
        self.oldSubscriptionLevel = oldSubscriptionLevel
        self.amount = amount
        self.createDate = Date()
    }

    private enum CodingKeys: String, CodingKey {
        case subscriberId
        case clientSecret
        case setupIntentId
        // Deserialize-only; see usage.
        case newSubscriptionLevel
        // Deserialize-only; see usage.
        case oldSubscriptionLevel
        case newSubscriptionLevelRaw
        case oldSubscriptionLevelRaw
        case amount
        case createDate
    }

    /// In the past, we persisted subscription levels as full
    /// ``DonationSubscriptionLevel`` objects. We've since migrated to only
    /// storing the raw level, but we may need to decode legacy objects to get
    /// their raw level.
    private struct LegacyDonationSubscriptionLevel: Decodable {
        let level: UInt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        subscriberId = try container.decode(Data.self, forKey: .subscriberId)
        clientSecret = try container.decode(String.self, forKey: .clientSecret)
        setupIntentId = try container.decode(String.self, forKey: .setupIntentId)
        amount = try container.decode(FiatMoney.self, forKey: .amount)
        createDate = try container.decode(Date.self, forKey: .createDate)

        if container.contains(.newSubscriptionLevelRaw) {
            newSubscriptionLevel = try container.decode(UInt.self, forKey: .newSubscriptionLevelRaw)
        } else {
            newSubscriptionLevel = try container.decode(
                LegacyDonationSubscriptionLevel.self,
                forKey: .newSubscriptionLevel,
            ).level
        }

        if container.contains(.oldSubscriptionLevelRaw) {
            oldSubscriptionLevel = try container.decodeIfPresent(UInt.self, forKey: .oldSubscriptionLevelRaw)
        } else {
            oldSubscriptionLevel = try container.decodeIfPresent(
                LegacyDonationSubscriptionLevel.self,
                forKey: .oldSubscriptionLevel,
            )?.level
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(subscriberId, forKey: .subscriberId)
        try container.encode(clientSecret, forKey: .clientSecret)
        try container.encode(setupIntentId, forKey: .setupIntentId)
        try container.encode(newSubscriptionLevel, forKey: .newSubscriptionLevelRaw)
        try container.encodeIfPresent(oldSubscriptionLevel, forKey: .oldSubscriptionLevelRaw)
        try container.encode(amount, forKey: .amount)
        try container.encode(createDate, forKey: .createDate)
    }
}

// MARK: - PendingIDEALDonationStore

public struct PendingIDEALDonationStore {

    private enum Constants {
        static let pendingOneTimeDonationKey = "PendingOneTimeDonationKey"
        static let pendingMonthlyDonationKey = "PendingMonthlyDonationKey"
        static let unclaimedOneTimeDonationKey = "UnclaimedOneTimeDonationKey"
        static let unclaimedRecurringDonationKey = "UnclaimedRecurringDonationKey"
    }

    private let keyStore: NewKeyValueStore

    init() {
        keyStore = NewKeyValueStore(collection: "PendingExternalDonationStore")
    }

    // MARK: - One-time

    public func getPendingOneTimeDonation(tx: DBReadTransaction) -> PendingOneTimeIDEALDonation? {
        do {
            return try keyStore.fetchJSONAsValue(PendingOneTimeIDEALDonation.self, forKey: Constants.pendingOneTimeDonationKey, tx: tx)
        } catch {
            owsFailDebug("Could not decode donation: \(error.localizedDescription)")
            return nil
        }
    }

    public func setPendingOneTimeDonation(donation: PendingOneTimeIDEALDonation, tx: DBWriteTransaction) {
        keyStore.writeValueAsJSON(donation, forKey: Constants.pendingOneTimeDonationKey, tx: tx)
    }

    public func clearPendingOneTimeDonation(tx: DBWriteTransaction) {
        keyStore.removeValue(forKey: Constants.pendingOneTimeDonationKey, tx: tx)
    }

    // MARK: - Monthly

    public func getPendingSubscription(tx: DBReadTransaction) -> PendingMonthlyIDEALDonation? {
        do {
            return try keyStore.fetchJSONAsValue(PendingMonthlyIDEALDonation.self, forKey: Constants.pendingMonthlyDonationKey, tx: tx)
        } catch {
            owsFailDebug("Could not decode donation: \(error.localizedDescription)")
            return nil
        }
    }

    public func setPendingSubscription(donation: PendingMonthlyIDEALDonation, tx: DBWriteTransaction) {
        keyStore.writeValueAsJSON(donation, forKey: Constants.pendingMonthlyDonationKey, tx: tx)
    }

    public func clearPendingSubscription(tx: DBWriteTransaction) {
        keyStore.removeValue(forKey: Constants.pendingMonthlyDonationKey, tx: tx)
    }

    // MARK: - Donation Handling

    public func claimDonationHandling(isOneTime: Bool, intentId: String, tx: DBWriteTransaction) -> Bool {
        let key = isOneTime ? Constants.unclaimedOneTimeDonationKey : Constants.unclaimedRecurringDonationKey
        let returnValue = keyStore.fetchValue(String.self, forKey: key, tx: tx) == intentId
        if returnValue {
            keyStore.removeValue(forKey: key, tx: tx)
        }
        return returnValue
    }

    public func setDonationNeedsHandling(isOneTime: Bool, intentId: String, tx: DBWriteTransaction) {
        let key = isOneTime ? Constants.unclaimedOneTimeDonationKey : Constants.unclaimedRecurringDonationKey
        keyStore.writeValue(intentId, forKey: key, tx: tx)
    }
}
