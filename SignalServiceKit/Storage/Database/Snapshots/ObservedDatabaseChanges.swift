//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

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

        return (
            _tableNames.isEmpty
            && _tableRowIds.isEmpty
            && threads.isEmpty
            && interactions.isEmpty
            && storyMessages.isEmpty
            && _lastError == nil
        )
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

    // MARK: - Table Rows

    private var _tableRowIds: [String: Set<Int64>] = [:]

    func insert(tableName: String, rowId: Int64) {
        formUnion(tableRowIds: [tableName: [rowId]])
    }

    func formUnion(tableRowIds: [String: Set<Int64>]) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        _tableRowIds.merge(tableRowIds, uniquingKeysWith: { $0.union($1) })
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

extension ObservedDatabaseChanges {

    var threadUniqueIds: Set<UniqueId> {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        return threads.uniqueIds.keys
    }

    func snapshot() -> DatabaseChangesSnapshot {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        let threadUniqueIds: Set<UniqueId> = threads.uniqueIds.keys
        let threadUniqueIdsForChatListUpdate: Set<UniqueId> = threads.uniqueIds.keys(where: \.chatListUiUpdateRule.shouldUpdate)
        let interactionUniqueIds: Set<UniqueId> = interactions.uniqueIds.keys
        let storyMessageUniqueIds: Set<UniqueId> = storyMessages.uniqueIds.keys
        let storyMessageRowIds: Set<RowId> = storyMessages.rowIds
        let interactionDeletedUniqueIds: Set<UniqueId> = interactions.deletedUniqueIds.keys
        let storyMessageDeletedUniqueIds: Set<UniqueId> = storyMessages.deletedUniqueIds.keys
        let tableNames: Set<String> = _tableNames
        let tableRowIds: [String: Set<Int64>] = _tableRowIds
        let didUpdateInteractions: Bool = tableNames.contains(TSInteraction.table.tableName)
        let didUpdateThreads: Bool = tableNames.contains(TSThread.table.tableName)
        let lastError = _lastError

        return DatabaseChangesSnapshot(
            threadUniqueIds: threadUniqueIds,
            threadUniqueIdsForChatListUpdate: threadUniqueIdsForChatListUpdate,
            interactionUniqueIds: interactionUniqueIds,
            storyMessageUniqueIds: storyMessageUniqueIds,
            storyMessageRowIds: storyMessageRowIds,
            interactionDeletedUniqueIds: interactionDeletedUniqueIds,
            storyMessageDeletedUniqueIds: storyMessageDeletedUniqueIds,
            tableNames: tableNames,
            tableRowIds: tableRowIds,
            didUpdateInteractions: didUpdateInteractions,
            didUpdateThreads: didUpdateThreads,
            lastError: lastError
        )
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
        let tableNames = self._tableNames
        let tableRowIds = self._tableRowIds

        lock.withLock {
            committedChanges.interactions.merge(interactions)
            committedChanges.threads.merge(threads)
            committedChanges.storyMessages.merge(storyMessages)
            committedChanges.formUnion(tableNames: tableNames)
            committedChanges.formUnion(tableRowIds: tableRowIds)
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

        guard allUniqueIds.count < DatabaseChangeObserverImpl.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }
        guard unresolvedRowIds.count < DatabaseChangeObserverImpl.kMaxIncrementalRowChanges else {
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

        guard allUniqueIds.count < DatabaseChangeObserverImpl.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }

        return allUniqueIds
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
