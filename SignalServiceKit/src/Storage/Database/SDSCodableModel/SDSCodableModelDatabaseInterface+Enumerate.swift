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

        var batchSize: UInt
        switch batchingPreference {
        case .batched(let size):
            batchSize = size
        case .unbatched:
            batchSize = 0
        }

        enumerateModels(
            modelType: modelType,
            transaction: transaction,
            batchSize: batchSize,
            block: block
        )
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
        batchSize: UInt,
        block: @escaping (Model, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        do {
            let cursor = try modelType.fetchCursor(transaction.unwrapGrdbRead.database)

            try Batching.loop(batchSize: batchSize) { stop in
                guard let value = try cursor.next() else {
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
