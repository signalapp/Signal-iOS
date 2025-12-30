//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

extension SDSCodableModelDatabaseInterfaceImpl {
    /// Fetch a persisted model with the given rowid if it exists.
    func fetchModel<Model: SDSCodableModel>(
        modelType: Model.Type,
        rowId: Model.RowId,
        tx: DBReadTransaction,
    ) -> Model? {
        return fetchModel(
            modelType: modelType,
            sql: """
            SELECT * FROM \(modelType.databaseTableName) WHERE "id" = ?
            """,
            arguments: [rowId],
            transaction: tx,
        )
    }

    /// Fetch a persisted model with the given unique ID, if one exists.
    func fetchModel<Model: SDSCodableModel>(
        modelType: Model.Type,
        uniqueId: String,
        transaction: DBReadTransaction,
    ) -> Model? {
        owsAssertDebug(!uniqueId.isEmpty)

        return fetchModel(
            modelType: modelType,
            sql: "SELECT * FROM \(modelType.databaseTableName) WHERE uniqueId = ?",
            arguments: [uniqueId],
            transaction: transaction,
        )
    }

    func fetchModel<Model: SDSCodableModel>(
        modelType: Model.Type,
        sql: String,
        arguments: StatementArguments,
        transaction: DBReadTransaction,
    ) -> Model? {
        return failIfThrows {
            let model = try modelType.fetchOne(
                transaction.database,
                sql: sql,
                arguments: arguments,
            )
            model?.anyDidFetchOne(transaction: transaction)
            return model
        }
    }

    /// Fetch all persisted models of the given type.
    func fetchAllModels<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBReadTransaction,
    ) -> [Model] {
        return failIfThrows {
            let sql: String = """
                SELECT * FROM \(modelType.databaseTableName)
            """

            return try modelType.fetchAll(
                transaction.database,
                sql: sql,
            )
        }
    }

    /// Count all persisted models of the given type.
    func countAllModels<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBReadTransaction,
    ) -> UInt {
        return modelType.ows_fetchCount(transaction.database)
    }
}
