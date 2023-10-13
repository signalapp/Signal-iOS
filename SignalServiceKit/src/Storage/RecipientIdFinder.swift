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

public enum RecipientIdError: Error, IsRetryableProvider {
    /// We can't use the Pni because it's been replaced by an Aci.
    case mustNotUsePniBecauseAciExists

    public var isRetryableProvider: Bool {
        // Allow retries so that we send to the Aci instead of the Pni.
        return true
    }
}

public final class RecipientIdFinder {
    private let recipientFetcher: RecipientFetcher
    private let recipientStore: RecipientDataStore

    public init(
        recipientFetcher: RecipientFetcher,
        recipientStore: RecipientDataStore
    ) {
        self.recipientFetcher = recipientFetcher
        self.recipientStore = recipientStore
    }

    public func recipientId(for serviceId: ServiceId, tx: DBReadTransaction) -> Result<AccountId, RecipientIdError>? {
        guard let recipient = recipientStore.fetchRecipient(serviceId: serviceId, transaction: tx) else {
            return nil
        }
        return recipientIdResult(for: serviceId, recipient: recipient)
    }

    public func recipientId(for address: SignalServiceAddress, tx: DBReadTransaction) -> Result<AccountId, RecipientIdError>? {
        guard let recipient = SignalRecipient.fetchRecipient(for: address, onlyIfRegistered: false, tx: SDSDB.shimOnlyBridge(tx)) else {
            return nil
        }
        return recipientIdResult(for: address.serviceId, recipient: recipient)
    }

    public func ensureRecipientId(for serviceId: ServiceId, tx: DBWriteTransaction) -> Result<AccountId, RecipientIdError> {
        let recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx)
        return recipientIdResult(for: serviceId, recipient: recipient)
    }

    private func recipientIdResult(for serviceId: ServiceId?, recipient: SignalRecipient) -> Result<AccountId, RecipientIdError> {
        if serviceId is Pni, recipient.aciString != nil {
            return .failure(.mustNotUsePniBecauseAciExists)
        }
        return .success(recipient.uniqueId)
    }
}

public final class OWSAccountIdFinder {
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
