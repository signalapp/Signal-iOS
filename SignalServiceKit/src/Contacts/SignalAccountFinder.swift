//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class AnySignalAccountFinder: NSObject {
    let grdbAdapter = GRDBSignalAccountFinder()
    let yapdbAdapter = YAPDBSignalServiceAddressIndex()
}

extension AnySignalAccountFinder {
    @objc(signalAccountForAddress:transaction:)
    func signalAccount(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalAccount(for: address, transaction: transaction)
        case .yapRead(let transaction):
            return yapdbAdapter.fetchOne(for: address, transaction: transaction)
        }
    }
}

@objc
class GRDBSignalAccountFinder: NSObject {
    func signalAccount(for address: SignalServiceAddress, transaction: GRDBReadTransaction) -> SignalAccount? {
        if let account = signalAccountForUUID(address.uuid, transaction: transaction) {
            return account
        } else if let account = signalAccountForPhoneNumber(address.phoneNumber, transaction: transaction) {
            return account
        } else {
            return nil
        }
    }

    private func signalAccountForUUID(_ uuid: UUID?, transaction: GRDBReadTransaction) -> SignalAccount? {
        guard let uuidString = uuid?.uuidString else { return nil }
        let sql = "SELECT * FROM \(SignalAccountRecord.databaseTableName) WHERE \(signalAccountColumn: .recipientUUID) = ?"
        return SignalAccount.grdbFetchOne(sql: sql, arguments: [uuidString], transaction: transaction)
    }

    private func signalAccountForPhoneNumber(_ phoneNumber: String?, transaction: GRDBReadTransaction) -> SignalAccount? {
        guard let phoneNumber = phoneNumber else { return nil }
        let sql = "SELECT * FROM \(SignalAccountRecord.databaseTableName) WHERE \(signalAccountColumn: .recipientPhoneNumber) = ?"
        return SignalAccount.grdbFetchOne(sql: sql, arguments: [phoneNumber], transaction: transaction)
    }
}
