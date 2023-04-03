//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Provides de/serialization for SDS models using Swift's ``Codable``.
public protocol SDSCodableModel: Codable, FetchableRecord, PersistableRecord, SDSIndexableModel, SDSIdentifiableModel {
    associatedtype CodingKeys: RawRepresentable<String>, CodingKey, ColumnExpression, CaseIterable
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

    func anyWillInsert(transaction: SDSAnyWriteTransaction)
    func anyDidInsert(transaction: SDSAnyWriteTransaction)
    func anyWillUpdate(transaction: SDSAnyWriteTransaction)
    func anyDidUpdate(transaction: SDSAnyWriteTransaction)
    func anyWillRemove(transaction: SDSAnyWriteTransaction)
    func anyDidRemove(transaction: SDSAnyWriteTransaction)
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
        id = rowID
    }
}

public extension SDSCodableModel {
    /// Convenience method delegating to ``SDSCodableModelDatabaseInterface``.
    /// See that class for details.
    static func anyFetch(
        uniqueId: String,
        transaction: SDSAnyReadTransaction
    ) -> Self? {
        SDSCodableModelDatabaseInterfaceImpl().fetchModel(
            modelType: Self.self,
            uniqueId: uniqueId,
            transaction: transaction.asV2Read
        )
    }

    /// Convenience method delegating to ``SDSCodableModelDatabaseInterface``.
    /// See that class for details.
    func anyInsert(transaction: SDSAnyWriteTransaction) {
        SDSCodableModelDatabaseInterfaceImpl().insertModel(self, transaction: transaction.asV2Write)
    }

    /// Convenience method delegating to ``SDSCodableModelDatabaseInterface``.
    /// See that class for details.
    func anyUpsert(transaction: SDSAnyWriteTransaction) {
        SDSCodableModelDatabaseInterfaceImpl().upsertModel(self, transaction: transaction.asV2Write)
    }

    /// Convenience method delegating to ``SDSCodableModelDatabaseInterface``.
    /// See that class for details.
    func anyOverwritingUpdate(transaction: SDSAnyWriteTransaction) {
        SDSCodableModelDatabaseInterfaceImpl().overwritingUpdateModel(self, transaction: transaction.asV2Write)
    }

    /// Convenience method delegating to ``SDSCodableModelDatabaseInterface``.
    /// See that class for details.
    func anyRemove(transaction: SDSAnyWriteTransaction) {
        SDSCodableModelDatabaseInterfaceImpl().removeModel(self, transaction: transaction.asV2Write)
    }
}

public extension SDSCodableModel where Self: AnyObject {
    /// Convenience method delegating to ``SDSCodableModelDatabaseInterface``.
    /// See that class for details.
    func anyUpdate(transaction: SDSAnyWriteTransaction, block: (Self) -> Void) {
        SDSCodableModelDatabaseInterfaceImpl().updateModel(
            self,
            transaction: transaction.asV2Write,
            block: block
        )
    }

    static func anyRemoveAllWithInstantiation(transaction: SDSAnyWriteTransaction) {
        SDSCodableModelDatabaseInterfaceImpl().removeAllModelsWithInstantiation(
            modelType: Self.self,
            transaction: transaction.asV2Write
        )
    }
}

public extension SDSCodableModel {
    /// Traverse all records as ``SDSIndexableModel``s, in no particular order.
    static func anyEnumerateIndexable(
        transaction: SDSAnyReadTransaction,
        block: @escaping (SDSIndexableModel) -> Void
    ) {
        anyEnumerate(transaction: transaction, batched: false) { model, _ in
            block(model)
        }
    }

    /// Convenience method delegating to ``SDSCodableModelDatabaseInterface``.
    /// See that class for details.
    static func anyEnumerate(
        transaction: SDSAnyReadTransaction,
        batched: Bool = false,
        block: @escaping (Self, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        SDSCodableModelDatabaseInterfaceImpl().enumerateModels(
            modelType: Self.self,
            transaction: transaction.asV2Read,
            batched: batched,
            block: block
        )
    }

    /// Convenience method delegating to ``SDSCodableModelDatabaseInterface``.
    /// See that class for details.
    static func anyEnumerateUniqueIds(
        transaction: SDSAnyReadTransaction,
        batched: Bool = false,
        block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        SDSCodableModelDatabaseInterfaceImpl().enumerateModelUniqueIds(
            modelType: Self.self,
            transaction: transaction.asV2Read,
            batched: batched,
            block: block
        )
    }
}
