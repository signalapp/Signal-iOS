//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol SDSCodableModel: Codable, FetchableRecord, PersistableRecord, SDSIndexableModel, SDSIdentifiableModel {
    associatedtype CodingKeys: RawRepresentable, CodingKey, ColumnExpression, CaseIterable
    typealias Columns = CodingKeys
    typealias RowId = Int64

    var id: RowId? { get set }

    // For compatibility with SDSRecord. Subclasses should override
    // to differentiate their records from the parent class.
    static var recordType: UInt { get }
    var recordType: UInt { get }

    var uniqueId: String { get }

    var shouldBeSaved: Bool { get }
    static var ftsIndexMode: TSFTSIndexMode { get }

    func anyInsert(transaction: SDSAnyWriteTransaction)
    func anyRemove(transaction: SDSAnyWriteTransaction)

    func anyWillInsert(transaction: SDSAnyWriteTransaction)
    func anyDidInsert(transaction: SDSAnyWriteTransaction)
    func anyWillUpdate(transaction: SDSAnyWriteTransaction)
    func anyDidUpdate(transaction: SDSAnyWriteTransaction)
    func anyWillRemove(transaction: SDSAnyWriteTransaction)
    func anyDidRemove(transaction: SDSAnyWriteTransaction)

    static func columnName(_ column: Columns, fullyQualified: Bool) -> String

    static func anyAllUniqueIds(transaction: SDSAnyReadTransaction) -> [String]
    static func anyRemoveAllWithInstantiation(transaction: SDSAnyWriteTransaction)
}

public extension SDSCodableModel {
    static var recordType: UInt { 0 }
    var recordType: UInt { Self.recordType }

    var grdbId: NSNumber? { id.map { NSNumber(value: $0) } }

    static func collection() -> String { String(describing: self) }

    var shouldBeSaved: Bool { true }
    static var ftsIndexMode: TSFTSIndexMode { .never }

    var transactionFinalizationKey: String { "\(Self.collection()).\(uniqueId)" }

    var sdsTableName: String { Self.databaseTableName }

    func anyWillInsert(transaction: SDSAnyWriteTransaction) {}
    func anyDidInsert(transaction: SDSAnyWriteTransaction) {}
    func anyWillUpdate(transaction: SDSAnyWriteTransaction) {}
    func anyDidUpdate(transaction: SDSAnyWriteTransaction) {}
    func anyWillRemove(transaction: SDSAnyWriteTransaction) {}
    func anyDidRemove(transaction: SDSAnyWriteTransaction) {}

    static var databaseUUIDEncodingStrategy: DatabaseUUIDEncodingStrategy { .uppercaseString }
    static var databaseDateEncodingStrategy: DatabaseDateEncodingStrategy { .timeIntervalSince1970 }
    static var databaseDateDecodingStrategy: DatabaseDateDecodingStrategy { .timeIntervalSince1970 }

    mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
}

public extension SDSCodableModel where Columns.RawValue == String {
    static func columnName(_ column: Columns, fullyQualified: Bool = false) -> String {
        fullyQualified ? "\(databaseTableName).\(column.rawValue)" : column.rawValue
    }
}

public extension SDSCodableModel {
    static func anyFetch(uniqueId: String, transaction: SDSAnyReadTransaction) -> Self? {
        assert(!uniqueId.isEmpty)

        switch transaction.readTransaction {
        case .grdbRead(let grdbTransaction):
            let sql = "SELECT * FROM \(databaseTableName) WHERE uniqueId = ?"
            do {
                return try Self.fetchOne(grdbTransaction.database, sql: sql, arguments: [uniqueId])
            } catch {
                owsFailDebug("Failed to fetch by uniqueId \(error)")
                return nil
            }
        }
    }

    func anyInsert(transaction: SDSAnyWriteTransaction) {
        sdsSave(saveMode: .insert, transaction: transaction)
    }

    // Avoid this method whenever feasible.
    //
    // If the record has previously been saved, this method does an overwriting
    // update of the corresponding row, otherwise if it's a new record, this
    // method inserts a new row.
    //
    // For performance, when possible, you should explicitly specify whether
    // you are inserting or updating rather than calling this method.
    func anyUpsert(transaction: SDSAnyWriteTransaction) {
        let isInserting: Bool
        if Self.anyFetch(uniqueId: uniqueId, transaction: transaction) != nil {
            isInserting = false
        } else {
            isInserting = true
        }
        sdsSave(saveMode: isInserting ? .insert : .update, transaction: transaction)
    }

    // This method is an alternative to `anyUpdate(transaction:block:)` methods.
    //
    // We should generally use `anyUpdate` to ensure we're not unintentionally
    // clobbering other columns in the database when another concurrent update
    // has occured.
    //
    // There are cases when this doesn't make sense, e.g. when  we know we've
    // just loaded the model in the same transaction. In those cases it is
    // safe and faster to do a "overwriting" update
    func anyOverwritingUpdate(transaction: SDSAnyWriteTransaction) {
        sdsSave(saveMode: .update, transaction: transaction)
    }

    func anyRemove(transaction: SDSAnyWriteTransaction) {
        sdsRemove(transaction: transaction)
    }
}

public extension SDSCodableModel where Self: AnyObject {
    /// Get the unique ID of each stored instance of the model.
    static func anyAllUniqueIds(transaction: SDSAnyReadTransaction) -> [String] {
        var result = [String]()

        anyEnumerateUniqueIds(transaction: transaction) { uniqueId, _ in
            result.append(uniqueId)
        }

        return result
    }

    /// Remove all stored instances of the model.
    ///
    /// Note: implementation based on the SDS-codegen-ed version of this method.
    static func anyRemoveAllWithInstantiation(transaction: SDSAnyWriteTransaction) {
        // To avoid mutationDuringEnumerationException, we need
        // to remove the instances outside the enumeration.
        let uniqueIds = anyAllUniqueIds(transaction: transaction)

        var index: Int = 0
        Batching.loop(batchSize: Batching.kDefaultBatchSize,
                      loopBlock: { stop in
            guard index < uniqueIds.count else {
                stop.pointee = true
                return
            }
            let uniqueId = uniqueIds[index]
            index += 1
            guard let instance = anyFetch(uniqueId: uniqueId, transaction: transaction) else {
                owsFailDebug("Missing instance.")
                return
            }
            instance.anyRemove(transaction: transaction)
        })

        if ftsIndexMode != .never {
            FullTextSearchFinder.allModelsWereRemoved(collection: collection(), transaction: transaction)
        }
    }
}

public extension SDSCodableModel where Self: AnyObject {
    // This method is used by "updateWith..." methods.
    //
    // This model may be updated from many threads. We don't want to save
    // our local copy (this instance) since it may be out of date.  We also
    // want to avoid re-saving a model that has been deleted.  Therefore, we
    // use "updateWith..." methods to:
    //
    // a) Update a property of this instance.
    // b) If a copy of this model exists in the database, load an up-to-date copy,
    //    and update and save that copy.
    // b) If a copy of this model _DOES NOT_ exist in the database, do _NOT_ save
    //    this local instance.
    //
    // After "updateWith...":
    //
    // a) Any copy of this model in the database will have been updated.
    // b) The local property on this instance will always have been updated.
    // c) Other properties on this instance may be out of date.
    //
    // All mutable properties of this class have been made read-only to
    // prevent accidentally modifying them directly.
    //
    // This isn't a perfect arrangement, but in practice this will prevent
    // data loss and will resolve all known issues.
    func anyUpdate(transaction: SDSAnyWriteTransaction, block: (Self) -> Void) {

        block(self)

        guard let dbCopy = Self.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            return
        }

        // Don't apply the block twice to the same instance.
        // It's at least unnecessary and actually wrong for some blocks.
        // e.g. `block: { $0 in $0.someField++ }`
        if dbCopy !== self { block(dbCopy) }

        dbCopy.sdsSave(saveMode: .update, transaction: transaction)
    }
}

public extension SDSCodableModel {
    func sdsSave(saveMode: SDSSaveMode, transaction: SDSAnyWriteTransaction) {
        guard shouldBeSaved else {
            Logger.warn("Skipping save of: \(type(of: self))")
            return
        }

        switch saveMode {
        case .insert:
            anyWillInsert(transaction: transaction)
        case .update:
            anyWillUpdate(transaction: transaction)
        }

        switch transaction.writeTransaction {
        case .grdbWrite(let grdbTransaction):
            sdsSave(saveMode: saveMode, transaction: grdbTransaction)
        }

        switch saveMode {
        case .insert:
            anyDidInsert(transaction: transaction)

            if Self.ftsIndexMode != .never {
                FullTextSearchFinder().modelWasInserted(model: self, transaction: transaction)
            }
        case .update:
            anyDidUpdate(transaction: transaction)

            if Self.ftsIndexMode == .always {
                FullTextSearchFinder().modelWasUpdated(model: self, transaction: transaction)
            }
        }
    }

    func sdsRemove(transaction: SDSAnyWriteTransaction) {
        guard shouldBeSaved else {
            // Skipping remove.
            return
        }

        anyWillRemove(transaction: transaction)

        switch transaction.writeTransaction {
        case .grdbWrite(let grdbTransaction):
            sdsRemove(transaction: grdbTransaction)
        }

        anyDidRemove(transaction: transaction)

        if Self.ftsIndexMode != .never {
            FullTextSearchFinder().modelWasRemoved(model: self, transaction: transaction)
        }
    }
}

fileprivate extension SDSCodableModel {
    static func grdbIdForUniqueId(_ uniqueId: String, transaction: GRDBReadTransaction) -> RowId? {
        do {
            let sql = "SELECT id FROM \(databaseTableName.quotedDatabaseIdentifier) WHERE uniqueId = ?"
            guard let value = try RowId.fetchOne(transaction.database, sql: sql, arguments: [uniqueId]) else {
                return nil
            }
            return value
        } catch {
            owsFailDebug("Could not find grdbId for uniqueId: \(error)")
            return nil
        }
    }

    // This is a "fault-tolerant" save method that will upsert in production.
    // In DEBUG builds it will fail if the intention (insert v. update)
    // doesn't match the database contents.
    func sdsSave(saveMode: SDSSaveMode, transaction: GRDBWriteTransaction) {
        // Verify that the record we're trying to save wasn't removed from the database.
        if let grdbId = Self.grdbIdForUniqueId(uniqueId, transaction: transaction) {
            if saveMode == .insert {
                owsFailDebug("Could not insert existing record.")
            }
            sdsUpdate(grdbId: grdbId, transaction: transaction)
        } else {
            if saveMode == .update {
                owsFailDebug("Could not update missing record.")
            }
            sdsInsert(transaction: transaction)
        }
    }

    private func sdsUpdate(grdbId: Int64, transaction: GRDBWriteTransaction) {
        do {
            var recordCopy = self
            recordCopy.id = grdbId
            try recordCopy.update(transaction.database)
        } catch {
            DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Update failed: \(error.grdbErrorForLogging)")
        }
    }

    private func sdsInsert(transaction: GRDBWriteTransaction) {
        do {
            try self.insert(transaction.database)
        } catch {
            DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Insert failed: \(error.grdbErrorForLogging)")
        }
    }

    func sdsRemove(transaction: GRDBWriteTransaction) {
        do {
            let sql: String = """
                DELETE FROM \(Self.databaseTableName.quotedDatabaseIdentifier)
                WHERE uniqueId = ?
            """

            let statement = try transaction.database.cachedStatement(sql: sql)
            guard let arguments = StatementArguments([uniqueId]) else {
                owsFail("Could not convert values.")
            }
            // TODO: We could use setArgumentsWithValidation for more safety.
            statement.setUncheckedArguments(arguments)
            try statement.execute()
        } catch {
            DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Write failed: \(error.grdbErrorForLogging)")
        }
    }
}

public extension SDSCodableModel {
    // Traverses all records.
    // Records are not visited in any particular order.
    static func anyEnumerate(
        transaction: SDSAnyReadTransaction,
        block: @escaping (Self, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        anyEnumerate(transaction: transaction, batched: false, block: block)
    }

    // Traverses all records.
    // Records are not visited in any particular order.
    static func anyEnumerate(
        transaction: SDSAnyReadTransaction,
        batched: Bool = false,
        block: @escaping (Self, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let batchSize = batched ? Batching.kDefaultBatchSize : 0
        anyEnumerate(transaction: transaction, batchSize: batchSize, block: block)
    }

    // Traverses all records.
    // Records are not visited in any particular order.
    //
    // If batchSize > 0, the enumeration is performed in autoreleased batches.
    static func anyEnumerate(
        transaction: SDSAnyReadTransaction,
        batchSize: UInt,
        block: @escaping (Self, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let cursor: RecordCursor<Self>
        do {
            cursor = try Self.fetchCursor(transaction.unwrapGrdbRead.database)
        } catch {
            owsFailDebug("Couldn't fetch cursor \(error)")
            return
        }

        Batching.loop(
            batchSize: batchSize,
            loopBlock: { stop in
                do {
                    guard let value = try cursor.next() else {
                        stop.pointee = true
                        return
                    }
                    block(value, stop)
                } catch let error {
                    owsFailDebug("Couldn't fetch model: \(error)")
                }
            }
        )
    }

    static func anyEnumerateIndexable(
        transaction: SDSAnyReadTransaction,
        block: @escaping (SDSIndexableModel) -> Void
    ) {
        anyEnumerate(transaction: transaction, batched: false) { model, _ in
            block(model)
        }
    }

    // Traverses all records' unique ids.
    // Records are not visited in any particular order.
    static func anyEnumerateUniqueIds(
        transaction: SDSAnyReadTransaction,
        block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        anyEnumerateUniqueIds(transaction: transaction, batched: false, block: block)
    }

    // Traverses all records' unique ids.
    // Records are not visited in any particular order.
    static func anyEnumerateUniqueIds(
        transaction: SDSAnyReadTransaction,
        batched: Bool = false,
        block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let batchSize = batched ? Batching.kDefaultBatchSize : 0
        anyEnumerateUniqueIds(transaction: transaction, batchSize: batchSize, block: block)
    }

    // Traverses all records' unique ids.
    // Records are not visited in any particular order.
    //
    // If batchSize > 0, the enumeration is performed in autoreleased batches.
    static func anyEnumerateUniqueIds(
        transaction: SDSAnyReadTransaction,
        batchSize: UInt,
        block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        do {
            let cursor = try String.fetchCursor(
                transaction.unwrapGrdbRead.database,
                sql: "SELECT uniqueId FROM \(databaseTableName)"
            )
            try Batching.loop(
                batchSize: batchSize,
                loopBlock: { stop in
                    guard let uniqueId = try cursor.next() else {
                        stop.pointee = true
                        return
                    }
                    block(uniqueId, stop)
                }
            )
        } catch let error as NSError {
            owsFailDebug("Couldn't fetch uniqueIds: \(error)")
        }
    }
}
