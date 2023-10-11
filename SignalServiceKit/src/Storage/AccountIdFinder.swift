//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public typealias AccountId = String

@objc
public extension SignalRecipient {
    var accountId: AccountId! {
        return uniqueId
    }
}

public enum RecipientIdError: Error {
    /// We can't use the Pni because it's been replaced by an Aci.
    case mustNotUsePniBecauseAciExists
}

@objc
public class OWSAccountIdFinder: NSObject {
    class func recipientId(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> Result<AccountId, RecipientIdError>? {
        let recipientStore = DependenciesBridge.shared.recipientStore
        guard let recipient = recipientStore.fetchRecipient(serviceId: serviceId, transaction: tx.asV2Read) else {
            return nil
        }
        return recipientIdResult(for: serviceId, recipient: recipient)
    }

    class func recipientId(for address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> Result<AccountId, RecipientIdError>? {
        guard let recipient = SignalRecipient.fetchRecipient(for: address, onlyIfRegistered: false, tx: tx) else {
            return nil
        }
        return recipientIdResult(for: address.serviceId, recipient: recipient)
    }

    class func ensureRecipientId(for serviceId: ServiceId, tx: SDSAnyWriteTransaction) -> Result<AccountId, RecipientIdError> {
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx.asV2Write)
        return recipientIdResult(for: serviceId, recipient: recipient)
    }

    private static func recipientIdResult(for serviceId: ServiceId?, recipient: SignalRecipient) -> Result<AccountId, RecipientIdError> {
        if serviceId is Pni, recipient.aciString != nil {
            return .failure(.mustNotUsePniBecauseAciExists)
        }
        return .success(recipient.uniqueId)
    }

    @objc
    public class func accountId(
        forAddress address: SignalServiceAddress,
        transaction: SDSAnyReadTransaction
    ) -> AccountId? {
        return SignalRecipient.fetchRecipient(for: address, onlyIfRegistered: false, tx: transaction)?.accountId
    }

    public class func ensureRecipient(
        forAddress address: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) -> SignalRecipient {
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
            recipient = SignalRecipient(aci: nil, pni: nil, phoneNumber: nil)
            recipient.anyInsert(transaction: transaction)
        }
        return recipient
    }
}
