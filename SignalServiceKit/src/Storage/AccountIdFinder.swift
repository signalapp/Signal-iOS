//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
    public func accountId(forAddress address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> AccountId? {
        return SignalRecipient.get(address: address, mustHaveDevices: false, transaction: transaction)?.accountId
    }

    @objc
    public func ensureAccountId(forAddress address: SignalServiceAddress, transaction: SDSAnyWriteTransaction) -> AccountId {
        if let accountId = accountId(forAddress: address, transaction: transaction) {
            return accountId
        }

        let recipient = SignalRecipient.mark(asRegisteredAndGet: address, trustLevel: .low, transaction: transaction)
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

extension OWSAccountIdFinder: SMKAccountIdFinder {
    public func accountId(forUuid uuid: UUID?, phoneNumber: String?, protocolContext: SPKProtocolWriteContext?) -> String? {
        guard let transaction = protocolContext as? SDSAnyWriteTransaction else {
            owsFail("transaction had unexected type: \(type(of: protocolContext))")
        }

        return ensureAccountId(forUuid: uuid, phoneNumber: phoneNumber, transaction: transaction)
    }

    private func ensureAccountId(forUuid uuid: UUID?, phoneNumber: String?, transaction: SDSAnyWriteTransaction) -> String? {
        let address = SignalServiceAddress(uuid: uuid, phoneNumber: phoneNumber)
        guard address.isValid else {
            owsFailDebug("address was invalid")
            return nil
        }
        return ensureAccountId(forAddress: address, transaction: transaction)
    }
}
