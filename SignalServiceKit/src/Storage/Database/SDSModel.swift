//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol SDSModel: TSYapDatabaseObject, SDSIndexableModel, SDSIdentifiableModel {
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

            if type(of: self).ftsIndexMode != .never {
                FullTextSearchFinder.modelWasInserted(model: self, transaction: transaction)
            }
        case .update:
            anyDidUpdate(with: transaction)

            if type(of: self).ftsIndexMode == .always {
                FullTextSearchFinder.modelWasUpdated(model: self, transaction: transaction)
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
        case .grdbWrite(let grdbTransaction):
            // Don't use a record to delete the record;
            // asRecord() is expensive.
            let sql = """
                DELETE
                FROM \(sdsTableName)
                WHERE uniqueId == ?
            """
            grdbTransaction.executeAndCacheStatement(sql: sql, arguments: [uniqueId])
        }

        anyDidRemove(with: transaction)

        if type(of: self).ftsIndexMode != .never {
            FullTextSearchFinder.modelWasRemoved(model: self, transaction: transaction)
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
    // If batchSize > 0, the enumeration is performed in autoreleased batches.
    static func grdbEnumerateUniqueIds(transaction: GRDBReadTransaction,
                                       sql: String,
                                       batchSize: UInt,
                                       block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        do {
            let cursor = try String.fetchCursor(transaction.database,
                                                sql: sql)
            try Batching.loop(batchSize: batchSize,
                              loopBlock: { stop in
                                guard let uniqueId = try cursor.next() else {
                                    stop.pointee = true
                                    return
                                }
                                block(uniqueId, stop)
            })
        } catch let error as NSError {
            owsFailDebug("Couldn't fetch uniqueIds: \(error)")
        }
    }
}

// MARK: - Cursors

public protocol SDSCursor {
    associatedtype Model: SDSModel
    mutating func next() throws -> Model?
}

public struct SDSMappedCursor<Cursor: SDSCursor, Element> {
    fileprivate var cursor: Cursor
    fileprivate let transform: (Cursor.Model) throws -> Element?

    public mutating func next() throws -> Element? {
        while let next = try cursor.next() {
            if let transformed = try transform(next) {
                return transformed
            }
        }
        return nil
    }
}

public extension SDSCursor {
    func map<Element>(transform: @escaping (Model) throws -> Element) -> SDSMappedCursor<Self, Element> {
        return compactMap(transform: transform)
    }

    func compactMap<Element>(transform: @escaping (Model) throws -> Element?) -> SDSMappedCursor<Self, Element> {
        return SDSMappedCursor(cursor: self, transform: transform)
    }
}
