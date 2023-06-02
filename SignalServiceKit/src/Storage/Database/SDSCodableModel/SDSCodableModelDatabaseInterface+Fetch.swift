//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalCoreKit

extension SDSCodableModelDatabaseInterfaceImpl {

    /// Fetch a persisted model with the given unique ID, if one exists.
    func fetchModel<Model: SDSCodableModel>(
        modelType: Model.Type,
        uniqueId: String,
        transaction: DBReadTransaction
    ) -> Model? {
        owsAssertDebug(!uniqueId.isEmpty)

        return fetchModel(
            modelType: modelType,
            sql: "SELECT * FROM \(modelType.databaseTableName) WHERE uniqueId = ?",
            arguments: [uniqueId],
            transaction: transaction
        )
    }

    func fetchModel<Model: SDSCodableModel>(
        modelType: Model.Type,
        sql: String,
        arguments: StatementArguments,
        transaction: DBReadTransaction
    ) -> Model? {
        let transaction = SDSDB.shimOnlyBridge(transaction)

        let grdbTransaction = transaction.unwrapGrdbRead

        do {
            let model = try modelType.fetchOne(
                grdbTransaction.database,
                sql: sql,
                arguments: arguments
            )
            model?.anyDidFetchOne(transaction: transaction)
            return model
        } catch let error {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFailDebug("Failed to fetch model \(modelType): \(error)")
            return nil
        }
    }

    /// Fetch all persisted models of the given type.
    func fetchAllModels<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBReadTransaction
    ) -> [Model] {
        let transaction = SDSDB.shimOnlyBridge(transaction)

        do {
            let sql: String = """
                SELECT * FROM \(modelType.databaseTableName)
            """

            return try modelType.fetchAll(
                transaction.unwrapGrdbRead.database,
                sql: sql
            )
        } catch let error {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFailDebug("Failed to fetch \(modelType) models: \(error)")
            return []
        }
    }

    /// Count all persisted models of the given type.
    func countAllModels<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBReadTransaction
    ) -> UInt {
        let transaction = SDSDB.shimOnlyBridge(transaction)

        return modelType.ows_fetchCount(transaction.unwrapGrdbRead.database)
    }
}
