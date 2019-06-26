//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol SignalRecipientFinder {
    associatedtype ReadTransaction

    func signalRecipient(for address: SignalServiceAddress, transaction: ReadTransaction) -> SignalRecipient?
}

@objc
public class AnySignalRecipientFinder: NSObject {
    typealias ReadTransaction = SDSAnyReadTransaction

    let grdbAdapter = GRDBSignalRecipientFinder()
    let yapdbAdapter = YAPDBSignalRecipientFinder()
}

extension AnySignalRecipientFinder: SignalRecipientFinder {
    @objc(signalRecipientForAddress:transaction:)
    func signalRecipient(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalRecipient? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalRecipient(for: address, transaction: transaction)
        case .yapRead(let transaction):
            return yapdbAdapter.signalRecipient(for: address, transaction: transaction)
        }
    }
}

@objc
class GRDBSignalRecipientFinder: NSObject, SignalRecipientFinder {
    typealias ReadTransaction = GRDBReadTransaction

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

@objc
class YAPDBSignalRecipientFinder: NSObject, SignalRecipientFinder {
    typealias ReadTransaction = YapDatabaseReadTransaction

    private static let uuidColumn = "recipient_uuid"
    private static let phoneNumberColumn = "recipient_phone_number"
    private static let phoneNumberIndex = "index_signal_recipients_on_recipientPhoneNumber"
    private static let uuidIndex = "index_signal_recipients_on_recipientUUID"

    func signalRecipient(for address: SignalServiceAddress, transaction: YapDatabaseReadTransaction) -> SignalRecipient? {
        if let recipient = signalRecipientForUUID(address.uuid, transaction: transaction) {
            return recipient
        } else if let recipient = signalRecipientForPhoneNumber(address.phoneNumber, transaction: transaction) {
            return recipient
        } else {
            return nil
        }
    }

    private func signalRecipientForUUID(_ uuid: UUID?, transaction: YapDatabaseReadTransaction) -> SignalRecipient? {
        guard let uuidString = uuid?.uuidString else { return nil }

        guard let ext = transaction.ext(YAPDBSignalRecipientFinder.uuidIndex) as? YapDatabaseSecondaryIndexTransaction else {
            owsFailDebug("Unexpected transaction type for extension")
            return nil
        }

        let queryFormat = String(format: "WHERE %@ = \"%@\"", YAPDBSignalRecipientFinder.uuidColumn, uuidString)
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var matchedAccount: SignalRecipient?

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stop in
            guard let recipient = object as? SignalRecipient else {
                owsFailDebug("Unexpected object type \(type(of: object))")
                return
            }
            matchedAccount = recipient
            stop.pointee = true
        }

        return matchedAccount
    }

    private func signalRecipientForPhoneNumber(_ phoneNumber: String?, transaction: YapDatabaseReadTransaction) -> SignalRecipient? {
        guard let phoneNumber = phoneNumber else { return nil }

        guard let ext = transaction.ext(YAPDBSignalRecipientFinder.phoneNumberIndex) as? YapDatabaseSecondaryIndexTransaction else {
            owsFailDebug("Unexpected transaction type for extension")
            return nil
        }

        let queryFormat = String(format: "WHERE %@ = \"%@\"", YAPDBSignalRecipientFinder.phoneNumberColumn, phoneNumber)
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var matchedAccount: SignalRecipient?

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stop in
            guard let recipient = object as? SignalRecipient else {
                owsFailDebug("Unexpected object type \(type(of: object))")
                return
            }
            matchedAccount = recipient
            stop.pointee = true
        }

        return matchedAccount
    }

    @objc
    static func asyncRegisterDatabaseExtensions(_ storage: OWSStorage) {
        storage.asyncRegister(indexUUIDExtension(), withName: uuidIndex)
        storage.asyncRegister(indexPhoneNumberExtension(), withName: phoneNumberIndex)
    }

    private static func indexUUIDExtension() -> YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(uuidColumn, with: .text)

        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { _, dict, _, _, object in
            guard let recipient = object as? SignalRecipient else {
                return
            }

            dict[uuidColumn] = recipient.recipientUUID
        }

        return YapDatabaseSecondaryIndex(setup: setup, handler: handler, versionTag: "1")
    }

    private static func indexPhoneNumberExtension() -> YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(phoneNumberColumn, with: .text)

        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { _, dict, _, _, object in
            guard let recipient = object as? SignalRecipient else {
                return
            }

            dict[phoneNumberColumn] = recipient.recipientPhoneNumber
        }

        return YapDatabaseSecondaryIndex(setup: setup, handler: handler, versionTag: "1")
    }
}
