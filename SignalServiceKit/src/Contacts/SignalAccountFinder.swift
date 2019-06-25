//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol SignalAccountFinder {
    associatedtype ReadTransaction

    func signalAccount(for address: SignalServiceAddress, transaction: ReadTransaction) -> SignalAccount?
}

@objc
class AnySignalAccountFinder: NSObject {
    typealias ReadTransaction = SDSAnyReadTransaction

    let grdbAdapter = GRDBSignalAccountFinder()
    let yapdbAdapter = YAPDBSignalAccountFinder()
}

extension AnySignalAccountFinder: SignalAccountFinder {
    @objc(signalAccountForAddress:transaction:)
    func signalAccount(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.signalAccount(for: address, transaction: transaction)
        case .yapRead(let transaction):
            return yapdbAdapter.signalAccount(for: address, transaction: transaction)
        }
    }
}

@objc
class GRDBSignalAccountFinder: NSObject, SignalAccountFinder {
    typealias ReadTransaction = GRDBReadTransaction

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

@objc
class YAPDBSignalAccountFinder: NSObject, SignalAccountFinder {
    typealias ReadTransaction = YapDatabaseReadTransaction

    private static let uuidColumn = "recipient_uuid"
    private static let phoneNumberColumn = "recipient_phone_number"
    private static let phoneNumberIndex = "index_signal_accounts_on_recipientPhoneNumber"
    private static let uuidIndex = "index_signal_accounts_on_recipientUUID"

    func signalAccount(for address: SignalServiceAddress, transaction: YapDatabaseReadTransaction) -> SignalAccount? {
        if let account = signalAccountForUUID(address.uuid, transaction: transaction) {
            return account
        } else if let account = signalAccountForPhoneNumber(address.phoneNumber, transaction: transaction) {
            return account
        } else {
            return nil
        }
    }

    private func signalAccountForUUID(_ uuid: UUID?, transaction: YapDatabaseReadTransaction) -> SignalAccount? {
        guard let uuidString = uuid?.uuidString else { return nil }

        guard let ext = transaction.ext(YAPDBSignalAccountFinder.uuidIndex) as? YapDatabaseSecondaryIndexTransaction else {
            owsFailDebug("Unexpected transaction type for extension")
            return nil
        }

        let queryFormat = String(format: "WHERE %@ = \"%@\"", YAPDBSignalAccountFinder.uuidColumn, uuidString)
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var matchedAccount: SignalAccount?

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stop in
            guard let account = object as? SignalAccount else {
                owsFailDebug("Unexpected object type \(type(of: object))")
                return
            }
            matchedAccount = account
            stop.pointee = true
        }

        return matchedAccount
    }

    private func signalAccountForPhoneNumber(_ phoneNumber: String?, transaction: YapDatabaseReadTransaction) -> SignalAccount? {
        guard let phoneNumber = phoneNumber else { return nil }

        guard let ext = transaction.ext(YAPDBSignalAccountFinder.phoneNumberIndex) as? YapDatabaseSecondaryIndexTransaction else {
            owsFailDebug("Unexpected transaction type for extension")
            return nil
        }

        let queryFormat = String(format: "WHERE %@ = \"%@\"", YAPDBSignalAccountFinder.phoneNumberColumn, phoneNumber)
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var matchedAccount: SignalAccount?

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stop in
            guard let account = object as? SignalAccount else {
                owsFailDebug("Unexpected object type \(type(of: object))")
                return
            }
            matchedAccount = account
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
            guard let account = object as? SignalAccount else {
                return
            }

            dict[uuidColumn] = account.recipientUUID
        }

        return YapDatabaseSecondaryIndex(setup: setup, handler: handler, versionTag: "1")
    }

    private static func indexPhoneNumberExtension() -> YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(phoneNumberColumn, with: .text)

        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { _, dict, _, _, object in
            guard let account = object as? SignalAccount else {
                return
            }

            dict[phoneNumberColumn] = account.recipientPhoneNumber
        }

        return YapDatabaseSecondaryIndex(setup: setup, handler: handler, versionTag: "1")
    }
}
