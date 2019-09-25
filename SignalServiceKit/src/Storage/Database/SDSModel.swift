//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

public protocol SDSModel: TSYapDatabaseObject {
    var sdsTableName: String { get }

    func asRecord() throws -> SDSRecord

    var serializer: SDSSerializer { get }

    func anyInsert(transaction: SDSAnyWriteTransaction)

    func anyRemove(transaction: SDSAnyWriteTransaction)

    static var table: SDSTableMetadata { get }
}

// MARK: -

public extension SDSModel {
    func sdsSave(saveMode: SDSSaveMode, transaction: SDSAnyWriteTransaction) {
        guard shouldBeSaved else {
            Logger.warn("Skipping save of: \(type(of: self))")
            return
        }

        switch saveMode {
        case .insert:
            anyWillInsert(with: transaction)
        case .update:
            anyWillUpdate(with: transaction)
        }

        switch transaction.writeTransaction {
        case .yapWrite(let ydbTransaction):
            ydb_save(with: ydbTransaction)
        case .grdbWrite(let grdbTransaction):
            do {
                let record = try asRecord()
                record.sdsSave(saveMode: saveMode, transaction: grdbTransaction)
            } catch {
                owsFail("Write failed: \(error)")
            }
        }

        switch saveMode {
        case .insert:
            anyDidInsert(with: transaction)

            if type(of: self).shouldBeIndexedForFTS {
                FullTextSearchFinder().modelWasInserted(model: self, transaction: transaction)
            }
        case .update:
            anyDidUpdate(with: transaction)

            if type(of: self).shouldBeIndexedForFTS {
                FullTextSearchFinder().modelWasUpdated(model: self, transaction: transaction)
            }
        }
    }

    func sdsRemove(transaction: SDSAnyWriteTransaction) {
        guard shouldBeSaved else {
            // Skipping remove.
            return
        }

        anyWillRemove(with: transaction)

        switch transaction.writeTransaction {
        case .yapWrite(let ydbTransaction):
            ydb_remove(with: ydbTransaction)
        case .grdbWrite(let grdbTransaction):
            // Don't use a record to delete the record;
            // asRecord() is expensive.
            let sql = """
                DELETE
                FROM \(sdsTableName)
                WHERE uniqueId == ?
            """
            grdbTransaction.executeWithCachedStatement(sql: sql, arguments: [uniqueId])
        }

        anyDidRemove(with: transaction)

        if type(of: self).shouldBeIndexedForFTS {
            FullTextSearchFinder().modelWasRemoved(model: self, transaction: transaction)
        }
    }
}

// MARK: -

public extension TableRecord {
    static func ows_fetchCount(_ db: Database) -> UInt {
        do {
            let result = try fetchCount(db)
            guard result >= 0 else {
                owsFailDebug("Invalid result: \(result)")
                return 0
            }
            guard result <= UInt.max else {
                owsFailDebug("Invalid result: \(result)")
                return UInt.max
            }
            return UInt(result)
        } catch {
            owsFailDebug("Read failed: \(error)")
            return 0
        }
    }
}

// MARK: -

public extension SDSModel {
    static func grdbEnumerateUniqueIds(transaction: GRDBReadTransaction,
                                       sql: String,
                                       block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        do {
            let cursor = try String.fetchCursor(transaction.database,
                                                sql: sql)
            while let uniqueId = try cursor.next() {
                var stop: ObjCBool = false
                block(uniqueId, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch let error as NSError {
            owsFailDebug("Couldn't fetch uniqueIds: \(error)")
        }
    }
}
