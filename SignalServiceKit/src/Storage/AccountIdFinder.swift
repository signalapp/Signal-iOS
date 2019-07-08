//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public typealias AccountId = String

@objc
public extension SignalRecipient {
    var accountId: AccountId! {
        guard let accountId = uniqueId else {
            owsFailDebug("UniqueID unexpectedly nil")
            return nil
        }
        return accountId
    }
}

@objc
public class OWSAccountIdFinder: NSObject {
    @objc
    public func accountId(forAddress address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> AccountId? {
        return SignalRecipient.registeredRecipient(for: address, mustHaveDevices: false, transaction: transaction)?.accountId
    }

    @objc
    public func ensureAccountId(forAddress address: SignalServiceAddress, transaction: SDSAnyWriteTransaction) -> AccountId {
        if let accountId = accountId(forAddress: address, transaction: transaction) {
            return accountId
        }

        let recipient = SignalRecipient(address: address)
        recipient.anyInsert(transaction: transaction)
        return recipient.accountId
    }

    @objc
    public func address(forAccountId accountId: AccountId, transaction: SDSAnyReadTransaction) -> SignalServiceAddress? {
        guard let recipient = SignalRecipient.anyFetch(uniqueId: accountId, transaction: transaction) else {
            return nil
        }
        return recipient.address
    }
}
