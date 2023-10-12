//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

@objc
public protocol DatabaseChanges: AnyObject {
    typealias UniqueId = String
    typealias RowId = Int64

    var threadUniqueIds: Set<UniqueId> { get }
    /// Unique ids for threads that have been changed in a user-facing way
    /// that should affect the chat list UI.
    var threadUniqueIdsForChatListUpdate: Set<UniqueId> { get }
    /// Dictionary mapping thread uniqueIds to whether their corresponding
    /// UI in the chat list should be updated.
    var uniqueIdToShouldUpdateChatListUiDict: [String: Bool] { get }
    var interactionUniqueIds: Set<UniqueId> { get }
    var storyMessageUniqueIds: Set<UniqueId> { get }
    var storyMessageRowIds: Set<RowId> { get }

    var interactionDeletedUniqueIds: Set<UniqueId> { get }
    var storyMessageDeletedUniqueIds: Set<UniqueId> { get }

    var tableNames: Set<String> { get }
    var collections: Set<String> { get }

    var didUpdateInteractions: Bool { get }

    var didUpdateThreads: Bool { get }

    var didUpdateInteractionsOrThreads: Bool { get }

    // Note that this method should only be used for model
    // collections, not key-value stores.
    @objc(didUpdateModelWithCollection:)
    func didUpdateModel(collection: String) -> Bool

    // Note: In GRDB, this will return true for _any_ key-value write.
    //       This should be acceptable.
    @objc(didUpdateKeyValueStore:)
    func didUpdate(keyValueStore: SDSKeyValueStore) -> Bool

    @objc(didUpdateInteraction:)
    func didUpdate(interaction: TSInteraction) -> Bool

    @objc(didUpdateThread:)
    func didUpdate(thread: TSThread) -> Bool
}

// MARK: -

// Our observers collect "pending" and "committed" database state.
// This struct DRYs up a bunch of that handling, especially around
// thread safety.
//
// NOTE: Different observers collect different kinds of state.
// Not all observers will update all of the properties below.
//
// UniqueId: Some observers use RowIds, some use uniqueIds.
class ObservedDatabaseChanges: NSObject {
    typealias UniqueId = String
    typealias RowId = Int64

    enum ConcurrencyMode {
        case databaseChangeObserverSerialQueue
        case unfairLock
    }
    private let concurrencyMode: ConcurrencyMode

    #if TESTABLE_BUILD
    private func checkConcurrency() {
        switch concurrencyMode {
        case .unfairLock:
            // There's no way to assert we have the unfairLock acquired.
            break
        case .databaseChangeObserverSerialQueue:
            AssertHasDatabaseChangeObserverLock()
        }
    }
    #endif

    init(concurrencyMode: ConcurrencyMode) {
        self.concurrencyMode = concurrencyMode
    }

    public var isEmpty: Bool {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return (_collections.isEmpty &&
                    _tableNames.isEmpty &&
                    threads.isEmpty &&
                    interactions.isEmpty &&
                    storyMessages.isEmpty &&
                    _lastError == nil)
    }

    // MARK: - Collections

    private var _collections: Set<String> = Set()

    func append(collection: String) {
        append(collections: [collection])
    }

    func append(collections: Set<String>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif
        _collections.formUnion(collections)
    }

    // MARK: - Table Names

    private var _tableNames: Set<String> = Set()

    func append(tableName: String) {
        append(tableNames: [tableName])
    }

    func append(tableNames: Set<String>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        _tableNames.formUnion(tableNames)
    }

    // MARK: - Threads

    private var threads = ObservedModelChanges()
    private var uniqueIdToShouldUpdateChatListUi = [String: Bool]()

    var threadUniqueIdsForChatListUpdate: Set<UniqueId> {
        return threadUniqueIds.filter {
            uniqueIdToShouldUpdateChatListUi[$0] == true
        }
    }

    func append(thread: TSThread, shouldUpdateChatListUi: Bool = true) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        threads.append(model: thread)
        // If `shouldUpdateChatListUi` is false, it is important that we set the value
        // in the dictionary to false, rather than leaving it as nil. The code in
        // `self.mapRowIdsToUniqueIds` relies on this.
        uniqueIdToShouldUpdateChatListUi[thread.uniqueId] = (uniqueIdToShouldUpdateChatListUi[thread.uniqueId] ?? false) || shouldUpdateChatListUi
    }

    func append(
        threadUniqueIds: Set<UniqueId>,
        shouldUpdateChatListUiDictParam: [String: Bool]
    ) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        threads.append(uniqueIds: threadUniqueIds)
        for (key, value) in shouldUpdateChatListUiDictParam {
            // In practice, `uniqueIdToShouldUpdateChatListUi` should always be empty to start
            // with because this method is only called on a fresh `ObservedDatabaseChanges`
            // object. However, we do this OR defensively.
            let oldShouldUpdateChatListUi = uniqueIdToShouldUpdateChatListUi[key] ?? false
            uniqueIdToShouldUpdateChatListUi[key] = oldShouldUpdateChatListUi || value
        }
    }

    func append(threadRowId: RowId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        threads.append(rowId: threadRowId)
    }

    // MARK: - Interactions

    private var interactions = ObservedModelChanges()

    func append(interaction: TSInteraction) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.append(model: interaction)
    }

    func append(interactionUniqueId: UniqueId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.append(uniqueId: interactionUniqueId)
    }

    func append(interactionUniqueIds: Set<UniqueId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.append(uniqueIds: interactionUniqueIds)
    }

    func append(interactionDeletedUniqueIds: Set<UniqueId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.append(deletedUniqueIds: interactionDeletedUniqueIds)
    }

    func append(interactionRowId: RowId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.append(rowId: interactionRowId)
    }

    func append(interactionRowIds: Set<RowId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.append(rowIds: interactionRowIds)
    }

    func append(deletedInteractionRowId: RowId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.append(deletedRowId: deletedInteractionRowId)
    }

    // MARK: - Stories

    private var storyMessages = ObservedModelChanges()

    func append(storyMessage: StoryMessage) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        storyMessages.append(model: storyMessage)
    }

    func append(storyMessageUniqueId: UniqueId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        storyMessages.append(uniqueId: storyMessageUniqueId)
    }

    func append(storyMessageUniqueIds: Set<UniqueId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        storyMessages.append(uniqueIds: storyMessageUniqueIds)
    }

    func append(storyMessageDeletedUniqueIds: Set<UniqueId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        storyMessages.append(deletedUniqueIds: storyMessageDeletedUniqueIds)
    }

    func append(storyMessageRowId: RowId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        storyMessages.append(rowId: storyMessageRowId)
    }

    func append(storyMessageRowIds: Set<RowId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        storyMessages.append(rowIds: storyMessageRowIds)
    }

    // MARK: - Errors

    func setLastError(_ error: Error) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        _lastError = error
    }

    private var _lastError: Error?
    var lastError: Error? {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return _lastError
    }
}

// MARK: -

private struct ObservedModelChanges {
    typealias UniqueId = ObservedDatabaseChanges.UniqueId
    typealias RowId = ObservedDatabaseChanges.RowId

    private var _rowIds = Set<RowId>()
    private var _uniqueIds = Set<UniqueId>()
    private var _deletedRowIds = Set<RowId>()
    private var _deletedUniqueIds = Set<UniqueId>()
    fileprivate var rowIdToUniqueIdMap = [RowId: UniqueId]()

    public var isEmpty: Bool {
        return (_rowIds.isEmpty &&
                    _uniqueIds.isEmpty &&
                    _deletedRowIds.isEmpty &&
                    _deletedUniqueIds.isEmpty &&
                    rowIdToUniqueIdMap.isEmpty)
    }

    mutating func append(model: SDSIdentifiableModel) {
        _uniqueIds.insert(model.uniqueId)
        guard let grdbId = model.grdbId else {
            owsFailDebug("Missing grdbId")
            return
        }
        let rowId: RowId = grdbId.int64Value
        _rowIds.insert(rowId)
        rowIdToUniqueIdMap[rowId] = model.uniqueId
    }

    mutating func append(uniqueId: UniqueId) {
        append(uniqueIds: [uniqueId])
    }

    mutating func append(uniqueIds: Set<UniqueId>) {
        _uniqueIds.formUnion(uniqueIds)
    }

    fileprivate mutating func append(deletedUniqueIds: Set<UniqueId>) {
        _deletedUniqueIds.formUnion(deletedUniqueIds)
    }

    mutating func append(rowId: RowId) {
        #if TESTABLE_BUILD
        assert(rowId > 0)
        #endif
        append(rowIds: [rowId])
    }

    mutating func append(deletedRowId: RowId) {
        #if TESTABLE_BUILD
        assert(deletedRowId > 0)
        #endif
        _deletedRowIds.insert(deletedRowId)
    }

    mutating func append(rowIds: Set<RowId>) {
        #if TESTABLE_BUILD
        for rowId in rowIds {
            assert(rowId > 0)
        }
        #endif
        _rowIds.formUnion(rowIds)
    }

    var rowIds: Set<RowId> {
        assert(_rowIds.count >= _uniqueIds.count)
        return _rowIds
    }
    var uniqueIds: Set<UniqueId> { _uniqueIds }
    var deletedUniqueIds: Set<UniqueId> { _deletedUniqueIds }
    var deletedRowIds: Set<RowId> { _deletedRowIds }
}

// MARK: - Published state

extension ObservedDatabaseChanges: DatabaseChanges {

    var threadUniqueIds: Set<UniqueId> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return threads.uniqueIds
    }

    var uniqueIdToShouldUpdateChatListUiDict: [String: Bool] {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return uniqueIdToShouldUpdateChatListUi
    }

    var interactionUniqueIds: Set<UniqueId> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return interactions.uniqueIds
    }

    var storyMessageUniqueIds: Set<UniqueId> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return storyMessages.uniqueIds
    }

    var storyMessageRowIds: Set<RowId> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return storyMessages.rowIds
    }

    var interactionDeletedUniqueIds: Set<UniqueId> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return interactions.deletedUniqueIds
    }

    var storyMessageDeletedUniqueIds: Set<UniqueId> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return storyMessages.deletedUniqueIds
    }

    var tableNames: Set<String> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return _tableNames
    }

    var collections: Set<String> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return _collections
    }

    var didUpdateInteractions: Bool {
        return didUpdate(collection: TSInteraction.collection())
    }

    var didUpdateThreads: Bool {
        return didUpdate(collection: TSThread.collection())
    }

    var didUpdateInteractionsOrThreads: Bool {
        return didUpdateInteractions || didUpdateThreads
    }

    private func didUpdate(collection: String) -> Bool {
        collections.contains(collection)
    }

    @objc(didUpdateModelWithCollection:)
    func didUpdateModel(collection: String) -> Bool {
        return didUpdate(collection: collection)
    }

    @objc(didUpdateKeyValueStore:)
    func didUpdate(keyValueStore: SDSKeyValueStore) -> Bool {
        // GRDB: SDSKeyValueStore.dataStoreCollection
        return (didUpdate(collection: keyValueStore.collection) ||
                    didUpdate(collection: SDSKeyValueStore.dataStoreCollection))
    }

    @objc(didUpdateInteraction:)
    func didUpdate(interaction: TSInteraction) -> Bool {
        interactionUniqueIds.contains(interaction.uniqueId)
    }

    @objc(didUpdateThread:)
    func didUpdate(thread: TSThread) -> Bool {
        threadUniqueIds.contains(thread.uniqueId)
    }

    func finalizePublishedState(db: Database) throws {
        // We don't finalize everything, only state the views currently care about.

        // We need to convert all thread "row ids" to "unique ids".
        threads.append(uniqueIds: try mapRowIdsToUniqueIds(db: db,
                                                           rowIds: threads.rowIds,
                                                           uniqueIds: threads.uniqueIds,
                                                           rowIdToUniqueIdMap: threads.rowIdToUniqueIdMap,
                                                           tableName: "\(ThreadRecord.databaseTableName)",
                                                           uniqueIdColumnName: "\(threadColumn: .uniqueId)",
                                                           isMappingForThreads: true))

        // We need to convert all interaction "row ids" to "unique ids".
        interactions.append(uniqueIds: try mapRowIdsToUniqueIds(db: db,
                                                                rowIds: interactions.rowIds,
                                                                uniqueIds: interactions.uniqueIds,
                                                                rowIdToUniqueIdMap: interactions.rowIdToUniqueIdMap,
                                                                tableName: "\(InteractionRecord.databaseTableName)",
                                                                uniqueIdColumnName: "\(interactionColumn: .uniqueId)"))

        // We need to convert _deleted_ interaction "row ids" to "unique ids".
        interactions.append(deletedUniqueIds: try mapRowIdsToUniqueIds(db: db,
                                                                       rowIds: interactions.deletedRowIds,
                                                                       uniqueIds: interactions.deletedUniqueIds,
                                                                       rowIdToUniqueIdMap: interactions.rowIdToUniqueIdMap,
                                                                       tableName: "\(InteractionRecord.databaseTableName)",
                                                                       uniqueIdColumnName: "\(interactionColumn: .uniqueId)"))

        // We need to convert db table names to "collections."
        mapTableNamesToCollections()
    }

    private func mapRowIdsToUniqueIds(db: Database,
                                      rowIds: Set<RowId>,
                                      uniqueIds: Set<UniqueId>,
                                      rowIdToUniqueIdMap: [RowId: UniqueId],
                                      tableName: String,
                                      uniqueIdColumnName: String,
                                      isMappingForThreads: Bool = false) throws -> Set<String> {
        AssertHasDatabaseChangeObserverLock()

        // We try to avoid the query below by leveraging the
        // fact that we know the uniqueId and rowId for
        // touched threads.
        //
        // If a thread was touched _and_ modified, we
        // can convert its rowId to a uniqueId without a query.
        var allUniqueIds = uniqueIds
        var unresolvedRowIds = [RowId]()
        for rowId in rowIds {
            if let uniqueId = rowIdToUniqueIdMap[rowId] {
                allUniqueIds.insert(uniqueId)
                if isMappingForThreads, uniqueIdToShouldUpdateChatListUi[uniqueId] == nil {
                    /// When we aren't sure whether a changed thread should trigger a
                    /// chat list UI update, we want to do so to be safe. If there is
                    /// already a value for this uniqueId in `uniqueIdToShouldUpdateChatListUi`,
                    /// we can trust that this is correct and do not want to override it.
                    uniqueIdToShouldUpdateChatListUi[uniqueId] = true
                }
            } else {
                unresolvedRowIds.append(rowId)
            }
        }

        guard allUniqueIds.count < DatabaseChangeObserver.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }
        guard unresolvedRowIds.count < DatabaseChangeObserver.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }

        guard unresolvedRowIds.count > 0 else {
            return allUniqueIds
        }

        let commaSeparatedRowIds = unresolvedRowIds.map { String($0) }.joined(separator: ", ")
        let rowIdsSQL = "(\(commaSeparatedRowIds))"
        let mappingSql = """
        SELECT \(uniqueIdColumnName)
        FROM \(tableName)
        WHERE rowid IN \(rowIdsSQL)
        """
        let fetchedUniqueIds = try String.fetchAll(db, sql: mappingSql)
        if isMappingForThreads {
            for id in fetchedUniqueIds {
                if uniqueIdToShouldUpdateChatListUi[id] == nil {
                    /// When we aren't sure whether a changed thread should trigger a
                    /// chat list UI update, we want to do so to be safe. If there is
                    /// already a value for this uniqueId in `uniqueIdToShouldUpdateChatListUi`,
                    /// we can trust that this is correct and do not want to override it.
                    uniqueIdToShouldUpdateChatListUi[id] = true
                }
            }
        }
        allUniqueIds.formUnion(fetchedUniqueIds)

        guard allUniqueIds.count < DatabaseChangeObserver.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }

        return allUniqueIds
    }

    private static var tableNameToCollectionMap: [String: String] = {
        var result = [String: String]()
        for table in GRDBDatabaseStorageAdapter.tables {
            result[table.tableName] = table.collection
        }
        for table in GRDBDatabaseStorageAdapter.swiftTables {
            result[table.databaseTableName] = String(describing: table)
        }
        result[SDSKeyValueStore.tableName] = SDSKeyValueStore.dataStoreCollection
        return result
    }()

    private func mapTableNamesToCollections() {
        let tableNames = self.tableNames
        guard tableNames.count > 0 else {
            return
        }

        // If necessary, convert GRDB table names to "collections".
        let tableNameToCollectionMap = Self.tableNameToCollectionMap
        for tableName in tableNames {
            guard !tableName.hasPrefix(GRDBFullTextSearchFinder.contentTableName) else {
                owsFailDebug("should not have been notified for changes to FTS tables")
                continue
            }
            guard tableName != "grdb_migrations" else {
                continue
            }
            guard let collection = tableNameToCollectionMap[tableName] else {
                owsFailDebug("Unknown table: \(tableName)")
                continue
            }
            append(collection: collection)
        }
    }
}

public protocol SDSIdentifiableModel {
    var uniqueId: String { get }
    var grdbId: NSNumber? { get }
}
