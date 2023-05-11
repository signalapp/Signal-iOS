//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension SDSCodableModelDatabaseInterfaceImpl {

    /// Fetch a persisted model with the given unique ID, if one exists.
    func fetchModel<Model: SDSCodableModel>(
        modelType: Model.Type,
        uniqueId: String,
        transaction: DBReadTransaction
    ) -> Model? {
        owsAssertDebug(!uniqueId.isEmpty)

        let transaction = SDSDB.shimOnlyBridge(transaction)

        let grdbTransaction = transaction.unwrapGrdbRead

        do {
            let sql: String = """
                SELECT * FROM \(modelType.databaseTableName)
                WHERE uniqueId = ?
            """

            let model = try modelType.fetchOne(
                grdbTransaction.database,
                sql: sql,
                arguments: [uniqueId]
            )
            model?.anyDidFetchOne(transaction: transaction)
            return model
        } catch let error {
            owsFailDebug("Failed to fetch model \(modelType) by uniqueId: \(error)")
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
