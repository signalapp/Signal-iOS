//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct PendingOneTimeIDEALDonation: Codable {
    public let amount: FiatMoney
    public let paymentIntentId: String
    public let createDate: Date

    public init(
        paymentIntentId: String,
        amount: FiatMoney
    ) {
        self.paymentIntentId = paymentIntentId
        self.amount = amount
        self.createDate = Date()
    }
}

public struct PendingMonthlyIDEALDonation: Codable {
    public let subscriberId: Data
    public let clientSecret: String
    public let setupIntentId: String
    public let newSubscriptionLevel: SubscriptionLevel
    public let oldSubscriptionLevel: SubscriptionLevel?
    public let amount: FiatMoney
    public let createDate: Date

    public init(
        subscriberId: Data,
        clientSecret: String,
        setupIntentId: String,
        newSubscriptionLevel: SubscriptionLevel,
        oldSubscriptionLevel: SubscriptionLevel?,
        amount: FiatMoney
    ) {
        self.subscriberId = subscriberId
        self.clientSecret = clientSecret
        self.setupIntentId = setupIntentId
        self.newSubscriptionLevel = newSubscriptionLevel
        self.oldSubscriptionLevel = oldSubscriptionLevel
        self.amount = amount
        self.createDate = Date()
    }
}

public protocol ExternalPendingIDEALDonationStore {
    func getPendingOneTimeDonation(tx: DBReadTransaction) -> PendingOneTimeIDEALDonation?
    func setPendingOneTimeDonation(donation: PendingOneTimeIDEALDonation, tx: DBWriteTransaction) throws
    func clearPendingOneTimeDonation(tx: DBWriteTransaction)

    func getPendingSubscription(tx: DBReadTransaction) -> PendingMonthlyIDEALDonation?
    func setPendingSubscription(donation: PendingMonthlyIDEALDonation, tx: DBWriteTransaction) throws
    func clearPendingSubscription(tx: DBWriteTransaction)
}

public class ExternalPendingIDEALDonationStoreImpl: ExternalPendingIDEALDonationStore {

    private enum Constants {
        static let pendingOneTimeDonationKey = "PendingOneTimeDonationKey"
        static let pendingMonthlyDonationKey = "PendingMonthlyDonationKey"
    }

    private let keyStore: KeyValueStore
    init(keyStoreFactory: KeyValueStoreFactory) {
        keyStore = keyStoreFactory.keyValueStore(collection: "PendingExternalDonationStore")
    }

    public func getPendingOneTimeDonation(tx: DBReadTransaction) -> PendingOneTimeIDEALDonation? {
        do {
            return try keyStore.getCodableValue(forKey: Constants.pendingOneTimeDonationKey, transaction: tx)
        } catch {
            owsFailDebug("Could not decode donation: \(error.localizedDescription)")
            return nil
        }
    }

    public func setPendingOneTimeDonation(donation: PendingOneTimeIDEALDonation, tx: DBWriteTransaction) throws {
        try keyStore.setCodable(donation, key: Constants.pendingOneTimeDonationKey, transaction: tx)
    }

    public func clearPendingOneTimeDonation(tx: DBWriteTransaction) {
        keyStore.removeValue(forKey: Constants.pendingOneTimeDonationKey, transaction: tx)
    }

    public func getPendingSubscription(tx: DBReadTransaction) -> PendingMonthlyIDEALDonation? {
        do {
            return try keyStore.getCodableValue(forKey: Constants.pendingMonthlyDonationKey, transaction: tx)
        } catch {
            owsFailDebug("Could not decode donation: \(error.localizedDescription)")
            return nil
        }
    }

    public func setPendingSubscription(donation: PendingMonthlyIDEALDonation, tx: DBWriteTransaction) throws {
        try keyStore.setCodable(donation, key: Constants.pendingMonthlyDonationKey, transaction: tx)
    }

    public func clearPendingSubscription(tx: DBWriteTransaction) {
        keyStore.removeValue(forKey: Constants.pendingMonthlyDonationKey, transaction: tx)
    }
}
