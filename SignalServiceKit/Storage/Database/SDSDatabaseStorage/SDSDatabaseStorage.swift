//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

// MARK: -

@objc
public class SDSDatabaseStorage: NSObject, DB {
    private let asyncWriteQueue = DispatchQueue(label: "org.signal.database.write-async", qos: .userInitiated)
    private let awaitableWriteQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    private var hasPendingCrossProcessWrite = false

    // Implicitly unwrapped because it is set in the initializer but after initialization completes because it
    // needs to refer to self.
    private var crossProcess: SDSCrossProcess!

    // MARK: - Initialization / Setup

    private let appReadiness: AppReadiness
    private let _databaseChangeObserver: SDSDatabaseChangeObserver

    public let databaseFileUrl: URL
    public let keyFetcher: GRDBKeyFetcher

    private(set) public var grdbStorage: GRDBDatabaseStorageAdapter
    public var databaseChangeObserver: DatabaseChangeObserver { _databaseChangeObserver }

    public init(appReadiness: AppReadiness, databaseFileUrl: URL, keychainStorage: any KeychainStorage) throws {
        self.appReadiness = appReadiness
        self._databaseChangeObserver = DatabaseChangeObserverImpl(appReadiness: appReadiness)
        self.databaseFileUrl = databaseFileUrl
        self.keyFetcher = GRDBKeyFetcher(keychainStorage: keychainStorage)
        self.grdbStorage = try GRDBDatabaseStorageAdapter(
            databaseChangeObserver: _databaseChangeObserver,
            databaseFileUrl: databaseFileUrl,
            keyFetcher: self.keyFetcher
        )

        super.init()

        if CurrentAppContext().isRunningTests {
            self.crossProcess = SDSCrossProcess(callback: {})
        } else {
            self.crossProcess = SDSCrossProcess(callback: { @MainActor [weak self] () -> Void in
                self?.handleCrossProcessWrite()
            })
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(didBecomeActive),
                                                   name: UIApplication.didBecomeActiveNotification,
                                                   object: nil)
        }
    }

    public class var baseDir: URL {
        return URL(
            fileURLWithPath: CurrentAppContext().appDatabaseBaseDirectoryPath(),
            isDirectory: true
        )
    }

    public static var grdbDatabaseFileUrl: URL {
        return GRDBDatabaseStorageAdapter.databaseFileUrl()
    }

    func runGrdbSchemaMigrations() {
        let didPerformIncrementalMigrations: Bool
        do {
            didPerformIncrementalMigrations = try GRDBSchemaMigrator.migrateDatabase(databaseStorage: self, runDataMigrations: false)
        } catch {
            DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Database migration failed. Error: \(error.grdbErrorForLogging)")
        }

        if didPerformIncrementalMigrations {
            do {
                try reopenGRDBStorage()
            } catch {
                owsFail("Unable to reopen storage \(error.grdbErrorForLogging)")
            }
        }
    }

    /// Note: This *technically* runs schema migrations as well, though it
    /// should be impossible to execute this method when there are any
    /// outstanding schema migrations.
    func runGrdbDataMigrations() {
        do {
            try GRDBSchemaMigrator.migrateDatabase(databaseStorage: self, runDataMigrations: true)
        } catch {
            DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Database migration failed. Error: \(error.grdbErrorForLogging)")
        }
    }

    private func reopenGRDBStorage() throws {
        // There seems to be a rare issue where at least one reader or writer
        // (e.g. SQLite connection) in the GRDB pool ends up "stale" after
        // a schema migration and does not reflect the migrations.
        grdbStorage.pool.releaseMemory()
        #if compiler(>=6.2.3)
        weak let weakPool: DatabasePool?
        weak let weakGrdbStorage: GRDBDatabaseStorageAdapter?
        #else
        weak var weakPool: DatabasePool?
        weak var weakGrdbStorage: GRDBDatabaseStorageAdapter?
        #endif
        weakPool = grdbStorage.pool
        weakGrdbStorage = grdbStorage
        owsAssertDebug(weakPool != nil)
        owsAssertDebug(weakGrdbStorage != nil)
        grdbStorage = try GRDBDatabaseStorageAdapter(
            databaseChangeObserver: _databaseChangeObserver,
            databaseFileUrl: databaseFileUrl,
            keyFetcher: keyFetcher
        )

        // We want to make sure all db connections from the old adapter/pool are closed.
        //
        // We only reach this point by a predictable code path; the autoreleasepool
        // should be drained by this point.
        owsAssertDebug(weakPool == nil)
        owsAssertDebug(weakGrdbStorage == nil)
    }

    // MARK: - Id Mapping

    public func updateIdMapping(thread: TSThread, transaction tx: DBWriteTransaction) {
        DatabaseChangeObserverImpl.serializedSync {
            _databaseChangeObserver.updateIdMapping(thread: thread, transaction: tx)
        }
    }

    public func updateIdMapping(interaction: TSInteraction, transaction tx: DBWriteTransaction) {
        DatabaseChangeObserverImpl.serializedSync {
            _databaseChangeObserver.updateIdMapping(interaction: interaction, transaction: tx)
        }
    }

    // MARK: - Touch

    public func touch(interaction: TSInteraction, shouldReindex: Bool, tx: DBWriteTransaction) {
        DatabaseChangeObserverImpl.serializedSync {
            _databaseChangeObserver.didTouch(interaction: interaction, transaction: tx)
        }
        if shouldReindex, let message = interaction as? TSMessage {
            do {
                try FullTextSearchIndexer.update(message, tx: tx)
            } catch {
                owsFail("Error: \(error)")
            }
        }
    }

    @objc
    public func touch(thread: TSThread, shouldReindex: Bool, shouldUpdateChatListUi: Bool = true, tx: DBWriteTransaction) {
        DatabaseChangeObserverImpl.serializedSync {
            _databaseChangeObserver.didTouch(thread: thread, shouldUpdateChatListUi: shouldUpdateChatListUi, transaction: tx)
        }
        if shouldReindex {
            let searchableNameIndexer = DependenciesBridge.shared.searchableNameIndexer
            searchableNameIndexer.update(thread, tx: tx)
        }
    }

    public func touch(storyMessage: StoryMessage, tx: DBWriteTransaction) {
        DatabaseChangeObserverImpl.serializedSync {
            _databaseChangeObserver.didTouch(storyMessage: storyMessage, transaction: tx)
        }
    }

    // MARK: - Observer

    public func add(transactionObserver: any GRDB.TransactionObserver, extent: GRDB.Database.TransactionObservationExtent) {
        grdbStorage.pool.add(transactionObserver: transactionObserver, extent: extent)
    }

    // MARK: - Cross Process Notifications

    @MainActor
    private func handleCrossProcessWrite() {
        AssertIsOnMainThread()

        guard CurrentAppContext().isMainApp else {
            return
        }

        // Post these notifications always, sync.
        NotificationCenter.default.post(name: SDSDatabaseStorage.didReceiveCrossProcessNotificationAlwaysSync, object: nil, userInfo: nil)

        // Post these notifications async and defer if inactive.
        if CurrentAppContext().isMainAppAndActive {
            // If already active, update immediately.
            postCrossProcessNotificationActiveAsync()
        } else {
            // If not active, set flag to update when we become active.
            hasPendingCrossProcessWrite = true
        }
    }

    @objc
    func didBecomeActive() {
        AssertIsOnMainThread()

        guard hasPendingCrossProcessWrite else {
            return
        }
        hasPendingCrossProcessWrite = false

        postCrossProcessNotificationActiveAsync()
    }

    public static let didReceiveCrossProcessNotificationActiveAsync = Notification.Name("didReceiveCrossProcessNotificationActiveAsync")
    public static let didReceiveCrossProcessNotificationAlwaysSync = Notification.Name("didReceiveCrossProcessNotificationAlwaysSync")

    private func postCrossProcessNotificationActiveAsync() {
        Logger.info("")

        // TODO: The observers of this notification will inevitably do
        //       expensive work.  It'd be nice to only fire this event
        //       if this had any effect, if the state of the database
        //       has changed.
        //
        //       In the meantime, most (all?) cross process write notifications
        //       will be delivered to the main app while it is inactive. By
        //       de-bouncing notifications while inactive and only updating
        //       once when we become active, we should be able to effectively
        //       skip most of the perf cost.
        NotificationCenter.default.postOnMainThread(name: SDSDatabaseStorage.didReceiveCrossProcessNotificationActiveAsync, object: nil)
    }

    // MARK: - Reading & Writing

    public func readThrows<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) throws -> T
    ) throws -> T {
        try grdbStorage.read { try block($0) }
    }

    public func read(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) -> Void
    ) {
        do {
            try readThrows(file: file, function: function, line: line, block: block)
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("error: \(error.grdbErrorForLogging)")
        }
    }

    @objc(readWithBlock:)
    public func readObjC(block: (DBReadTransaction) -> Void) {
        read(file: "objc", function: "block", line: 0, block: block)
    }

    public func read<T, E: Error>(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) throws(E) -> T
    ) throws(E) -> T {
        return try _read(file: file, function: function, line: line, block: block)
    }

    private func _read<T, E: Error>(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) throws(E) -> T,
    ) throws(E) -> T {
        var value: T!
        var thrown: E?
        read(file: file, function: function, line: line) { tx in
            do throws(E) {
                value = try block(tx)
            } catch {
                thrown = error
            }
        }
        if let thrown {
            throw thrown
        }
        return value
    }

    /// Perform the given write,
    public func performWriteWithTxCompletion(
        file: String,
        function: String,
        line: Int,
        isAwaitableWrite: Bool = false,
        block: (DBWriteTransaction) -> Database.TransactionCompletion,
    ) throws {
        #if DEBUG
        // When running in a Task, we should ensure that callers don't use
        // synchronous writes, as that could block forward progress for other
        // tasks. This seems like a reasonable way to check for this in debug
        // builds without adding overhead for other types of builds.
        withUnsafeCurrentTask {
            owsAssertDebug(isAwaitableWrite || Thread.isMainThread || $0 == nil, "Must use awaitableWrite in Tasks.")
        }
        #endif

        let benchTitle = "Slow Write Transaction \(Self.owsFormatLogMessage(file: file, function: function, line: line))"
        let timeoutThreshold = DebugFlags.internalLogging ? 0.1 : 0.5

        defer {
            Task { @MainActor in
                crossProcess.notifyChanged()
            }
        }

        try grdbStorage.writeWithTxCompletion { tx in
            Bench(title: benchTitle, logIfLongerThan: timeoutThreshold, logInProduction: true) {
                block(tx)
            }
        }
    }

    public func write<T, E>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws(E) -> T
    ) throws(E) -> T {
        return try _writeWithTxCompletionIfThrows(
            file: file,
            function: function,
            line: line,
            isAwaitableWrite: false,
            completionIfThrows: .commit,
            block: block,
        )
    }

    public func writeWithRollbackIfThrows<T, E>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws(E) -> T
    ) throws(E) -> T {
        return try _writeWithTxCompletionIfThrows(
            file: file,
            function: function,
            line: line,
            isAwaitableWrite: false,
            completionIfThrows: .rollback,
            block: block,
        )
    }

    private func _writeWithTxCompletionIfThrows<T, E>(
        file: String,
        function: String,
        line: Int,
        isAwaitableWrite: Bool,
        completionIfThrows: Database.TransactionCompletion,
        block: (DBWriteTransaction) throws(E) -> T,
    ) throws(E) -> T {
        var value: T!
        var thrown: E?
        do {
            try performWriteWithTxCompletion(
                file: file,
                function: function,
                line: line,
                isAwaitableWrite: isAwaitableWrite
            ) { tx in
                do throws(E) {
                    value = try block(tx)
                    return .commit
                } catch {
                    thrown = error
                    return completionIfThrows
                }
            }
        } catch {
            owsFail("error: \(error.grdbErrorForLogging)")
        }
        if let thrown {
            throw thrown
        }
        return value
    }

    // MARK: - Async

    public func asyncRead<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBReadTransaction) -> T,
        completionQueue: DispatchQueue = .main,
        completion: ((T) -> Void)? = nil
    ) {
        DispatchQueue.global().async {
            let result = self.read(file: file, function: function, line: line, block: block)

            if let completion {
                completionQueue.async(execute: { completion(result) })
            }
        }
    }

    public func asyncWrite(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) -> Void
    ) {
        asyncWrite(file: file, function: function, line: line, block: block, completion: nil)
    }

    public func asyncWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) -> T,
        completion: ((T) -> Void)?
    ) {
        asyncWrite(file: file, function: function, line: line, block: block, completionQueue: .main, completion: completion)
    }

    public func asyncWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) -> T,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    ) {
        self.asyncWriteQueue.async {
            let result = self.write(file: file, function: function, line: line, block: block)
            if let completion {
                completionQueue.async(execute: { completion(result) })
            }
        }
    }

    // MARK: - Awaitable

    public func awaitableWrite<T, E>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws(E) -> T
    ) async throws(E) -> T {
        return try await self.awaitableWriteQueue.runWithoutTaskCancellationHandler { () throws(E) -> T in
            return try self._writeWithTxCompletionIfThrows(
                file: file,
                function: function,
                line: line,
                isAwaitableWrite: true,
                completionIfThrows: .commit,
                block: block
            )
        }
    }

    public func awaitableWriteWithRollbackIfThrows<T, E>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws(E) -> T
    ) async throws(E) -> T {
        return try await self.awaitableWriteQueue.runWithoutTaskCancellationHandler { () throws(E) -> T in
            return try self._writeWithTxCompletionIfThrows(
                file: file,
                function: function,
                line: line,
                isAwaitableWrite: true,
                completionIfThrows: .rollback,
                block: block
            )
        }
    }

    // MARK: - Obj-C Bridge

    /// NOTE: Do NOT call these methods directly. See SDSDatabaseStorage+Objc.h.
    @available(*, deprecated, message: "Use DatabaseStorageWrite() instead")
    @objc
    func __private_objc_write(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) -> Void
    ) {
        do {
            try performWriteWithTxCompletion(
                file: file,
                function: function,
                line: line,
                isAwaitableWrite: false,
                block: {
                    block($0)
                    // The block can't throw; always commit.
                    return .commit
                }
            )
        } catch {
            owsFail("error: \(error.grdbErrorForLogging)")
        }
    }

    /// NOTE: Do NOT call these methods directly. See SDSDatabaseStorage+Objc.h.
    @available(*, deprecated, message: "Use DatabaseStorageAsyncWrite() instead")
    @objc
    func __private_objc_asyncWrite(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) -> Void
    ) {
        asyncWrite(file: file, function: function, line: line, block: block, completion: nil)
    }

    private static func owsFormatLogMessage(file: String = #file, function: String = #function, line: Int = #line) -> String {
        let filename = (file as NSString).lastPathComponent
        // We format the filename & line number in a format compatible
        // with XCode's "Open Quickly..." feature.
        return "[\(filename):\(line) \(function)]"
    }
}

// MARK: -

@inlinable
@inline(__always)
public func DEBUG_INDEXED_BY(_ indexName: @autoclosure () -> String, or oldIndexName: @autoclosure () -> String? = nil) -> String {
    // In DEBUG builds, confirm that we use the expected index.
    #if DEBUG
    if oldIndexName() != nil {
        // If we're in an ambiguous state, we can't enforce a single index. (This
        // state should be temporary and eventually replaced by a blocking
        // migration.)
        return ""
    } else {
        return "INDEXED BY \(indexName())"
    }
    #else
    return ""
    #endif
}

// MARK: -

public enum SDS {
    public static func fitsInInt64(_ value: UInt64) -> Bool {
        return value <= Int64.max
    }
}

// MARK: -

extension SDSDatabaseStorage {
    public func logFileSizes() {
        Logger.info("Database: \(databaseFileSize), WAL: \(databaseWALFileSize), SHM: \(databaseSHMFileSize)")
    }

    public var databaseFileSize: UInt64 {
        grdbStorage.databaseFileSize
    }

    public var databaseWALFileSize: UInt64 {
        grdbStorage.databaseWALFileSize
    }

    public var databaseSHMFileSize: UInt64 {
        grdbStorage.databaseSHMFileSize
    }

    public var databaseCombinedFileSize: UInt64 {
        databaseFileSize + databaseWALFileSize + databaseSHMFileSize
    }
}
