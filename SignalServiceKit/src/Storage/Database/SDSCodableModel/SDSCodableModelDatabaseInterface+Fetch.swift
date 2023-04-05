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

            return try modelType.fetchOne(
                grdbTransaction.database,
                sql: sql,
                arguments: [uniqueId]
            )
        } catch let error {
            owsFailDebug("Failed to fetch model by uniqueId: \(error)")
            return nil
        }
    }
}
