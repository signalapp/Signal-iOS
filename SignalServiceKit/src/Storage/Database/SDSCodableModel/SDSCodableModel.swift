//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Provides serialization for SDS models using Swift's ``Codable``.
///
/// Requires conformance to ``FetchableRecord``. Types that conform to
/// ``Decodable`` may take advantage of a default ``FetchableRecord``
/// conformance.
///
/// **This default implementation must not be used by types with inheritance**.
///
/// Types that support inheritance in which the base class wishes to conform
/// to ``SDSCodableModel`` should use
/// ``NeedsFactoryInitializationFromRecordType`` on the base class along with
/// ``FactoryInitializableFromRecordType`` on all subclasses.
///
/// See ``JobRecord`` for an example, and see below for additional context.
///
/// ---
///
/// Consider a base class conforming to ``SDSEncodableModel & Decodable``,
/// which has subclasses that override its `init(from:)`. Due to a
/// [Swift issue][0] calling static methods such as ``FetchableRecord.fetchOne``
/// in contexts where the inferrable static type is the base class will result
/// in the overridden initializer being ignored and only the base class being
/// initialized - even if the dynamic runtime type is the subclass.
///
/// This can lead to unexpected and undesirable behavior in generic contexts.
/// For example, consider the following snippet:
///
/// ```swift
/// func foo<Model: SDSCodableModel & Decodable>(model: Model) {
///     ...
///     let fetchedModel: Model = Model.fetchOne()
///     ...
/// }
///
/// class Base: SDSCodableModel { ... }
/// class Derived: Base {
///     override init(from: Decoder) throws { ... }
/// }
///
/// foo(model: Derived())
/// ```
///
/// Inside the call to `fetchOne()` (a static context), `self` will be the
/// expected dynamic type `Derived`. However, `Self.self` will be the inferred
/// static type `Base`, on which `fetchOne` is actually declared. If `fetchOne`
/// ends up using `Self` as a generic parameter, any subsequent code taking that
/// parameter will have no knowledge of `Derived`.
///
/// In the case of the real ``FetchableRecord.fetchOne`` implementation this is
/// exactly what happens; downstream code instantiates a `Self` using
/// `init(from:)`. In the example above, since `Self == Base` `fetchedModel`
/// will be of type `Base` and `Derived.init()` will never be called; this is
/// despite the fact that `type(of: model) == Derived`.
///
/// Another problematic example would include a "fetch all" scenario. Imagine
/// we have a base class `Base`, with subclasses `A`, `B`, and `C`. If we call
/// `Base.fetchAll()`, the subclass initializers will never be invoked.
/// Moreover, in this example it's not clear which initializer *should* be
/// invoked for a given fetched row.
///
/// As mentioned above, factory initialization is one pattern that allows us to
/// work around these issues and ensure subclasses are correctly initialized.
///
/// [0]: https://github.com/apple/swift/issues/61946
public protocol SDSCodableModel: Encodable, FetchableRecord, PersistableRecord, SDSIndexableModel, SDSIdentifiableModel {
    associatedtype CodingKeys: RawRepresentable<String>, CodingKey, ColumnExpression, CaseIterable
    typealias Columns = CodingKeys
    typealias RowId = Int64

    var id: RowId? { get set }

    /// For compatibility with legacy SDS codegen (see ``SDSRecord`` and
    /// friends). Subclasses should override to differentiate their records
    /// from parent classes.
    ///
    /// See ``NeedsFactoryInitializationFromRecordType`` for more details on
    /// models with inheritance, and how that intersects with `recordType`.
    ///
    /// Models using ``SDSCodableModel`` that never used codegen (i.e., were
    /// written from the start using ``SDSCodableModel``, rather than migrated)
    /// and which do not use inheritance may set this to zero. If they choose
    /// to do so, they may never in the future use inheritance.
    static var recordType: UInt { get }

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
    static func anyCount(
        transaction: SDSAnyReadTransaction
    ) -> UInt {
        SDSCodableModelDatabaseInterfaceImpl().countAllModels(
            modelType: Self.self,
            transaction: transaction.asV2Read
        )
    }

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
    static func anyFetchAll(
        transaction: SDSAnyReadTransaction
    ) -> [Self] {
        SDSCodableModelDatabaseInterfaceImpl().fetchAllModels(
            modelType: Self.self,
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
