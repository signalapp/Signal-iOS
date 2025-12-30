//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension SDSCodableModelDatabaseInterfaceImpl {

    /// Remove a model from the database.
    func removeModel<Model: SDSCodableModel>(
        _ model: Model,
        transaction: DBWriteTransaction,
    ) {
        guard model.shouldBeSaved else {
            Logger.warn("Skipping delete of \(Model.self).")
            return
        }

        model.anyWillRemove(transaction: transaction)

        removeModelFromDatabase(model, transaction: transaction)

        model.anyDidRemove(transaction: transaction)
    }

    private func removeModelFromDatabase<Model: SDSCodableModel>(
        _ model: Model,
        transaction: DBWriteTransaction,
    ) {
        failIfThrows {
            let sql: String = """
                DELETE FROM \(Model.databaseTableName.quotedDatabaseIdentifier)
                WHERE uniqueId = ?
            """

            let statement = try transaction.database.cachedStatement(sql: sql)
            try statement.setArguments([model.uniqueId])
            try statement.execute()
        }
    }
}
