//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public class AnySignalRecipientFinder: NSObject {
    let grdbAdapter = GRDBSignalRecipientFinder()
}

extension AnySignalRecipientFinder {
    @objc(signalRecipientForUUID:transaction:)
    public func signalRecipientForUUID(_ uuid: UUID?, transaction: SDSAnyReadTransaction) -> SignalRecipient? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalRecipientForUUID(uuid, transaction: transaction)
        }
    }

    @objc(signalRecipientForPhoneNumber:transaction:)
    public func signalRecipientForPhoneNumber(_ phoneNumber: String?, transaction: SDSAnyReadTransaction) -> SignalRecipient? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalRecipientForPhoneNumber(phoneNumber, transaction: transaction)
        }
    }

    @objc(signalRecipientForAddress:transaction:)
    public func signalRecipient(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalRecipient? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalRecipient(for: address, transaction: transaction)
        }
    }

    public func signalRecipients(for addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [SignalRecipient] {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalRecipients(for: addresses, transaction: transaction)
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

    fileprivate func signalRecipientForUUID(_ uuid: UUID?, transaction: GRDBReadTransaction) -> SignalRecipient? {
        guard let uuidString = uuid?.uuidString else { return nil }
        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(signalRecipientColumn: .serviceIdString) = ?"
        return SignalRecipient.anyFetch(sql: sql, arguments: [uuidString], transaction: transaction.asAnyRead)
    }

    fileprivate func signalRecipientForPhoneNumber(_ phoneNumber: String?, transaction: GRDBReadTransaction) -> SignalRecipient? {
        guard let phoneNumber = phoneNumber else { return nil }
        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(signalRecipientColumn: .phoneNumber) = ?"
        return SignalRecipient.anyFetch(sql: sql, arguments: [phoneNumber], transaction: transaction.asAnyRead)
    }

    func signalRecipients(for addresses: [SignalServiceAddress], transaction tx: GRDBReadTransaction) -> [SignalRecipient] {
        guard !addresses.isEmpty else { return [] }

        let phoneNumbersToLookup = addresses.compactMap { $0.phoneNumber }.map { "'\($0)'" }.joined(separator: ",")
        let uuidsToLookup = addresses.compactMap { $0.uuidString }.map { "'\($0)'" }.joined(separator: ",")

        let sql = """
            SELECT * FROM \(SignalRecipient.databaseTableName)
            WHERE \(signalRecipientColumn: .phoneNumber) IN (\(phoneNumbersToLookup))
            OR \(signalRecipientColumn: .serviceIdString) IN (\(uuidsToLookup))
        """

        var result = [SignalRecipient]()
        SignalRecipient.anyEnumerate(transaction: tx.asAnyRead, sql: sql, arguments: []) { signalRecipient, _ in
            result.append(signalRecipient)
        }
        return result
    }
}
