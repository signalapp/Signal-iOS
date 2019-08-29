//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CDSContactQueryBuilder: NSObject {
    let phoneNumbersToLookup: Set<String>

    @objc
    init(phoneNumbersToLookup: Set<String>) {
        self.phoneNumbersToLookup = phoneNumbersToLookup
    }

    @objc
    public func build(transaction: SDSAnyWriteTransaction) throws -> CDSContactQueryCollection {
        var contactQueries: [CDSContactQuery] = []
        for phoneNumber in phoneNumbersToLookup {
            if let record = OWSContactQuery.anyFetch(uniqueId: phoneNumber, transaction: transaction) {
                record.anyUpdate(transaction: transaction) {
                    $0.lastQueried = Date()
                }
                assert(record.uniqueId == phoneNumber)
                do {
                    Logger.verbose("Using existing nonce for phoneNumber: \(phoneNumber)")
                    let contactQuery = try CDSContactQuery(e164PhoneNumber: phoneNumber, nonce: record.nonce)
                    contactQueries.append(contactQuery)
                    continue
                } catch {
                    owsFailDebug("error: \(error)")

                    // remove this record, fall through, and build a new valid one
                    record.anyRemove(transaction: transaction)
                }
            }

            Logger.verbose("generating new nonce for phoneNumber: \(phoneNumber)")
            let nonce = Randomness.generateRandomBytes(CDSContactQuery.nonceLength)
            let newRecord = OWSContactQuery(uniqueId: phoneNumber, lastQueried: Date(), nonce: nonce)
            newRecord.anyInsert(transaction: transaction)

            let contactQuery = try CDSContactQuery(e164PhoneNumber: phoneNumber, nonce: nonce)
            contactQueries.append(contactQuery)
        }

        return CDSContactQueryCollection(contactQueries: contactQueries)
    }

    @objc
    public func removeStale(transaction: SDSAnyWriteTransaction) {
        let threshold: TimeInterval = kDayInterval * 14
        let referenceDate = Date(timeIntervalSinceNow: -threshold)

        for uniqueId in AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction,
                                                                 olderThan: referenceDate) {

            guard let record = OWSContactQuery.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
                owsFailDebug("record was unexpectedly nil")
                continue
            }
            record.anyRemove(transaction: transaction)
        }
    }
}

@objc
public class CDSContactQueryCollection: NSObject {
    let contactQueries: [CDSContactQuery]
    init(contactQueries: [CDSContactQuery]) {
        self.contactQueries = contactQueries
    }
}

@objc
extension LegacyContactDiscoveryOperation {
    convenience init(queryCollection: CDSContactQueryCollection) {
        self.init(contactsToLookup: queryCollection.contactQueries)
    }
}

@objc
extension ContactDiscoveryOperation {
    convenience init(queryCollection: CDSContactQueryCollection) {
        self.init(contactsToLookup: queryCollection.contactQueries)
    }
}

protocol ContactQueryFinder {
    associatedtype ReadTransaction
    static func enumerateUniqueIds(transaction: ReadTransaction,
                                   olderThan referenceDate: Date,
                                   block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void)

    static func allRecordUniqueIds(transaction: ReadTransaction,
                                   olderThan referenceDate: Date) -> [String]
}

extension ContactQueryFinder {
    static func allRecordUniqueIds(transaction: ReadTransaction,
                                   olderThan referenceDate: Date) -> [String] {
        var result: [String] = []
        enumerateUniqueIds(transaction: transaction, olderThan: referenceDate) { uniqueId, _ in
            result.append(uniqueId)
        }
        return result
    }
}

public struct AnyContactQueryFinder: ContactQueryFinder {
    static func enumerateUniqueIds(transaction: SDSAnyReadTransaction,
                                   olderThan referenceDate: Date,
                                   block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            YAPDBContactQueryFinder.enumerateUniqueIds(transaction: yapRead,
                                                     olderThan: referenceDate,
                                                     block: block)
        case .grdbRead(let grdbRead):
            GRDBContactQueryFinder.enumerateUniqueIds(transaction: grdbRead,
                                                      olderThan: referenceDate,
                                                      block: block)
        }
    }
}

@objc
public class YAPDBContactQueryFinder: NSObject, ContactQueryFinder {
    public static func enumerateUniqueIds(transaction: YapDatabaseReadTransaction,
                                          olderThan referenceDate: Date,
                                          block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {

        let query = YapDatabaseQuery(string: "WHERE '\(lastQueriedColumnName)' < ?",
            parameters: [referenceDate.timeIntervalSince1970])

        view(transaction).enumerateKeys(matching: query) { (_, key, stopPtr) in
            block(key, stopPtr)
        }
    }

    @objc
    public static func asyncRegisterDatabaseExtensions(_ storage: OWSStorage) {
        storage.asyncRegister(buildExtension(), withName: extensionName)
    }

    // MARK: - Private

    private static let extensionName = "YAPDBContactQueryFinder"
    private static func view(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseSecondaryIndexTransaction {
        return transaction.extension(extensionName) as! YapDatabaseSecondaryIndexTransaction
    }

    private static let lastQueriedColumnName = "lastQueried"

    private static func buildExtension() -> YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(lastQueriedColumnName, with: .numeric)

        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { _, dict, _, _, object in
            guard let indexableObject = object as? OWSContactQuery else {
                return
            }

            dict[lastQueriedColumnName] = indexableObject.lastQueried.timeIntervalSince1970
        }

        return YapDatabaseSecondaryIndex(setup: setup, handler: handler, versionTag: "1")
    }
}

struct GRDBContactQueryFinder: ContactQueryFinder {
    static func enumerateUniqueIds(transaction: GRDBReadTransaction,
                                   olderThan referenceDate: Date,
                                   block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let sql = """
        SELECT \(contactQueryColumn: .uniqueId)
        FROM \(ContactQueryRecord.databaseTableName)
        WHERE \(contactQueryColumn: .lastQueried) < ?
        """

        do {
            var stop: ObjCBool = false
            let cursor = try String.fetchCursor(transaction.database, sql: sql, arguments: [referenceDate])
            while !stop.boolValue, let next = try cursor.next() {
                block(next, &stop)
            }
        } catch {
            owsFailDebug("db Error: \(error)")
        }
    }
}
