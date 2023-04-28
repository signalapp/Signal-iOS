//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension SDSCodableModelDatabaseInterfaceImpl {

    /// Insert the given model to the database.
    func insertModel<Model: SDSCodableModel>(
        _ model: Model,
        transaction: DBWriteTransaction
    ) {
        let transaction = SDSDB.shimOnlyBridge(transaction)
        saveModelToDatabase(model, saveMode: .insert, transaction: transaction)
    }

    /// If a persisted record exists for this model, do an overwriting update.
    /// Otherwise, do an insertion.
    ///
    /// When possible, avoid this method in preference of an explicit insert or
    /// update.
    func upsertModel<Model: SDSCodableModel>(
        _ model: Model,
        transaction: DBWriteTransaction
    ) {
        let shouldInsert: Bool = fetchModel(
            modelType: Model.self,
            uniqueId: model.uniqueId,
            transaction: transaction
        ) == nil

        if shouldInsert {
            insertModel(model, transaction: transaction)
        } else {
            overwritingUpdateModel(model, transaction: transaction)
        }
    }

    /// Apply changes produced by the given block to the persisted copy of the
    /// given model.
    ///
    /// Used by `updateWith...` methods.
    ///
    /// This model may be updated from many threads. We don't want to save this
    /// instance, since it may be out of date. We also want to avoid re-saving
    /// a model that has been deleted. Therefore, this method:
    ///
    /// a) Updates the passed instance using the given block.
    /// b) If a copy of the model exists in the database (which will be
    ///    up-to-date), load it, update it, and save that copy.
    /// c) If a copy of the model does *not* exist in the database, do *not*
    ///    save the passed instance.
    ///
    /// Afterwards:
    ///
    /// a) Any copy of this model in the database will be updated.
    /// b) The passed instance will be updated.
    /// c) Other properties on the passed instance may be out of date.
    func updateModel<Model: SDSCodableModel & AnyObject>(
        _ model: Model,
        transaction: DBWriteTransaction,
        block: (Model) -> Void
    ) {
        block(model)

        guard let dbCopy: Model = fetchModel(
            modelType: Model.self,
            uniqueId: model.uniqueId,
            transaction: transaction
        ) else {
            return
        }

        // Don't apply the block twice to the same instance. At best it's
        // unnecessary, and at worst it's wrong: `block: { $0.someField++ }`.
        if dbCopy !== model {
            block(dbCopy)
        }

        saveModelToDatabase(dbCopy, saveMode: .update, transaction: SDSDB.shimOnlyBridge(transaction))
    }

    /// Immediately persist the given model.
    ///
    /// A faster alternative to ``updateModel(_:transaction:block:)`` that will
    /// clobber columns modified by concurrent updates.
    ///
    /// Safe to use if we are sure the model in question is up-to-date and not
    /// being updated concurrently, such as when the model was just loaded in
    /// the same transaction.
    func overwritingUpdateModel<Model: SDSCodableModel>(
        _ model: Model,
        transaction: DBWriteTransaction
    ) {
        saveModelToDatabase(model, saveMode: .update, transaction: SDSDB.shimOnlyBridge(transaction))
    }
}

// MARK: - Helpers

private extension SDSCodableModelDatabaseInterface {

    /// Get the row ID of this model if it has already been persisted.
    func existingGrdbRowId<Model: SDSCodableModel>(
        forModel model: Model,
        transaction: GRDBReadTransaction
    ) -> SDSCodableModel.RowId? {
        do {
            let databaseTableName = Model.databaseTableName.quotedDatabaseIdentifier
            let sql: String = """
                SELECT id FROM \(databaseTableName)
                WHERE uniqueId = ?
            """

            return try SDSCodableModel.RowId.fetchOne(
                transaction.database,
                sql: sql,
                arguments: [model.uniqueId]
            )
        } catch let error {
            owsFailDebug("Failed to fetch GRDB row ID for uniqueId: \(error)")
            return nil
        }
    }

    /// Persist the given model using the given mode.
    ///
    /// - Parameter saveMode
    /// The mode to use when saving. If this mode does not match persisted
    /// state, the appropriate mode will be used instead. For example, if
    /// `.insert` is given, but we already have a persisted record for this
    /// model, `.update` will be used instead. (And vice versa.)
    func saveModelToDatabase<Model: SDSCodableModel>(
        _ model: Model,
        saveMode: SDSSaveMode,
        transaction: SDSAnyWriteTransaction
    ) {
        guard model.shouldBeSaved else {
            Logger.warn("Skipping save of: \(Model.self).")
            return
        }

        switch saveMode {
        case .insert:
            model.anyWillInsert(transaction: transaction)
        case .update:
            model.anyWillUpdate(transaction: transaction)
        }

        faultTolerantSaveModelToDatabase(
            model,
            saveMode: saveMode,
            transaction: transaction.unwrapGrdbWrite
        )

        switch saveMode {
        case .insert:
            model.anyDidInsert(transaction: transaction)

            if Model.ftsIndexMode != .never {
                FullTextSearchFinder.modelWasInserted(model: model, transaction: transaction)
            }
        case .update:
            model.anyDidUpdate(transaction: transaction)

            if Model.ftsIndexMode == .always {
                FullTextSearchFinder.modelWasUpdated(model: model, transaction: transaction)
            }
        }
    }

    /// "Fault-tolerant" save.
    ///
    /// Upserts in production, triggers asserts in debug builds if the passed
    /// `saveMode` does not align with database contents.
    func faultTolerantSaveModelToDatabase<Model: SDSCodableModel>(
        _ model: Model,
        saveMode: SDSSaveMode,
        transaction: GRDBWriteTransaction
    ) {
        if let existingGrdbRowId = existingGrdbRowId(forModel: model, transaction: transaction) {
            owsAssertDebug(
                saveMode == .update,
                "Could not insert existing record - updating instead."
            )

            updateModelInDatabase(
                model,
                existingGrdbRowId: existingGrdbRowId,
                transaction: transaction
            )
        } else {
            owsAssertDebug(
                saveMode == .insert,
                "Could not update non-existent record - inserting instead."
            )

            insertToDatabase(model: model, transaction: transaction)
        }
    }

    func updateModelInDatabase<Model: SDSCodableModel>(
        _ model: Model,
        existingGrdbRowId: SDSCodableModel.RowId,
        transaction: GRDBWriteTransaction
    ) {
        do {
            var recordCopy = model
            recordCopy.id = existingGrdbRowId

            try recordCopy.update(transaction.database)
        } catch let error {
            DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )

            owsFail("Update failed: \(error.grdbErrorForLogging)")
        }
    }

    func insertToDatabase<Model: SDSCodableModel>(
        model: Model,
        transaction: GRDBWriteTransaction
    ) {
        do {
            try model.insert(transaction.database)
        } catch let error {
            DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )

            owsFail("Insert failed: \(error.grdbErrorForLogging)")
        }
    }
}
