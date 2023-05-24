//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public typealias AccountId = String

@objc
public extension SignalRecipient {
    var accountId: AccountId! {
        return uniqueId
    }
}

@objc
public class OWSAccountIdFinder: NSObject {
    @objc
    public class func accountId(
        forAddress address: SignalServiceAddress,
        transaction: SDSAnyReadTransaction
    ) -> AccountId? {
        return SignalRecipient.fetchRecipient(for: address, onlyIfRegistered: false, tx: transaction)?.accountId
    }

    /// Fetches (or creates) a SignalRecipient for a provided address.
    ///
    /// In general, callers should prefer using ``RecipientFetcher`` directly.
    @objc
    public class func ensureAccountId(
        forAddress address: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) -> AccountId {
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let recipient: SignalRecipient
        if let serviceId = address.serviceId {
            recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: transaction.asV2Write)
        } else if let phoneNumber = address.e164 {
            recipient = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: transaction.asV2Write)
        } else {
            // This can happen for historical reasons. It shouldn't happen, but it
            // could. We could return [[NSUUID UUID] UUIDString] and avoid persisting
            // anything to disk. However, it's possible that a caller may expect to be
            // able to fetch the recipient based on the value we return, so we need to
            // ensure that the return value can be fetched. In the future, we should
            // update all callers to ensure they pass valid addresses.
            owsFailDebug("Fetching accountId for invalid address.")
            recipient = SignalRecipient(serviceId: nil, phoneNumber: nil)
            recipient.anyInsert(transaction: transaction)
        }
        return recipient.uniqueId
    }

    @objc
    public class func address(forAccountId accountId: AccountId,
                              transaction: SDSAnyReadTransaction) -> SignalServiceAddress? {
        guard let recipient = SignalRecipient.anyFetch(uniqueId: accountId, transaction: transaction) else {
            return nil
        }
        return recipient.address
    }
}
