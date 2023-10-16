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

    func insert(collection: String) {
        formUnion(collections: [collection])
    }

    func formUnion(collections: Set<String>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif
        _collections.formUnion(collections)
    }

    // MARK: - Table Names

    private var _tableNames: Set<String> = Set()

    func insert(tableName: String) {
        formUnion(tableNames: [tableName])
    }

    func formUnion(tableNames: Set<String>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        _tableNames.formUnion(tableNames)
    }

    // MARK: - Threads

    private var threads = ObservedModelChanges()

    func insert(thread: TSThread, shouldUpdateChatListUi: Bool = true) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        threads.insert(
            model: thread,
            state: .init(
                chatListUiUpdateRule: shouldUpdateChatListUi.asChatListUIUpdateRule
            )
        )
    }

    func insert(threadRowId: RowId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        threads.insert(rowId: threadRowId)
    }

    // MARK: - Interactions

    private var interactions = ObservedModelChanges()

    func insert(interaction: TSInteraction) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.insert(model: interaction, state: .default)
    }

    func insert(interactionUniqueId: UniqueId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.insert(uniqueId: interactionUniqueId, state: .default)
    }

    func formUnion(interactionUniqueIds: Set<UniqueId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.formUnion(uniqueIds: interactionUniqueIds.asMergingDictWithUniformValue(.default))
    }

    func formUnion(interactionDeletedUniqueIds: Set<UniqueId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.formUnion(deletedUniqueIds: interactionDeletedUniqueIds.asMergingDictWithUniformValue(.default))
    }

    func insert(interactionRowId: RowId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.insert(rowId: interactionRowId)
    }

    func formUnion(interactionRowIds: Set<RowId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.formUnion(rowIds: interactionRowIds)
    }

    func insert(deletedInteractionRowId: RowId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.insert(deletedRowId: deletedInteractionRowId)
    }

    // MARK: - Stories

    private var storyMessages = ObservedModelChanges()

    func insert(storyMessage: StoryMessage) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        storyMessages.insert(model: storyMessage, state: .default)
    }

    func insert(storyMessageUniqueId: UniqueId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        storyMessages.insert(uniqueId: storyMessageUniqueId, state: .default)
    }

    func formUnion(storyMessageUniqueIds: Set<UniqueId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        storyMessages.formUnion(uniqueIds: storyMessageUniqueIds.asMergingDictWithUniformValue(.default))
    }

    func formUnion(storyMessageDeletedUniqueIds: Set<UniqueId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        storyMessages.formUnion(deletedUniqueIds: storyMessageDeletedUniqueIds.asMergingDictWithUniformValue(.default))
    }

    func insert(storyMessageRowId: RowId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        storyMessages.insert(rowId: storyMessageRowId)
    }

    func formUnion(storyMessageRowIds: Set<RowId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        storyMessages.formUnion(rowIds: storyMessageRowIds)
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

/// Whether we should update the chat list UI due to a database change.
/// Merged together when multiple changes to the same identifier are collapsed
/// together; e.g. two changes happen to the same thread unique id.
private enum ChatListUIUpdateRule: Mergeable {
    /// The caller did not specify whether the chat list needs updating
    /// due to a change with the associated identifier.
    /// Treated as requiring an update (the default), but when merging,
    /// prefers an explicit setting. (e.g. undefined + update = update,
    /// undefined + noUpdate = noUpdate).
    case undefined
    /// No UI update required due to the change with the associated identifier.
    /// When merging multiple changes together, update + noUpdate = update.
    case noUpdate
    /// A UI update is explicitly required due to the change with the associated identifier.
    /// When merging multiple changes together, update + noUpdate = update. 
    case update

    var shouldUpdate: Bool {
        switch self {
        case .undefined, .update:
            return true
        case .noUpdate:
            return false
        }
    }

    func merge(_ other: Self) -> Self {
        switch (self, other) {
        case (.update, _):
            return .update
        case (.undefined, _):
            return other
        case (.noUpdate, .update):
            return .update
        case (.noUpdate, .noUpdate), (.noUpdate, .undefined):
            return .noUpdate
        }
    }
}

fileprivate extension Bool {
    var asChatListUIUpdateRule: ChatListUIUpdateRule {
        return self ? .update : .noUpdate
    }
}

/// Track state related to a single model update, for example
/// whether this model change should trigger chat list UI to update.
private struct ObservedModelState: Mergeable {
    var chatListUiUpdateRule: ChatListUIUpdateRule

    // Add other fields here as new state needs to be tracked.

    static var `default`: Self {
        return Self.init(chatListUiUpdateRule: .undefined)
    }

    func merge(_ other: Self) -> Self {
        return .init(
            chatListUiUpdateRule: chatListUiUpdateRule.merge(other.chatListUiUpdateRule)
        )
    }
}

// MARK: -

private struct ObservedModelChanges {
    typealias UniqueId = ObservedDatabaseChanges.UniqueId
    typealias RowId = ObservedDatabaseChanges.RowId

    private var _rowIds = Set<RowId>()
    private var _uniqueIds = MergingDict<UniqueId, ObservedModelState>()
    private var _deletedRowIds = Set<RowId>()
    private var _deletedUniqueIds = MergingDict<UniqueId, ObservedModelState>()
    fileprivate var rowIdToUniqueIdMap = [RowId: UniqueId]()

    public var isEmpty: Bool {
        return (_rowIds.isEmpty &&
                    _uniqueIds.isEmpty &&
                    _deletedRowIds.isEmpty &&
                    _deletedUniqueIds.isEmpty &&
                    rowIdToUniqueIdMap.isEmpty)
    }

    mutating func merge(_ other: ObservedModelChanges) {
        _rowIds.formUnion(other._rowIds)
        _uniqueIds.formUnion(other._uniqueIds)
        _deletedRowIds.formUnion(other._deletedRowIds)
        _deletedUniqueIds.formUnion(other._deletedUniqueIds)
        for (k, v) in other.rowIdToUniqueIdMap {
            rowIdToUniqueIdMap[k] = v
        }
    }

    mutating func insert(model: SDSIdentifiableModel, state: ObservedModelState) {
        _uniqueIds.insert(model.uniqueId, state)
        guard let grdbId = model.grdbId else {
            owsFailDebug("Missing grdbId")
            return
        }
        let rowId: RowId = grdbId.int64Value
        _rowIds.insert(rowId)
        rowIdToUniqueIdMap[rowId] = model.uniqueId
    }

    mutating func insert(uniqueId: UniqueId, state: ObservedModelState) {
        _uniqueIds.insert(uniqueId, state)
    }

    mutating func formUnion(uniqueIds: MergingDict<UniqueId, ObservedModelState>) {
        _uniqueIds.formUnion(uniqueIds)
    }

    fileprivate mutating func formUnion(deletedUniqueIds: MergingDict<UniqueId, ObservedModelState>) {
        _deletedUniqueIds.formUnion(deletedUniqueIds)
    }

    mutating func insert(rowId: RowId) {
        #if TESTABLE_BUILD
        assert(rowId > 0)
        #endif
        formUnion(rowIds: [rowId])
    }

    mutating func insert(deletedRowId: RowId) {
        #if TESTABLE_BUILD
        assert(deletedRowId > 0)
        #endif
        _deletedRowIds.insert(deletedRowId)
    }

    mutating func formUnion(rowIds: Set<RowId>) {
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
    var uniqueIds: MergingDict<UniqueId, ObservedModelState> { _uniqueIds }
    var deletedUniqueIds: MergingDict<UniqueId, ObservedModelState> { _deletedUniqueIds }
    var deletedRowIds: Set<RowId> { _deletedRowIds }
}

// MARK: - Published state

extension ObservedDatabaseChanges: DatabaseChanges {

    var threadUniqueIds: Set<UniqueId> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return threads.uniqueIds.keys
    }

    var threadUniqueIdsForChatListUpdate: Set<UniqueId> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return threads.uniqueIds.keys(where: \.chatListUiUpdateRule.shouldUpdate)
    }

    var interactionUniqueIds: Set<UniqueId> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return interactions.uniqueIds.keys
    }

    var storyMessageUniqueIds: Set<UniqueId> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return storyMessages.uniqueIds.keys
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

        return interactions.deletedUniqueIds.keys
    }

    var storyMessageDeletedUniqueIds: Set<UniqueId> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return storyMessages.deletedUniqueIds.keys
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

    /// Finalizes the current set of changes, mapping any row Ids to uniqueIds by doing database lookups.
    /// Then copies over final changes to a "committed" set of changes, using the provided lock to
    /// guard updates.
    func finalizePublishedStateAndCopyToCommittedChanges(
        _ committedChanges: ObservedDatabaseChanges,
        withLock lock: UnfairLock,
        db: Database
    ) {
        do {
            // finalizePublishedState() finalizes the state we're about to
            // copy.
            try finalizePublishedState(db: db)
        } catch let error {
            lock.withLock {
                committedChanges.setLastError(error)
            }
            return
        }

        let interactions = self.interactions
        let threads = self.threads
        let storyMessages = self.storyMessages
        let collections = self.collections
        let tableNames = self.tableNames

        lock.withLock {
            committedChanges.interactions.merge(interactions)
            committedChanges.threads.merge(threads)
            committedChanges.storyMessages.merge(storyMessages)
            committedChanges.formUnion(collections: collections)
            committedChanges.formUnion(tableNames: tableNames)
        }
    }

    private func finalizePublishedState(db: Database) throws {
        // We don't finalize everything, only state the views currently care about.

        // We need to convert all thread "row ids" to "unique ids".
        threads.formUnion(
            uniqueIds: try mapRowIdsToUniqueIds(
                db: db,
                rowIds: threads.rowIds,
                uniqueIds: threads.uniqueIds,
                rowIdToUniqueIdMap: threads.rowIdToUniqueIdMap,
                tableName: "\(ThreadRecord.databaseTableName)",
                uniqueIdColumnName: "\(threadColumn: .uniqueId)"
            )
        )

        // We need to convert all interaction "row ids" to "unique ids".
        interactions.formUnion(
            uniqueIds: try mapRowIdsToUniqueIds(
                db: db,
                rowIds: interactions.rowIds,
                uniqueIds: interactions.uniqueIds,
                rowIdToUniqueIdMap: interactions.rowIdToUniqueIdMap,
                tableName: "\(InteractionRecord.databaseTableName)",
                uniqueIdColumnName: "\(interactionColumn: .uniqueId)"
            )
        )

        // We need to convert _deleted_ interaction "row ids" to "unique ids".
        interactions.formUnion(
            deletedUniqueIds: try mapRowIdsToUniqueIds(
                db: db,
                rowIds: interactions.deletedRowIds,
                uniqueIds: interactions.deletedUniqueIds,
                rowIdToUniqueIdMap: interactions.rowIdToUniqueIdMap,
                tableName: "\(InteractionRecord.databaseTableName)",
                uniqueIdColumnName: "\(interactionColumn: .uniqueId)"
            )
        )

        // We need to convert db table names to "collections."
        mapTableNamesToCollections()
    }

    private func mapRowIdsToUniqueIds(
        db: Database,
        rowIds: Set<RowId>,
        uniqueIds: MergingDict<UniqueId, ObservedModelState>,
        rowIdToUniqueIdMap: [RowId: UniqueId],
        tableName: String,
        uniqueIdColumnName: String
    ) throws -> MergingDict<UniqueId, ObservedModelState> {
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
                allUniqueIds.insert(uniqueId, .default)
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
        let fetchedUniqueIds = try String.fetchSet(db, sql: mappingSql)
        allUniqueIds.formUnion(fetchedUniqueIds.asMergingDictWithUniformValue(.default))

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
            insert(collection: collection)
        }
    }
}

public protocol SDSIdentifiableModel {
    var uniqueId: String { get }
    var grdbId: NSNumber? { get }
}

private extension Set {

    func asMergingDictWithUniformValue<V>(_ value: V) -> MergingDict<Element, V> {
        var dict = MergingDict<Element, V>()
        self.forEach {
            dict.insert($0, value)
        }
        return dict
    }
}
