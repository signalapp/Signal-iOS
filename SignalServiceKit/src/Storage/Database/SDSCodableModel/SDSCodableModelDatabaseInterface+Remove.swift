//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension SDSCodableModelDatabaseInterfaceImpl {

    /// Remove a model from the database.
    func removeModel<Model: SDSCodableModel>(
        _ model: Model,
        transaction: DBWriteTransaction
    ) {
        let transaction = SDSDB.shimOnlyBridge(transaction)

        guard model.shouldBeSaved else {
            Logger.warn("Skipping delete of \(Model.self).")
            return
        }

        model.anyWillRemove(transaction: transaction)

        removeModelFromDatabase(model, transaction: transaction.unwrapGrdbWrite)

        model.anyDidRemove(transaction: transaction)

        if Model.ftsIndexMode != .never {
            FullTextSearchFinder.modelWasRemoved(model: model, transaction: transaction)
        }
    }

    func removeAllModelsWithInstantiation<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBWriteTransaction
    ) {
        let transaction = SDSDB.shimOnlyBridge(transaction)

        var uniqueIdsToRemove = [String]()
        modelType.anyEnumerateUniqueIds(transaction: transaction) { uniqueId, _ in
            uniqueIdsToRemove.append(uniqueId)
        }

        var index: Int = 0
        Batching.loop(batchSize: Batching.kDefaultBatchSize) { stop in
            guard index < uniqueIdsToRemove.count else {
                stop.pointee = true
                return
            }

            let uniqueIdToRemove = uniqueIdsToRemove[index]

            index += 1

            guard let instanceToRemove: Model = fetchModel(
                modelType: modelType,
                uniqueId: uniqueIdToRemove,
                transaction: transaction.asV2Write
            ) else {
                owsFailDebug("Missing instance!")
                return
            }

            removeModel(instanceToRemove, transaction: transaction.asV2Write)
        }

        if modelType.ftsIndexMode != .never {
            FullTextSearchFinder.allModelsWereRemoved(
                collection: modelType.collection(),
                transaction: transaction
            )
        }
    }

    private func removeModelFromDatabase<Model: SDSCodableModel>(
        _ model: Model,
        transaction: GRDBWriteTransaction
    ) {
        do {
            let sql: String = """
                DELETE FROM \(Model.databaseTableName.quotedDatabaseIdentifier)
                WHERE uniqueId = ?
            """

            let statement = try transaction.database.cachedStatement(sql: sql)
            try statement.setArguments([model.uniqueId])
            try statement.execute()
        } catch let error {
            DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )

            owsFail("Delete failed: \(error.grdbErrorForLogging)")
        }
    }
}
