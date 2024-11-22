//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

// MARK: -

@objc
public class SDSDatabaseStorage: NSObject {

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

    func runGrdbSchemaMigrationsOnMainDatabase(completionScheduler: Scheduler, completion: @escaping () -> Void) {
        let didPerformIncrementalMigrations: Bool = {
            do {
                return try GRDBSchemaMigrator.migrateDatabase(
                    databaseStorage: self,
                    isMainDatabase: true
                )
            } catch {
                DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
                    userDefaults: CurrentAppContext().appUserDefaults(),
                    error: error
                )
                owsFail("Database migration failed. Error: \(error.grdbErrorForLogging)")
            }
        }()

        if didPerformIncrementalMigrations {
            do {
                try reopenGRDBStorage(completionScheduler: completionScheduler, completion: completion)
            } catch {
                owsFail("Unable to reopen storage \(error.grdbErrorForLogging)")
            }
        } else {
            completionScheduler.async(completion)
        }
    }

    public func reopenGRDBStorage(completionScheduler: Scheduler, completion: @escaping () -> Void = {}) throws {
        // There seems to be a rare issue where at least one reader or writer
        // (e.g. SQLite connection) in the GRDB pool ends up "stale" after
        // a schema migration and does not reflect the migrations.
        grdbStorage.pool.releaseMemory()
        weak var weakPool = grdbStorage.pool
        weak var weakGrdbStorage = grdbStorage
        owsAssertDebug(weakPool != nil)
        owsAssertDebug(weakGrdbStorage != nil)
        grdbStorage = try GRDBDatabaseStorageAdapter(
            databaseChangeObserver: _databaseChangeObserver,
            databaseFileUrl: databaseFileUrl,
            keyFetcher: keyFetcher
        )

        completionScheduler.async {
            // We want to make sure all db connections from the old adapter/pool are closed.
            //
            // We only reach this point by a predictable code path; the autoreleasepool
            // should be drained by this point.
            owsAssertDebug(weakPool == nil)
            owsAssertDebug(weakGrdbStorage == nil)

            completion()
        }
    }

    // MARK: - Id Mapping

    public func updateIdMapping(thread: TSThread, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdb):
            DatabaseChangeObserverImpl.serializedSync {
                _databaseChangeObserver.updateIdMapping(thread: thread, transaction: grdb)
            }
        }
    }

    public func updateIdMapping(interaction: TSInteraction, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdb):
            DatabaseChangeObserverImpl.serializedSync {
                _databaseChangeObserver.updateIdMapping(interaction: interaction, transaction: grdb)
            }
        }
    }

    // MARK: - Touch

    public func touch(interaction: TSInteraction, shouldReindex: Bool, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdb):
            DatabaseChangeObserverImpl.serializedSync {
                _databaseChangeObserver.didTouch(interaction: interaction, transaction: grdb)
            }
        }
        if shouldReindex, let message = interaction as? TSMessage {
            do {
                try FullTextSearchIndexer.update(message, tx: transaction)
            } catch {
                owsFail("Error: \(error)")
            }
        }
    }

    /// See note on `shouldUpdateChatListUi` parameter in docs for ``TSGroupThread.updateWithGroupModel:shouldUpdateChatListUi:transaction``.
    @objc(touchThread:shouldReindex:shouldUpdateChatListUi:transaction:)
    public func touch(thread: TSThread, shouldReindex: Bool, shouldUpdateChatListUi: Bool, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdb):
            DatabaseChangeObserverImpl.serializedSync {
                _databaseChangeObserver.didTouch(thread: thread, shouldUpdateChatListUi: shouldUpdateChatListUi, transaction: grdb)
            }
        }
        if shouldReindex {
            let searchableNameIndexer = DependenciesBridge.shared.searchableNameIndexer
            searchableNameIndexer.update(thread, tx: transaction.asV2Write)
        }
    }

    @objc(touchThread:shouldReindex:transaction:)
    public func touch(thread: TSThread, shouldReindex: Bool, transaction: SDSAnyWriteTransaction) {
        touch(thread: thread, shouldReindex: shouldReindex, shouldUpdateChatListUi: true, transaction: transaction)
    }

    public func touch(storyMessage: StoryMessage, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdb):
            DatabaseChangeObserverImpl.serializedSync {
                _databaseChangeObserver.didTouch(storyMessage: storyMessage, transaction: grdb)
            }
        }
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
        NotificationCenter.default.postNotificationNameAsync(SDSDatabaseStorage.didReceiveCrossProcessNotificationActiveAsync, object: nil)
    }

    // MARK: - Reading & Writing

    public func readThrows<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (SDSAnyReadTransaction) throws -> T
    ) throws -> T {
        try grdbStorage.read { try block($0.asAnyRead) }
    }

    public func read(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (SDSAnyReadTransaction) -> Void
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
    public func readObjC(block: (SDSAnyReadTransaction) -> Void) {
        read(file: "objc", function: "block", line: 0, block: block)
    }

    @discardableResult
    public func read<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (SDSAnyReadTransaction) throws -> T
    ) rethrows -> T {
        return try _read(file: file, function: function, line: line, block: block, rescue: { throw $0 })
    }

    // The "rescue" pattern is used in LibDispatch (and replicated here) to
    // allow "rethrows" to work properly.
    private func _read<T>(
        file: String,
        function: String,
        line: Int,
        block: (SDSAnyReadTransaction) throws -> T,
        rescue: (Error) throws -> Never
    ) rethrows -> T {
        var value: T!
        var thrown: Error?
        read(file: file, function: function, line: line) { tx in
            do {
                value = try block(tx)
            } catch {
                thrown = error
            }
        }
        if let thrown {
            try rescue(thrown.grdbErrorForLogging)
        }
        return value
    }

    public func performWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        isAwaitableWrite: Bool = false,
        block: (SDSAnyWriteTransaction) -> TransactionCompletion<T>
    ) throws -> T {
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

        return try grdbStorage.writeWithTxCompletion { tx in
            return Bench(title: benchTitle, logIfLongerThan: timeoutThreshold, logInProduction: true) {
                return block(tx.asAnyWrite)
            }
        }
    }

    // NOTE: This method is not @objc. See SDSDatabaseStorage+Objc.h.
    public func write(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (SDSAnyWriteTransaction) -> Void
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
                    return .commit(())
                }
            )
        } catch {
            owsFail("error: \(error.grdbErrorForLogging)")
        }
    }

    @discardableResult
    public func write<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (SDSAnyWriteTransaction) throws -> T
    ) rethrows -> T {
        return try _writeCommitIfThrows(file: file, function: function, line: line, isAwaitableWrite: false, block: block, rescue: { throw $0 })
    }

    @discardableResult
    public func writeWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (SDSAnyWriteTransaction) -> TransactionCompletion<T>
    ) -> T {
        do {
            return try performWriteWithTxCompletion(
                file: file,
                function: function,
                line: line,
                isAwaitableWrite: false,
                block: block
            )
        } catch {
            owsFail("error: \(error.grdbErrorForLogging)")
        }
    }

    // The "rescue" pattern is used in LibDispatch (and replicated here) to
    // allow "rethrows" to work properly.
    private func _writeCommitIfThrows<T>(
        file: String,
        function: String,
        line: Int,
        isAwaitableWrite: Bool,
        block: (SDSAnyWriteTransaction) throws -> T,
        rescue: (Error) throws -> Never
    ) rethrows -> T {
        var value: T!
        var thrown: Error?
        do {
            try performWriteWithTxCompletion(
                file: file,
                function: function,
                line: line,
                isAwaitableWrite: isAwaitableWrite
            ) { tx in
                do {
                    value = try block(tx)
                } catch {
                    thrown = error
                }
                // Always commit regardless of thrown errors.
                return .commit(())
            }
        } catch {
            owsFail("error: \(error.grdbErrorForLogging)")
        }
        if let thrown {
            try rescue(thrown.grdbErrorForLogging)
        }
        return value
    }

    // MARK: - Async

    public func asyncRead<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (SDSAnyReadTransaction) -> T,
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
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (SDSAnyWriteTransaction) -> Void
    ) {
        asyncWrite(file: file, function: function, line: line, block: block, completion: nil)
    }

    public func asyncWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (SDSAnyWriteTransaction) -> T,
        completion: ((T) -> Void)?
    ) {
        asyncWrite(file: file, function: function, line: line, block: block, completionQueue: .main, completion: completion)
    }

    public func asyncWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (SDSAnyWriteTransaction) -> TransactionCompletion<T>,
        completion: ((T) -> Void)?
    ) {
        asyncWriteWithTxCompletion(file: file, function: function, line: line, block: block, completionQueue: .main, completion: completion)
    }

    public func asyncWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (SDSAnyWriteTransaction) -> T,
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

    public func asyncWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (SDSAnyWriteTransaction) -> TransactionCompletion<T>,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    ) {
        self.asyncWriteQueue.async {
            let result = self.writeWithTxCompletion(file: file, function: function, line: line, block: block)
            if let completion {
                completionQueue.async(execute: { completion(result) })
            }
        }
    }

    // MARK: - Awaitable

    public func awaitableWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (SDSAnyWriteTransaction) throws -> T
    ) async rethrows -> T {
        return try await self.awaitableWriteQueue.run {
            return try self._writeCommitIfThrows(file: file, function: function, line: line, isAwaitableWrite: true, block: block, rescue: { throw $0 })
        }
    }

    public func awaitableWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (SDSAnyWriteTransaction) -> TransactionCompletion<T>
    ) async -> T {
        return await self.awaitableWriteQueue.run {
            do {
                return try self.performWriteWithTxCompletion(
                    file: file,
                    function: function,
                    line: line,
                    isAwaitableWrite: true,
                    block: block
                )
            } catch {
                owsFail("error: \(error.grdbErrorForLogging)")
            }
        }
    }

    // MARK: - Promises

    public func read<T>(
        _: PromiseNamespace,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (SDSAnyReadTransaction) throws -> T
    ) -> Promise<T> {
        return Promise { future in
            DispatchQueue.global().async {
                do {
                    future.resolve(try self.read(file: file, function: function, line: line, block: block))
                } catch {
                    future.reject(error)
                }
            }
        }
    }

    public func write<T>(
        _: PromiseNamespace,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (SDSAnyWriteTransaction) throws -> T
    ) -> Promise<T> {
        return Promise { future in
            self.asyncWriteQueue.async {
                do {
                    future.resolve(try self.write(file: file, function: function, line: line, block: block))
                } catch {
                    future.reject(error)
                }
            }
        }
    }

    // MARK: - Obj-C Bridge

    /// NOTE: Do NOT call these methods directly. See SDSDatabaseStorage+Objc.h.
    @available(*, deprecated, message: "Use DatabaseStorageWrite() instead")
    @objc
    func __private_objc_write(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (SDSAnyWriteTransaction) -> Void
    ) {
        write(file: file, function: function, line: line, block: block)
    }

    /// NOTE: Do NOT call these methods directly. See SDSDatabaseStorage+Objc.h.
    @available(*, deprecated, message: "Use DatabaseStorageAsyncWrite() instead")
    @objc
    func __private_objc_asyncWrite(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (SDSAnyWriteTransaction) -> Void
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

protocol SDSDatabaseStorageAdapter {
    associatedtype ReadTransaction
    associatedtype WriteTransaction
    func read(block: (ReadTransaction) -> Void) throws
    func writeWithTxCompletion(block: (WriteTransaction) -> TransactionCompletion<Void>) throws
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
