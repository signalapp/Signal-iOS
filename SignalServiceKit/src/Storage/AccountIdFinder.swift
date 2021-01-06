//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMetadataKit

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
    public class func accountId(forAddress address: SignalServiceAddress,
                                transaction: SDSAnyReadTransaction) -> AccountId? {
        return SignalRecipient.get(address: address, mustHaveDevices: false, transaction: transaction)?.accountId
    }

    @objc
    public class func ensureAccountId(forAddress address: SignalServiceAddress,
                                      transaction: SDSAnyWriteTransaction) -> AccountId {
        if let accountId = accountId(forAddress: address, transaction: transaction) {
            return accountId
        }

        let recipient = SignalRecipient.mark(asRegisteredAndGet: address, trustLevel: .low, transaction: transaction)
        return recipient.accountId
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
