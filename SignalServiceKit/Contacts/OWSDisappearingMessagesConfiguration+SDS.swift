//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

// NOTE: This file is generated by /Scripts/sds_codegen/sds_generate.py.
// Do not manually edit it, instead run `sds_codegen.sh`.

// MARK: - Record

public struct DisappearingMessagesConfigurationRecord: SDSRecord {
    public weak var delegate: SDSRecordDelegate?

    public var tableMetadata: SDSTableMetadata {
        OWSDisappearingMessagesConfigurationSerializer.table
    }

    public static var databaseTableName: String {
        OWSDisappearingMessagesConfigurationSerializer.table.tableName
    }

    public var id: Int64?

    // This defines all of the columns used in the table
    // where this model (and any subclasses) are persisted.
    public let recordType: SDSRecordType
    public let uniqueId: String

    // Properties
    public let durationSeconds: UInt32
    public let enabled: Bool
    public let timerVersion: UInt32

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case durationSeconds
        case enabled
        case timerVersion
    }

    public static func columnName(_ column: DisappearingMessagesConfigurationRecord.CodingKeys, fullyQualified: Bool = false) -> String {
        fullyQualified ? "\(databaseTableName).\(column.rawValue)" : column.rawValue
    }

    public func didInsert(with rowID: Int64, for column: String?) {
        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            return
        }
        delegate.updateRowId(rowID)
    }
}

// MARK: - Row Initializer

public extension DisappearingMessagesConfigurationRecord {
    static var databaseSelection: [SQLSelectable] {
        CodingKeys.allCases
    }

    init(row: Row) {
        id = row[0]
        recordType = row[1]
        uniqueId = row[2]
        durationSeconds = row[3]
        enabled = row[4]
        timerVersion = row[5]
    }
}

// MARK: - StringInterpolation

public extension String.StringInterpolation {
    mutating func appendInterpolation(disappearingMessagesConfigurationColumn column: DisappearingMessagesConfigurationRecord.CodingKeys) {
        appendLiteral(DisappearingMessagesConfigurationRecord.columnName(column))
    }
    mutating func appendInterpolation(disappearingMessagesConfigurationColumnFullyQualified column: DisappearingMessagesConfigurationRecord.CodingKeys) {
        appendLiteral(DisappearingMessagesConfigurationRecord.columnName(column, fullyQualified: true))
    }
}

// MARK: - Deserialization

extension OWSDisappearingMessagesConfiguration {
    // This method defines how to deserialize a model, given a
    // database row.  The recordType column is used to determine
    // the corresponding model class.
    class func fromRecord(_ record: DisappearingMessagesConfigurationRecord) throws -> OWSDisappearingMessagesConfiguration {

        guard let recordId = record.id else {
            throw SDSError.invalidValue()
        }

        switch record.recordType {
        case .disappearingMessagesConfiguration:

            let uniqueId: String = record.uniqueId
            let durationSeconds: UInt32 = record.durationSeconds
            let enabled: Bool = record.enabled
            let timerVersion: UInt32 = record.timerVersion

            return OWSDisappearingMessagesConfiguration(grdbId: recordId,
                                                        uniqueId: uniqueId,
                                                        durationSeconds: durationSeconds,
                                                        enabled: enabled,
                                                        timerVersion: timerVersion)

        default:
            owsFailDebug("Unexpected record type: \(record.recordType)")
            throw SDSError.invalidValue()
        }
    }
}

// MARK: - SDSModel

extension OWSDisappearingMessagesConfiguration: SDSModel {
    public var serializer: SDSSerializer {
        // Any subclass can be cast to it's superclass,
        // so the order of this switch statement matters.
        // We need to do a "depth first" search by type.
        switch self {
        default:
            return OWSDisappearingMessagesConfigurationSerializer(model: self)
        }
    }

    public func asRecord() -> SDSRecord {
        serializer.asRecord()
    }

    public var sdsTableName: String {
        DisappearingMessagesConfigurationRecord.databaseTableName
    }

    public static var table: SDSTableMetadata {
        OWSDisappearingMessagesConfigurationSerializer.table
    }
}

// MARK: - DeepCopyable

extension OWSDisappearingMessagesConfiguration: DeepCopyable {

    public func deepCopy() throws -> AnyObject {
        guard let id = self.grdbId?.int64Value else {
            throw OWSAssertionError("Model missing grdbId.")
        }

        // Any subclass can be cast to its superclass, so the order of these if
        // statements matters. We need to do a "depth first" search by type.

        do {
            let modelToCopy = self
            assert(type(of: modelToCopy) == OWSDisappearingMessagesConfiguration.self)
            let uniqueId: String = modelToCopy.uniqueId
            let durationSeconds: UInt32 = modelToCopy.durationSeconds
            let enabled: Bool = modelToCopy.isEnabled
            let timerVersion: UInt32 = modelToCopy.timerVersion

            return OWSDisappearingMessagesConfiguration(grdbId: id,
                                                        uniqueId: uniqueId,
                                                        durationSeconds: durationSeconds,
                                                        enabled: enabled,
                                                        timerVersion: timerVersion)
        }

    }
}

// MARK: - Table Metadata

extension OWSDisappearingMessagesConfigurationSerializer {

    // This defines all of the columns used in the table
    // where this model (and any subclasses) are persisted.
    static var idColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "id", columnType: .primaryKey) }
    static var recordTypeColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "recordType", columnType: .int64) }
    static var uniqueIdColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "uniqueId", columnType: .unicodeString, isUnique: true) }
    // Properties
    static var durationSecondsColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "durationSeconds", columnType: .int64) }
    static var enabledColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "enabled", columnType: .int) }
    static var timerVersionColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "timerVersion", columnType: .int64) }

    public static var table: SDSTableMetadata {
        SDSTableMetadata(
            tableName: "model_OWSDisappearingMessagesConfiguration",
            columns: [
                idColumn,
                recordTypeColumn,
                uniqueIdColumn,
                durationSecondsColumn,
                enabledColumn,
                timerVersionColumn,
            ]
        )
    }
}

// MARK: - Save/Remove/Update

@objc
public extension OWSDisappearingMessagesConfiguration {
    func anyInsert(transaction: DBWriteTransaction) {
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
    func anyUpsert(transaction: DBWriteTransaction) {
        let isInserting: Bool
        if OWSDisappearingMessagesConfiguration.anyFetch(uniqueId: uniqueId, transaction: transaction) != nil {
            isInserting = false
        } else {
            isInserting = true
        }
        sdsSave(saveMode: isInserting ? .insert : .update, transaction: transaction)
    }

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
    func anyUpdate(transaction: DBWriteTransaction, block: (OWSDisappearingMessagesConfiguration) -> Void) {

        block(self)

        // If it's not saved, we don't expect to find it in the database, and we
        // won't save any changes we make back into the database.
        guard shouldBeSaved else {
            return
        }

        guard let dbCopy = type(of: self).anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            return
        }

        // Don't apply the block twice to the same instance.
        // It's at least unnecessary and actually wrong for some blocks.
        // e.g. `block: { $0 in $0.someField++ }`
        if dbCopy !== self {
            block(dbCopy)
        }

        dbCopy.sdsSave(saveMode: .update, transaction: transaction)
    }

    // This method is an alternative to `anyUpdate(transaction:block:)` methods.
    //
    // We should generally use `anyUpdate` to ensure we're not unintentionally
    // clobbering other columns in the database when another concurrent update
    // has occurred.
    //
    // There are cases when this doesn't make sense, e.g. when  we know we've
    // just loaded the model in the same transaction. In those cases it is
    // safe and faster to do a "overwriting" update
    func anyOverwritingUpdate(transaction: DBWriteTransaction) {
        sdsSave(saveMode: .update, transaction: transaction)
    }

    func anyRemove(transaction: DBWriteTransaction) {
        sdsRemove(transaction: transaction)
    }
}

// MARK: - OWSDisappearingMessagesConfigurationCursor

@objc
public class OWSDisappearingMessagesConfigurationCursor: NSObject, SDSCursor {
    private let transaction: DBReadTransaction
    private let cursor: RecordCursor<DisappearingMessagesConfigurationRecord>?

    init(transaction: DBReadTransaction, cursor: RecordCursor<DisappearingMessagesConfigurationRecord>?) {
        self.transaction = transaction
        self.cursor = cursor
    }

    public func next() throws -> OWSDisappearingMessagesConfiguration? {
        guard let cursor = cursor else {
            return nil
        }
        guard let record = try cursor.next() else {
            return nil
        }
        return try OWSDisappearingMessagesConfiguration.fromRecord(record)
    }

    public func all() throws -> [OWSDisappearingMessagesConfiguration] {
        var result = [OWSDisappearingMessagesConfiguration]()
        while true {
            guard let model = try next() else {
                break
            }
            result.append(model)
        }
        return result
    }
}

// MARK: - Obj-C Fetch

@objc
public extension OWSDisappearingMessagesConfiguration {
    @nonobjc
    class func grdbFetchCursor(transaction: DBReadTransaction) -> OWSDisappearingMessagesConfigurationCursor {
        let database = transaction.database
        do {
            let cursor = try DisappearingMessagesConfigurationRecord.fetchCursor(database)
            return OWSDisappearingMessagesConfigurationCursor(transaction: transaction, cursor: cursor)
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFailDebug("Read failed: \(error)")
            return OWSDisappearingMessagesConfigurationCursor(transaction: transaction, cursor: nil)
        }
    }

    // Fetches a single model by "unique id".
    class func anyFetch(uniqueId: String,
                        transaction: DBReadTransaction) -> OWSDisappearingMessagesConfiguration? {
        assert(!uniqueId.isEmpty)

        let sql = "SELECT * FROM \(DisappearingMessagesConfigurationRecord.databaseTableName) WHERE \(disappearingMessagesConfigurationColumn: .uniqueId) = ?"
        return grdbFetchOne(sql: sql, arguments: [uniqueId], transaction: transaction)
    }

    // Traverses all records.
    // Records are not visited in any particular order.
    class func anyEnumerate(
        transaction: DBReadTransaction,
        block: (OWSDisappearingMessagesConfiguration, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        anyEnumerate(transaction: transaction, batched: false, block: block)
    }

    // Traverses all records.
    // Records are not visited in any particular order.
    class func anyEnumerate(
        transaction: DBReadTransaction,
        batched: Bool = false,
        block: (OWSDisappearingMessagesConfiguration, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let batchSize = batched ? Batching.kDefaultBatchSize : 0
        anyEnumerate(transaction: transaction, batchSize: batchSize, block: block)
    }

    // Traverses all records.
    // Records are not visited in any particular order.
    //
    // If batchSize > 0, the enumeration is performed in autoreleased batches.
    class func anyEnumerate(
        transaction: DBReadTransaction,
        batchSize: UInt,
        block: (OWSDisappearingMessagesConfiguration, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let cursor = OWSDisappearingMessagesConfiguration.grdbFetchCursor(transaction: transaction)
        Batching.loop(batchSize: batchSize,
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
                            })
    }

    // Traverses all records' unique ids.
    // Records are not visited in any particular order.
    class func anyEnumerateUniqueIds(
        transaction: DBReadTransaction,
        block: (String, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        anyEnumerateUniqueIds(transaction: transaction, batched: false, block: block)
    }

    // Traverses all records' unique ids.
    // Records are not visited in any particular order.
    class func anyEnumerateUniqueIds(
        transaction: DBReadTransaction,
        batched: Bool = false,
        block: (String, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let batchSize = batched ? Batching.kDefaultBatchSize : 0
        anyEnumerateUniqueIds(transaction: transaction, batchSize: batchSize, block: block)
    }

    // Traverses all records' unique ids.
    // Records are not visited in any particular order.
    //
    // If batchSize > 0, the enumeration is performed in autoreleased batches.
    class func anyEnumerateUniqueIds(
        transaction: DBReadTransaction,
        batchSize: UInt,
        block: (String, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        grdbEnumerateUniqueIds(transaction: transaction,
                                sql: """
                SELECT \(disappearingMessagesConfigurationColumn: .uniqueId)
                FROM \(DisappearingMessagesConfigurationRecord.databaseTableName)
            """,
            batchSize: batchSize,
            block: block)
    }

    // Does not order the results.
    class func anyFetchAll(transaction: DBReadTransaction) -> [OWSDisappearingMessagesConfiguration] {
        var result = [OWSDisappearingMessagesConfiguration]()
        anyEnumerate(transaction: transaction) { (model, _) in
            result.append(model)
        }
        return result
    }

    // Does not order the results.
    class func anyAllUniqueIds(transaction: DBReadTransaction) -> [String] {
        var result = [String]()
        anyEnumerateUniqueIds(transaction: transaction) { (uniqueId, _) in
            result.append(uniqueId)
        }
        return result
    }

    class func anyCount(transaction: DBReadTransaction) -> UInt {
        return DisappearingMessagesConfigurationRecord.ows_fetchCount(transaction.database)
    }

    class func anyExists(
        uniqueId: String,
        transaction: DBReadTransaction
    ) -> Bool {
        assert(!uniqueId.isEmpty)

        let sql = "SELECT EXISTS ( SELECT 1 FROM \(DisappearingMessagesConfigurationRecord.databaseTableName) WHERE \(disappearingMessagesConfigurationColumn: .uniqueId) = ? )"
        let arguments: StatementArguments = [uniqueId]
        do {
            return try Bool.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? false
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Missing instance.")
        }
    }
}

// MARK: - Swift Fetch

public extension OWSDisappearingMessagesConfiguration {
    class func grdbFetchCursor(sql: String,
                               arguments: StatementArguments = StatementArguments(),
                               transaction: DBReadTransaction) -> OWSDisappearingMessagesConfigurationCursor {
        do {
            let sqlRequest = SQLRequest<Void>(sql: sql, arguments: arguments, cached: true)
            let cursor = try DisappearingMessagesConfigurationRecord.fetchCursor(transaction.database, sqlRequest)
            return OWSDisappearingMessagesConfigurationCursor(transaction: transaction, cursor: cursor)
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFailDebug("Read failed: \(error)")
            return OWSDisappearingMessagesConfigurationCursor(transaction: transaction, cursor: nil)
        }
    }

    class func grdbFetchOne(sql: String,
                            arguments: StatementArguments = StatementArguments(),
                            transaction: DBReadTransaction) -> OWSDisappearingMessagesConfiguration? {
        assert(!sql.isEmpty)

        do {
            let sqlRequest = SQLRequest<Void>(sql: sql, arguments: arguments, cached: true)
            guard let record = try DisappearingMessagesConfigurationRecord.fetchOne(transaction.database, sqlRequest) else {
                return nil
            }

            return try OWSDisappearingMessagesConfiguration.fromRecord(record)
        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }
}

// MARK: - SDSSerializer

// The SDSSerializer protocol specifies how to insert and update the
// row that corresponds to this model.
class OWSDisappearingMessagesConfigurationSerializer: SDSSerializer {

    private let model: OWSDisappearingMessagesConfiguration
    public init(model: OWSDisappearingMessagesConfiguration) {
        self.model = model
    }

    // MARK: - Record

    func asRecord() -> SDSRecord {
        let id: Int64? = model.grdbId?.int64Value

        let recordType: SDSRecordType = .disappearingMessagesConfiguration
        let uniqueId: String = model.uniqueId

        // Properties
        let durationSeconds: UInt32 = model.durationSeconds
        let enabled: Bool = model.isEnabled
        let timerVersion: UInt32 = model.timerVersion

        return DisappearingMessagesConfigurationRecord(delegate: model, id: id, recordType: recordType, uniqueId: uniqueId, durationSeconds: durationSeconds, enabled: enabled, timerVersion: timerVersion)
    }
}
