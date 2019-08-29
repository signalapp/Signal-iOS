//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class AnyLinkedDeviceReadReceiptFinder: NSObject {
    let grdbAdapter = GRDBLinkedDeviceReadReceiptFinder()
    let yapdbAdapter = YAPDBLinkedDeviceReadReceiptFinder()
}

extension AnyLinkedDeviceReadReceiptFinder {
    @objc(linkedDeviceReadReceiptForAddress:messageIdTimestamp:transaction:)
    public func linkedDeviceReadReceipt(for address: SignalServiceAddress, andMessageIdTimestamp timestamp: UInt64, transaction: SDSAnyReadTransaction) -> OWSLinkedDeviceReadReceipt? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.linkedDeviceReadReceipt(for: address, andMessageIdTimestamp: timestamp, transaction: transaction)
        case .yapRead(let transaction):
            return yapdbAdapter.linkedDeviceReadReceipt(for: address, andMessageIdTimestamp: timestamp, transaction: transaction)
        }
    }
}

@objc
class GRDBLinkedDeviceReadReceiptFinder: NSObject {
    func linkedDeviceReadReceipt(for address: SignalServiceAddress, andMessageIdTimestamp timestamp: UInt64, transaction: GRDBReadTransaction) -> OWSLinkedDeviceReadReceipt? {
        if let thread = linkedDeviceReadReceiptForUUID(address.uuid, andMessageIdTimestamp: timestamp, transaction: transaction) {
            return thread
        } else if let thread = linkedDeviceReadReceiptForPhoneNumber(address.phoneNumber, andMessageIdTimestamp: timestamp, transaction: transaction) {
            return thread
        } else {
            return nil
        }
    }

    private func linkedDeviceReadReceiptForUUID(_ uuid: UUID?, andMessageIdTimestamp timestamp: UInt64, transaction: GRDBReadTransaction) -> OWSLinkedDeviceReadReceipt? {
        guard let uuidString = uuid?.uuidString else { return nil }
        let sql = "SELECT * FROM \(LinkedDeviceReadReceiptRecord.databaseTableName) WHERE \(linkedDeviceReadReceiptColumn: .senderUUID) = ? AND \(linkedDeviceReadReceiptColumn: .messageIdTimestamp) = ?"
        return OWSLinkedDeviceReadReceipt.grdbFetchOne(sql: sql, arguments: [uuidString, timestamp], transaction: transaction)
    }

    private func linkedDeviceReadReceiptForPhoneNumber(_ phoneNumber: String?, andMessageIdTimestamp timestamp: UInt64, transaction: GRDBReadTransaction) -> OWSLinkedDeviceReadReceipt? {
        guard let phoneNumber = phoneNumber else { return nil }
        let sql = "SELECT * FROM \(LinkedDeviceReadReceiptRecord.databaseTableName) WHERE \(linkedDeviceReadReceiptColumn: .senderPhoneNumber) = ? AND \(linkedDeviceReadReceiptColumn: .messageIdTimestamp) = ?"
        return OWSLinkedDeviceReadReceipt.grdbFetchOne(sql: sql, arguments: [phoneNumber, timestamp], transaction: transaction)
    }
}

@objc
class YAPDBLinkedDeviceReadReceiptFinder: NSObject {
    private static let uuidKey = "uuidKey"
    private static let phoneNumberKey = "phoneNumberKey"
    private static let timestampKey = "timestampKey"

    private static let phoneNumberIndexName = "index_linkedDeviceReadReceipt_on_senderPhoneNumberAndTimestamp"
    private static let uuidIndexName = "index_linkedDeviceReadReceipt_on_senderUUIDAndTimestamp"

    func linkedDeviceReadReceipt(for address: SignalServiceAddress, andMessageIdTimestamp timestamp: UInt64, transaction: YapDatabaseReadTransaction) -> OWSLinkedDeviceReadReceipt? {
        if let result = linkedDeviceReadReceiptForUUID(address.uuid, andMessageIdTimestamp: timestamp, transaction: transaction) {
            return result
        } else if let result = linkedDeviceReadReceiptForPhoneNumber(address.phoneNumber, andMessageIdTimestamp: timestamp, transaction: transaction) {
            return result
        } else {
            return nil
        }
    }

    private func linkedDeviceReadReceiptForUUID(_ uuid: UUID?, andMessageIdTimestamp timestamp: UInt64, transaction: YapDatabaseReadTransaction) -> OWSLinkedDeviceReadReceipt? {
        guard let uuidString = uuid?.uuidString else { return nil }

        guard let ext = transaction.ext(YAPDBLinkedDeviceReadReceiptFinder.uuidIndexName) as? YapDatabaseSecondaryIndexTransaction else {
            owsFailDebug("Unexpected transaction type for extension")
            return nil
        }

        let queryFormat = String(
            format: "WHERE %@ = \"%@\" AND %@ = \"%lld\"",
            YAPDBLinkedDeviceReadReceiptFinder.uuidKey,
            uuidString,
            YAPDBLinkedDeviceReadReceiptFinder.timestampKey,
            timestamp
        )
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var matchedRecord: OWSLinkedDeviceReadReceipt?

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stop in
            guard let record = object as? OWSLinkedDeviceReadReceipt else {
                return
            }
            matchedRecord = record
            stop.pointee = true
        }

        return matchedRecord
    }

    private func linkedDeviceReadReceiptForPhoneNumber(_ phoneNumber: String?, andMessageIdTimestamp timestamp: UInt64, transaction: YapDatabaseReadTransaction) -> OWSLinkedDeviceReadReceipt? {
        guard let phoneNumber = phoneNumber else { return nil }

        guard let ext = transaction.ext(YAPDBLinkedDeviceReadReceiptFinder.phoneNumberIndexName) as? YapDatabaseSecondaryIndexTransaction else {
            owsFailDebug("Unexpected transaction type for extension")
            return nil
        }

        let queryFormat = String(
            format: "WHERE %@ = \"%@\" AND %@ = \"%lld\"",
            YAPDBLinkedDeviceReadReceiptFinder.phoneNumberKey,
            phoneNumber,
            YAPDBLinkedDeviceReadReceiptFinder.timestampKey,
            timestamp
        )
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var matchedRecord: OWSLinkedDeviceReadReceipt?

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stop in
            guard let record = object as? OWSLinkedDeviceReadReceipt else {
                return
            }
            matchedRecord = record
            stop.pointee = true
        }

        return matchedRecord
    }

    @objc
    static func asyncRegisterDatabaseExtensions(_ storage: OWSStorage) {
        storage.asyncRegister(indexUUIDExtension(), withName: uuidIndexName)
        storage.asyncRegister(indexPhoneNumberExtension(), withName: phoneNumberIndexName)
    }

    private static func indexUUIDExtension() -> YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(uuidKey, with: .text)
        setup.addColumn(timestampKey, with: .integer)

        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { _, dict, _, _, object in
            guard let indexableObject = object as? OWSLinkedDeviceReadReceipt else {
                return
            }

            dict[uuidKey] = indexableObject.senderUUID
            dict[timestampKey] = indexableObject.messageIdTimestamp
        }

        return YapDatabaseSecondaryIndex(setup: setup, handler: handler, versionTag: "1")
    }

    private static func indexPhoneNumberExtension() -> YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(phoneNumberKey, with: .text)
        setup.addColumn(timestampKey, with: .integer)

        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { _, dict, _, _, object in
            guard let indexableObject = object as? OWSLinkedDeviceReadReceipt else {
                return
            }

            dict[phoneNumberKey] = indexableObject.senderPhoneNumber
            dict[timestampKey] = indexableObject.messageIdTimestamp
        }

        return YapDatabaseSecondaryIndex(setup: setup, handler: handler, versionTag: "1")
    }
}
