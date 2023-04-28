//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Performs database operations on ``SDSCodableModel`` types.
protocol SDSCodableModelDatabaseInterface {

    // MARK: Fetch

    /// Fetch a persisted model with the given unique ID, if one exists.
    func fetchModel<Model: SDSCodableModel>(
        modelType: Model.Type,
        uniqueId: String,
        transaction: DBReadTransaction
    ) -> Model?

    /// Fetch all persisted models of the given type.
    func fetchAllModels<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBReadTransaction
    ) -> [Model]

    /// Count all persisted models of the given type.
    func countAllModels<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBReadTransaction
    ) -> UInt

    // MARK: Remove

    /// Remove a model from the database.
    func removeModel<Model: SDSCodableModel>(
        _ model: Model,
        transaction: DBWriteTransaction
    )

    /// Instantiate and remove all models of the given type from the database.
    func removeAllModelsWithInstantiation<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBWriteTransaction
    )

    // MARK: Save

    /// Insert the given model to the database.
    func insertModel<Model: SDSCodableModel>(
        _ model: Model,
        transaction: DBWriteTransaction
    )

    /// If a persisted record exists for this model, do an overwriting update.
    /// Otherwise, do an insertion.
    func upsertModel<Model: SDSCodableModel>(
        _ model: Model,
        transaction: DBWriteTransaction
    )

    /// Apply changes produced by the given block to the persisted copy of the
    /// given model.
    func updateModel<Model: SDSCodableModel & AnyObject>(
        _ model: Model,
        transaction: DBWriteTransaction,
        block: (Model) -> Void
    )

    /// Immediately persist the given model.
    func overwritingUpdateModel<Model: SDSCodableModel>(
        _ model: Model,
        transaction: DBWriteTransaction
    )

    // MARK: Enumerate

    /// Traverse all records, in no particular order.
    func enumerateModels<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBReadTransaction,
        batched: Bool,
        block: @escaping (Model, UnsafeMutablePointer<ObjCBool>) -> Void
    )

    /// Traverse all records' unique IDs, in no particular order.
    func enumerateModelUniqueIds<Model: SDSCodableModel>(
        modelType: Model.Type,
        transaction: DBReadTransaction,
        batched: Bool,
        block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void
    )
}

/// The implementations of these methods previously existed as extensions on
/// ``SDSCodableModel``, and convenience stubs still exist there that forward
/// to this class. They have largely been migrated here as they were there.
public class SDSCodableModelDatabaseInterfaceImpl: SDSCodableModelDatabaseInterface {}
