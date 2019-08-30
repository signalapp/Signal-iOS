//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class AnySignalRecipientFinder: NSObject {
    let grdbAdapter = GRDBSignalRecipientFinder()
    let yapdbAdapter = YAPDBSignalServiceAddressIndex()
}

extension AnySignalRecipientFinder {
    @objc(signalRecipientForAddress:transaction:)
    public func signalRecipient(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalRecipient? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalRecipient(for: address, transaction: transaction)
        case .yapRead(let transaction):
            return yapdbAdapter.fetchOne(for: address, transaction: transaction)
        }
    }
}

@objc
class GRDBSignalRecipientFinder: NSObject {
    func signalRecipient(for address: SignalServiceAddress, transaction: GRDBReadTransaction) -> SignalRecipient? {
        if let recipient = signalRecipientForUUID(address.uuid, transaction: transaction) {
            return recipient
        } else if let recipient = signalRecipientForPhoneNumber(address.phoneNumber, transaction: transaction) {
            return recipient
        } else {
            return nil
        }
    }

    private func signalRecipientForUUID(_ uuid: UUID?, transaction: GRDBReadTransaction) -> SignalRecipient? {
        guard let uuidString = uuid?.uuidString else { return nil }
        let sql = "SELECT * FROM \(SignalRecipientRecord.databaseTableName) WHERE \(signalRecipientColumn: .recipientUUID) = ?"
        return SignalRecipient.grdbFetchOne(sql: sql, arguments: [uuidString], transaction: transaction)
    }

    private func signalRecipientForPhoneNumber(_ phoneNumber: String?, transaction: GRDBReadTransaction) -> SignalRecipient? {
        guard let phoneNumber = phoneNumber else { return nil }
        let sql = "SELECT * FROM \(SignalRecipientRecord.databaseTableName) WHERE \(signalRecipientColumn: .recipientPhoneNumber) = ?"
        return SignalRecipient.grdbFetchOne(sql: sql, arguments: [phoneNumber], transaction: transaction)
    }
}
