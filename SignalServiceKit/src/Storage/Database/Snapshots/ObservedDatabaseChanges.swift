//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public protocol UIDatabaseChanges: AnyObject {
    typealias UniqueId = String

    var threadUniqueIds: Set<UniqueId> { get }
    var interactionUniqueIds: Set<UniqueId> { get }
    var attachmentUniqueIds: Set<UniqueId> { get }

    var interactionDeletedUniqueIds: Set<UniqueId> { get }
    var attachmentDeletedUniqueIds: Set<UniqueId> { get }

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
        case mainThread
        case uiDatabaseObserverSerialQueue
    }
    private let concurrencyMode: ConcurrencyMode

    #if TESTABLE_BUILD
    private func checkConcurrency() {
        switch concurrencyMode {
        case .mainThread:
            AssertIsOnMainThread()
        case .uiDatabaseObserverSerialQueue:
            AssertHasUIDatabaseObserverLock()
        }
    }
    #endif

    init(concurrencyMode: ConcurrencyMode) {
        self.concurrencyMode = concurrencyMode
    }

    // MARK: - Completion Blocks

    public typealias CompletionBlock = () -> Void
    public var completionBlocks = [CompletionBlock]()

    func add(completionBlock: @escaping CompletionBlock) {
        completionBlocks.append(completionBlock)

    }

    func append(completionBlocks: [CompletionBlock]) {
        self.completionBlocks += completionBlocks
    }

    func fireCompletionBlocks() {
        for completionBlock in completionBlocks {
            completionBlock()
        }
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

    func append(thread: TSThread) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        threads.append(model: thread)
    }

    func append(threadUniqueId: UniqueId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        threads.append(uniqueId: threadUniqueId)
    }

    func append(threadUniqueIds: Set<UniqueId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        threads.append(uniqueIds: threadUniqueIds)
    }

    func append(threadRowId: RowId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        threads.append(rowId: threadRowId)
    }

    func append(threadRowIds: Set<RowId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        threads.append(rowIds: threadRowIds)
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

    // MARK: - Attachments

    private var attachments = ObservedModelChanges()

    func append(attachment: TSAttachment) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        attachments.append(model: attachment)
    }

    func append(attachmentUniqueId: UniqueId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        attachments.append(uniqueId: attachmentUniqueId)
    }

    func append(attachmentUniqueIds: Set<UniqueId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        attachments.append(uniqueIds: attachmentUniqueIds)
    }

    func append(interactionDeletedUniqueIds: Set<UniqueId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.append(deletedUniqueIds: interactionDeletedUniqueIds)
    }

    func append(attachmentDeletedUniqueIds: Set<UniqueId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        attachments.append(deletedUniqueIds: attachmentDeletedUniqueIds)
    }

    func append(attachmentRowId: RowId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        attachments.append(rowId: attachmentRowId)
    }

    func append(attachmentRowIds: Set<RowId>) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        attachments.append(rowIds: attachmentRowIds)
    }

    func append(deletedAttachmentRowId: RowId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        attachments.append(deletedRowId: deletedAttachmentRowId)
    }

    func append(deletedInteractionRowId: RowId) {
        #if TESTABLE_BUILD
        checkConcurrency()
        #endif

        interactions.append(deletedRowId: deletedInteractionRowId)
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
        get {
            #if TESTABLE_BUILD
            checkConcurrency()
            #endif

            return _lastError
        }
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

    mutating func append(model: BaseModel) {
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
        get {
            assert(_rowIds.count >= _uniqueIds.count)
            return _rowIds
        }
    }

    var uniqueIds: Set<UniqueId> {
        get {
            return _uniqueIds
        }
    }

    var deletedUniqueIds: Set<UniqueId> {
        get {
            return _deletedUniqueIds
        }
    }

    var deletedRowIds: Set<RowId> {
        get {
            return _deletedRowIds
        }
    }
}

// MARK: - Published state

extension ObservedDatabaseChanges: UIDatabaseChanges {

    var threadUniqueIds: Set<UniqueId> {
        get {
            #if TESTABLE_BUILD
            checkConcurrency()
            #endif

            return threads.uniqueIds
        }
    }

    var interactionUniqueIds: Set<UniqueId> {
        get {
            #if TESTABLE_BUILD
            checkConcurrency()
            #endif

            return interactions.uniqueIds
        }
    }

    var attachmentUniqueIds: Set<UniqueId> {
        get {
            #if TESTABLE_BUILD
            checkConcurrency()
            #endif

            return attachments.uniqueIds
        }
    }

    var interactionDeletedUniqueIds: Set<UniqueId> {
        get {
            #if TESTABLE_BUILD
            checkConcurrency()
            #endif

            return interactions.deletedUniqueIds
        }
    }

    var attachmentDeletedUniqueIds: Set<UniqueId> {
        get {
            #if TESTABLE_BUILD
            checkConcurrency()
            #endif

            return attachments.deletedUniqueIds
        }
    }

    var tableNames: Set<String> {
        get {
            #if TESTABLE_BUILD
            checkConcurrency()
            #endif

            return _tableNames
        }
    }

    var collections: Set<String> {
        get {
            #if TESTABLE_BUILD
            checkConcurrency()
            #endif

            return _collections
        }
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
        // YDB: keyValueStore.collection
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
            uniqueIdColumnName: "\(threadColumn: .uniqueId)"))

        // We need to convert all interaction "row ids" to "unique ids".
        interactions.append(uniqueIds: try mapRowIdsToUniqueIds(db: db,
                                                                rowIds: interactions.rowIds,
                                                                uniqueIds: interactions.uniqueIds,
                                                                rowIdToUniqueIdMap: interactions.rowIdToUniqueIdMap,
                                                                tableName: "\(InteractionRecord.databaseTableName)",
            uniqueIdColumnName: "\(interactionColumn: .uniqueId)"))

        // We need to convert all attachment "row ids" to "unique ids".
        attachments.append(uniqueIds: try mapRowIdsToUniqueIds(db: db,
                                                               rowIds: attachments.rowIds,
                                                               uniqueIds: attachments.uniqueIds,
                                                               rowIdToUniqueIdMap: attachments.rowIdToUniqueIdMap,
                                                               tableName: "\(AttachmentRecord.databaseTableName)",
            uniqueIdColumnName: "\(attachmentColumn: .uniqueId)"))

        // We need to convert _deleted_ attachment "row ids" to "unique ids".
        attachments.append(deletedUniqueIds: try mapRowIdsToUniqueIds(db: db,
                                                                      rowIds: attachments.deletedRowIds,
                                                                      uniqueIds: attachments.deletedUniqueIds,
                                                                      rowIdToUniqueIdMap: attachments.rowIdToUniqueIdMap,
                                                                      tableName: "\(AttachmentRecord.databaseTableName)",
                                                                      uniqueIdColumnName: "\(attachmentColumn: .uniqueId)"))

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
                                      uniqueIdColumnName: String) throws -> Set<String> {
        AssertHasUIDatabaseObserverLock()

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
            } else {
                unresolvedRowIds.append(rowId)
            }
        }

        guard allUniqueIds.count < UIDatabaseObserver.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }
        guard unresolvedRowIds.count < UIDatabaseObserver.kMaxIncrementalRowChanges else {
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
        allUniqueIds.formUnion(fetchedUniqueIds)

        guard allUniqueIds.count < UIDatabaseObserver.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }

        return allUniqueIds
    }

    private static var tableNameToCollectionMap: [String: String] = {
        var result = [String: String]()
        for table in GRDBDatabaseStorageAdapter.tables {
            result[table.tableName] = table.collection
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
