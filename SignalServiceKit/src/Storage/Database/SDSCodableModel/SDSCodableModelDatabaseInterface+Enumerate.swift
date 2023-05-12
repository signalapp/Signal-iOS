//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public enum BatchingPreference {
    case batched(UInt = Batching.kDefaultBatchSize)
    case unbatched
}

extension SDSCodableModelDatabaseInterfaceImpl {
    /// Traverse all records, in no particular order.
    func enumerateModels<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBReadTransaction,
        batchingPreference: BatchingPreference,
        block: @escaping (Model, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let transaction = SDSDB.shimOnlyBridge(transaction)
        let batchSize = batchSize(batchingPreference: batchingPreference)
        enumerateModels(
            modelType: modelType,
            transaction: transaction,
            sql: nil,
            arguments: nil,
            batchSize: batchSize,
            block: block
        )
    }

    /// Traverse all records, in no particular order.
    func enumerateModels<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBReadTransaction,
        sql: String,
        arguments: StatementArguments,
        batchingPreference: BatchingPreference,
        block: @escaping (Model, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let transaction = SDSDB.shimOnlyBridge(transaction)
        let batchSize = batchSize(batchingPreference: batchingPreference)
        enumerateModels(
            modelType: modelType,
            transaction: transaction,
            sql: sql,
            arguments: arguments,
            batchSize: batchSize,
            block: block
        )
    }

    /// The batch size for enumeration.
    private func batchSize(batchingPreference: BatchingPreference) -> UInt {
        switch batchingPreference {
        case .batched(let size):
            return size
        case .unbatched:
            return 0
        }
    }

    /// Traverse all records' unique IDs, in no particular order.
    func enumerateModelUniqueIds<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBReadTransaction,
        batched: Bool,
        block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let transaction = SDSDB.shimOnlyBridge(transaction)

        let batchSize = batched ? Batching.kDefaultBatchSize : 0
        enumerateModelUniqueIds(
            modelType: modelType,
            transaction: transaction,
            batchSize: batchSize,
            block: block
        )
    }

    /// Traverse all records, in no particular order.
    /// - Parameter batchSize
    /// If nonzero, enumeration is performed in autoreleased batches.
    private func enumerateModels<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: SDSAnyReadTransaction,
        sql: String? = nil,
        arguments: StatementArguments? = nil,
        batchSize: UInt,
        block: @escaping (Model, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        do {
            var recordCursor: RecordCursor<Model>
            if let sql = sql, let arguments = arguments {
                recordCursor = try Model.fetchCursor(
                    transaction.unwrapGrdbRead.database,
                    sql: sql,
                    arguments: arguments
                )
            } else {
                recordCursor = try modelType.fetchCursor(transaction.unwrapGrdbRead.database)
            }

            try Batching.loop(batchSize: batchSize) { stop in
                guard let value = try recordCursor.next() else {
                    stop.pointee = true
                    return
                }
                value.anyDidEnumerateOne(transaction: transaction)
                block(value, stop)
            }
        } catch let error {
            owsFailDebug("Failed to fetch models: \(error)!")
        }
    }

    /// Traverse all records' unique IDs, in no particular order.
    /// - Parameter batchSize
    /// If nonzero, enumeration is performed in autoreleased batches.
    private func enumerateModelUniqueIds<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: SDSAnyReadTransaction,
        batchSize: UInt,
        block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        do {
            let cursor = try String.fetchCursor(
                transaction.unwrapGrdbRead.database,
                sql: "SELECT uniqueId FROM \(modelType.databaseTableName)"
            )

            try Batching.loop(batchSize: batchSize) { stop in
                guard let uniqueId = try cursor.next() else {
                    stop.pointee = true
                    return
                }

                block(uniqueId, stop)
            }
        } catch let error {
            owsFailDebug("Failed to fetch uniqueIds: \(error)!")
        }
    }
}
