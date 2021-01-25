//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SignalCoreKit

// NOTE: This file is generated by /Scripts/sds_codegen/sds_generate.py.
// Do not manually edit it, instead run `sds_codegen.sh`.

// MARK: - Record

public struct ReactionRecord: SDSRecord {
    public weak var delegate: SDSRecordDelegate?

    public var tableMetadata: SDSTableMetadata {
        return OWSReactionSerializer.table
    }

    public static let databaseTableName: String = OWSReactionSerializer.table.tableName

    public var id: Int64?

    // This defines all of the columns used in the table
    // where this model (and any subclasses) are persisted.
    public let recordType: SDSRecordType
    public let uniqueId: String

    // Properties
    public let emoji: String
    public let reactorE164: String?
    public let reactorUUID: String?
    public let receivedAtTimestamp: UInt64
    public let sentAtTimestamp: UInt64
    public let uniqueMessageId: String
    public let read: Bool

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case emoji
        case reactorE164
        case reactorUUID
        case receivedAtTimestamp
        case sentAtTimestamp
        case uniqueMessageId
        case read
    }

    public static func columnName(_ column: ReactionRecord.CodingKeys, fullyQualified: Bool = false) -> String {
        return fullyQualified ? "\(databaseTableName).\(column.rawValue)" : column.rawValue
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

public extension ReactionRecord {
    static var databaseSelection: [SQLSelectable] {
        return CodingKeys.allCases
    }

    init(row: Row) {
        id = row[0]
        recordType = row[1]
        uniqueId = row[2]
        emoji = row[3]
        reactorE164 = row[4]
        reactorUUID = row[5]
        receivedAtTimestamp = row[6]
        sentAtTimestamp = row[7]
        uniqueMessageId = row[8]
        read = row[9]
    }
}

// MARK: - StringInterpolation

public extension String.StringInterpolation {
    mutating func appendInterpolation(reactionColumn column: ReactionRecord.CodingKeys) {
        appendLiteral(ReactionRecord.columnName(column))
    }
    mutating func appendInterpolation(reactionColumnFullyQualified column: ReactionRecord.CodingKeys) {
        appendLiteral(ReactionRecord.columnName(column, fullyQualified: true))
    }
}

// MARK: - Deserialization

// TODO: Rework metadata to not include, for example, columns, column indices.
extension OWSReaction {
    // This method defines how to deserialize a model, given a
    // database row.  The recordType column is used to determine
    // the corresponding model class.
    class func fromRecord(_ record: ReactionRecord) throws -> OWSReaction {

        guard let recordId = record.id else {
            throw SDSError.invalidValue
        }

        switch record.recordType {
        case .reaction:

            let uniqueId: String = record.uniqueId
            let emoji: String = record.emoji
            let reactorE164: String? = record.reactorE164
            let reactorUUID: String? = record.reactorUUID
            let read: Bool = record.read
            let receivedAtTimestamp: UInt64 = record.receivedAtTimestamp
            let sentAtTimestamp: UInt64 = record.sentAtTimestamp
            let uniqueMessageId: String = record.uniqueMessageId

            return OWSReaction(grdbId: recordId,
                               uniqueId: uniqueId,
                               emoji: emoji,
                               reactorE164: reactorE164,
                               reactorUUID: reactorUUID,
                               read: read,
                               receivedAtTimestamp: receivedAtTimestamp,
                               sentAtTimestamp: sentAtTimestamp,
                               uniqueMessageId: uniqueMessageId)

        default:
            owsFailDebug("Unexpected record type: \(record.recordType)")
            throw SDSError.invalidValue
        }
    }
}

// MARK: - SDSModel

extension OWSReaction: SDSModel {
    public var serializer: SDSSerializer {
        // Any subclass can be cast to it's superclass,
        // so the order of this switch statement matters.
        // We need to do a "depth first" search by type.
        switch self {
        default:
            return OWSReactionSerializer(model: self)
        }
    }

    public func asRecord() throws -> SDSRecord {
        return try serializer.asRecord()
    }

    public var sdsTableName: String {
        return ReactionRecord.databaseTableName
    }

    public static var table: SDSTableMetadata {
        return OWSReactionSerializer.table
    }
}

// MARK: - DeepCopyable

extension OWSReaction: DeepCopyable {

    public func deepCopy() throws -> AnyObject {
        // Any subclass can be cast to it's superclass,
        // so the order of this switch statement matters.
        // We need to do a "depth first" search by type.
        guard let id = self.grdbId?.int64Value else {
            throw OWSAssertionError("Model missing grdbId.")
        }

        do {
            let modelToCopy = self
            assert(type(of: modelToCopy) == OWSReaction.self)
            let uniqueId: String = modelToCopy.uniqueId
            let emoji: String = modelToCopy.emoji
            let reactorE164: String? = modelToCopy.reactorE164
            let reactorUUID: String? = modelToCopy.reactorUUID
            let read: Bool = modelToCopy.read
            let receivedAtTimestamp: UInt64 = modelToCopy.receivedAtTimestamp
            let sentAtTimestamp: UInt64 = modelToCopy.sentAtTimestamp
            let uniqueMessageId: String = modelToCopy.uniqueMessageId

            return OWSReaction(grdbId: id,
                               uniqueId: uniqueId,
                               emoji: emoji,
                               reactorE164: reactorE164,
                               reactorUUID: reactorUUID,
                               read: read,
                               receivedAtTimestamp: receivedAtTimestamp,
                               sentAtTimestamp: sentAtTimestamp,
                               uniqueMessageId: uniqueMessageId)
        }

    }
}

// MARK: - Table Metadata

extension OWSReactionSerializer {

    // This defines all of the columns used in the table
    // where this model (and any subclasses) are persisted.
    static let idColumn = SDSColumnMetadata(columnName: "id", columnType: .primaryKey)
    static let recordTypeColumn = SDSColumnMetadata(columnName: "recordType", columnType: .int64)
    static let uniqueIdColumn = SDSColumnMetadata(columnName: "uniqueId", columnType: .unicodeString, isUnique: true)
    // Properties
    static let emojiColumn = SDSColumnMetadata(columnName: "emoji", columnType: .unicodeString)
    static let reactorE164Column = SDSColumnMetadata(columnName: "reactorE164", columnType: .unicodeString, isOptional: true)
    static let reactorUUIDColumn = SDSColumnMetadata(columnName: "reactorUUID", columnType: .unicodeString, isOptional: true)
    static let receivedAtTimestampColumn = SDSColumnMetadata(columnName: "receivedAtTimestamp", columnType: .int64)
    static let sentAtTimestampColumn = SDSColumnMetadata(columnName: "sentAtTimestamp", columnType: .int64)
    static let uniqueMessageIdColumn = SDSColumnMetadata(columnName: "uniqueMessageId", columnType: .unicodeString)
    static let readColumn = SDSColumnMetadata(columnName: "read", columnType: .int)

    // TODO: We should decide on a naming convention for
    //       tables that store models.
    public static let table = SDSTableMetadata(collection: OWSReaction.collection(),
                                               tableName: "model_OWSReaction",
                                               columns: [
        idColumn,
        recordTypeColumn,
        uniqueIdColumn,
        emojiColumn,
        reactorE164Column,
        reactorUUIDColumn,
        receivedAtTimestampColumn,
        sentAtTimestampColumn,
        uniqueMessageIdColumn,
        readColumn
        ])
}

// MARK: - Save/Remove/Update

@objc
public extension OWSReaction {
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
        if OWSReaction.anyFetch(uniqueId: uniqueId, transaction: transaction) != nil {
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
    func anyUpdate(transaction: SDSAnyWriteTransaction, block: (OWSReaction) -> Void) {

        block(self)

        guard let dbCopy = type(of: self).anyFetch(uniqueId: uniqueId,
                                                   transaction: transaction) else {
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

    func anyReload(transaction: SDSAnyReadTransaction) {
        anyReload(transaction: transaction, ignoreMissing: false)
    }

    func anyReload(transaction: SDSAnyReadTransaction, ignoreMissing: Bool) {
        guard let latestVersion = type(of: self).anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            if !ignoreMissing {
                owsFailDebug("`latest` was unexpectedly nil")
            }
            return
        }

        setValuesForKeys(latestVersion.dictionaryValue)
    }
}

// MARK: - OWSReactionCursor

@objc
public class OWSReactionCursor: NSObject {
    private let transaction: GRDBReadTransaction
    private let cursor: RecordCursor<ReactionRecord>?

    init(transaction: GRDBReadTransaction, cursor: RecordCursor<ReactionRecord>?) {
        self.transaction = transaction
        self.cursor = cursor
    }

    public func next() throws -> OWSReaction? {
        guard let cursor = cursor else {
            return nil
        }
        guard let record = try cursor.next() else {
            return nil
        }
        return try OWSReaction.fromRecord(record)
    }

    public func all() throws -> [OWSReaction] {
        var result = [OWSReaction]()
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

// TODO: We may eventually want to define some combination of:
//
// * fetchCursor, fetchOne, fetchAll, etc. (ala GRDB)
// * Optional "where clause" parameters for filtering.
// * Async flavors with completions.
//
// TODO: I've defined flavors that take a read transaction.
//       Or we might take a "connection" if we end up having that class.
@objc
public extension OWSReaction {
    class func grdbFetchCursor(transaction: GRDBReadTransaction) -> OWSReactionCursor {
        let database = transaction.database
        do {
            let cursor = try ReactionRecord.fetchCursor(database)
            return OWSReactionCursor(transaction: transaction, cursor: cursor)
        } catch {
            owsFailDebug("Read failed: \(error)")
            return OWSReactionCursor(transaction: transaction, cursor: nil)
        }
    }

    // Fetches a single model by "unique id".
    class func anyFetch(uniqueId: String,
                        transaction: SDSAnyReadTransaction) -> OWSReaction? {
        assert(uniqueId.count > 0)

        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            return OWSReaction.ydb_fetch(uniqueId: uniqueId, transaction: ydbTransaction)
        case .grdbRead(let grdbTransaction):
            let sql = "SELECT * FROM \(ReactionRecord.databaseTableName) WHERE \(reactionColumn: .uniqueId) = ?"
            return grdbFetchOne(sql: sql, arguments: [uniqueId], transaction: grdbTransaction)
        }
    }

    // Traverses all records.
    // Records are not visited in any particular order.
    class func anyEnumerate(transaction: SDSAnyReadTransaction,
                            block: @escaping (OWSReaction, UnsafeMutablePointer<ObjCBool>) -> Void) {
        anyEnumerate(transaction: transaction, batched: false, block: block)
    }

    // Traverses all records.
    // Records are not visited in any particular order.
    class func anyEnumerate(transaction: SDSAnyReadTransaction,
                            batched: Bool = false,
                            block: @escaping (OWSReaction, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let batchSize = batched ? Batching.kDefaultBatchSize : 0
        anyEnumerate(transaction: transaction, batchSize: batchSize, block: block)
    }

    // Traverses all records.
    // Records are not visited in any particular order.
    //
    // If batchSize > 0, the enumeration is performed in autoreleased batches.
    class func anyEnumerate(transaction: SDSAnyReadTransaction,
                            batchSize: UInt,
                            block: @escaping (OWSReaction, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            OWSReaction.ydb_enumerateCollectionObjects(with: ydbTransaction) { (object, stop) in
                guard let value = object as? OWSReaction else {
                    owsFailDebug("unexpected object: \(type(of: object))")
                    return
                }
                block(value, stop)
            }
        case .grdbRead(let grdbTransaction):
            do {
                let cursor = OWSReaction.grdbFetchCursor(transaction: grdbTransaction)
                try Batching.loop(batchSize: batchSize,
                                  loopBlock: { stop in
                                      guard let value = try cursor.next() else {
                                        stop.pointee = true
                                        return
                                      }
                                      block(value, stop)
                })
            } catch let error {
                owsFailDebug("Couldn't fetch models: \(error)")
            }
        }
    }

    // Traverses all records' unique ids.
    // Records are not visited in any particular order.
    class func anyEnumerateUniqueIds(transaction: SDSAnyReadTransaction,
                                     block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        anyEnumerateUniqueIds(transaction: transaction, batched: false, block: block)
    }

    // Traverses all records' unique ids.
    // Records are not visited in any particular order.
    class func anyEnumerateUniqueIds(transaction: SDSAnyReadTransaction,
                                     batched: Bool = false,
                                     block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let batchSize = batched ? Batching.kDefaultBatchSize : 0
        anyEnumerateUniqueIds(transaction: transaction, batchSize: batchSize, block: block)
    }

    // Traverses all records' unique ids.
    // Records are not visited in any particular order.
    //
    // If batchSize > 0, the enumeration is performed in autoreleased batches.
    class func anyEnumerateUniqueIds(transaction: SDSAnyReadTransaction,
                                     batchSize: UInt,
                                     block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            ydbTransaction.enumerateKeys(inCollection: OWSReaction.collection()) { (uniqueId, stop) in
                block(uniqueId, stop)
            }
        case .grdbRead(let grdbTransaction):
            grdbEnumerateUniqueIds(transaction: grdbTransaction,
                                   sql: """
                    SELECT \(reactionColumn: .uniqueId)
                    FROM \(ReactionRecord.databaseTableName)
                """,
                batchSize: batchSize,
                block: block)
        }
    }

    // Does not order the results.
    class func anyFetchAll(transaction: SDSAnyReadTransaction) -> [OWSReaction] {
        var result = [OWSReaction]()
        anyEnumerate(transaction: transaction) { (model, _) in
            result.append(model)
        }
        return result
    }

    // Does not order the results.
    class func anyAllUniqueIds(transaction: SDSAnyReadTransaction) -> [String] {
        var result = [String]()
        anyEnumerateUniqueIds(transaction: transaction) { (uniqueId, _) in
            result.append(uniqueId)
        }
        return result
    }

    class func anyCount(transaction: SDSAnyReadTransaction) -> UInt {
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            return ydbTransaction.numberOfKeys(inCollection: OWSReaction.collection())
        case .grdbRead(let grdbTransaction):
            return ReactionRecord.ows_fetchCount(grdbTransaction.database)
        }
    }

    // WARNING: Do not use this method for any models which do cleanup
    //          in their anyWillRemove(), anyDidRemove() methods.
    class func anyRemoveAllWithoutInstantation(transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite(let ydbTransaction):
            ydbTransaction.removeAllObjects(inCollection: OWSReaction.collection())
        case .grdbWrite(let grdbTransaction):
            do {
                try ReactionRecord.deleteAll(grdbTransaction.database)
            } catch {
                owsFailDebug("deleteAll() failed: \(error)")
            }
        }

        if shouldBeIndexedForFTS {
            FullTextSearchFinder.allModelsWereRemoved(collection: collection(), transaction: transaction)
        }
    }

    class func anyRemoveAllWithInstantation(transaction: SDSAnyWriteTransaction) {
        // To avoid mutationDuringEnumerationException, we need
        // to remove the instances outside the enumeration.
        let uniqueIds = anyAllUniqueIds(transaction: transaction)

        var index: Int = 0
        do {
            try Batching.loop(batchSize: Batching.kDefaultBatchSize,
                              loopBlock: { stop in
                                  guard index < uniqueIds.count else {
                                    stop.pointee = true
                                    return
                                  }
                                  let uniqueId = uniqueIds[index]
                                  index = index + 1
                                  guard let instance = anyFetch(uniqueId: uniqueId, transaction: transaction) else {
                                      owsFailDebug("Missing instance.")
                                      return
                                  }
                                  instance.anyRemove(transaction: transaction)
            })
        } catch {
            owsFailDebug("Error: \(error)")
        }

        if shouldBeIndexedForFTS {
            FullTextSearchFinder.allModelsWereRemoved(collection: collection(), transaction: transaction)
        }
    }

    class func anyExists(uniqueId: String,
                        transaction: SDSAnyReadTransaction) -> Bool {
        assert(uniqueId.count > 0)

        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            return ydbTransaction.hasObject(forKey: uniqueId, inCollection: OWSReaction.collection())
        case .grdbRead(let grdbTransaction):
            let sql = "SELECT EXISTS ( SELECT 1 FROM \(ReactionRecord.databaseTableName) WHERE \(reactionColumn: .uniqueId) = ? )"
            let arguments: StatementArguments = [uniqueId]
            return try! Bool.fetchOne(grdbTransaction.database, sql: sql, arguments: arguments) ?? false
        }
    }
}

// MARK: - Swift Fetch

public extension OWSReaction {
    class func grdbFetchCursor(sql: String,
                               arguments: StatementArguments = StatementArguments(),
                               transaction: GRDBReadTransaction) -> OWSReactionCursor {
        do {
            let sqlRequest = SQLRequest<Void>(sql: sql, arguments: arguments, cached: true)
            let cursor = try ReactionRecord.fetchCursor(transaction.database, sqlRequest)
            return OWSReactionCursor(transaction: transaction, cursor: cursor)
        } catch {
            Logger.error("sql: \(sql)")
            owsFailDebug("Read failed: \(error)")
            return OWSReactionCursor(transaction: transaction, cursor: nil)
        }
    }

    class func grdbFetchOne(sql: String,
                            arguments: StatementArguments = StatementArguments(),
                            transaction: GRDBReadTransaction) -> OWSReaction? {
        assert(sql.count > 0)

        do {
            let sqlRequest = SQLRequest<Void>(sql: sql, arguments: arguments, cached: true)
            guard let record = try ReactionRecord.fetchOne(transaction.database, sqlRequest) else {
                return nil
            }

            return try OWSReaction.fromRecord(record)
        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }
}

// MARK: - SDSSerializer

// The SDSSerializer protocol specifies how to insert and update the
// row that corresponds to this model.
class OWSReactionSerializer: SDSSerializer {

    private let model: OWSReaction
    public required init(model: OWSReaction) {
        self.model = model
    }

    // MARK: - Record

    func asRecord() throws -> SDSRecord {
        let id: Int64? = model.grdbId?.int64Value

        let recordType: SDSRecordType = .reaction
        let uniqueId: String = model.uniqueId

        // Properties
        let emoji: String = model.emoji
        let reactorE164: String? = model.reactorE164
        let reactorUUID: String? = model.reactorUUID
        let receivedAtTimestamp: UInt64 = model.receivedAtTimestamp
        let sentAtTimestamp: UInt64 = model.sentAtTimestamp
        let uniqueMessageId: String = model.uniqueMessageId
        let read: Bool = model.read

        return ReactionRecord(delegate: model, id: id, recordType: recordType, uniqueId: uniqueId, emoji: emoji, reactorE164: reactorE164, reactorUUID: reactorUUID, receivedAtTimestamp: receivedAtTimestamp, sentAtTimestamp: sentAtTimestamp, uniqueMessageId: uniqueMessageId, read: read)
    }
}

// MARK: - Deep Copy

#if TESTABLE_BUILD
@objc
public extension OWSReaction {
    // We're not using this method at the moment,
    // but we might use it for validation of
    // other deep copy methods.
    func deepCopyUsingRecord() throws -> OWSReaction {
        guard let record = try asRecord() as? ReactionRecord else {
            throw OWSAssertionError("Could not convert to record.")
        }
        return try OWSReaction.fromRecord(record)
    }
}
#endif
