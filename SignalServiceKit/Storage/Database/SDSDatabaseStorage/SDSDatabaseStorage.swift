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

    private var hasPendingCrossProcessWrite = false

    // Implicitly unwrapped because it is set in the initializer but after initialization completes because it
    // needs to refer to self.
    private var crossProcess: SDSCrossProcess!

    // MARK: - Initialization / Setup

    private let appReadiness: AppReadiness

    public let databaseFileUrl: URL
    public let keyFetcher: GRDBKeyFetcher

    private(set) public var grdbStorage: GRDBDatabaseStorageAdapter

    public init(appReadiness: AppReadiness, databaseFileUrl: URL, keychainStorage: any KeychainStorage) throws {
        self.appReadiness = appReadiness
        self.databaseFileUrl = databaseFileUrl
        self.keyFetcher = GRDBKeyFetcher(keychainStorage: keychainStorage)
        self.grdbStorage = try GRDBDatabaseStorageAdapter(
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

    @objc
    public class var baseDir: URL {
        return URL(
            fileURLWithPath: CurrentAppContext().appDatabaseBaseDirectoryPath(),
            isDirectory: true
        )
    }

    @objc
    public static var grdbDatabaseDirUrl: URL {
        return GRDBDatabaseStorageAdapter.databaseDirUrl()
    }

    @objc
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
        grdbStorage = try GRDBDatabaseStorageAdapter(databaseFileUrl: databaseFileUrl, keyFetcher: keyFetcher)

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

    @objc
    public func deleteGrdbFiles() {
        GRDBDatabaseStorageAdapter.removeAllFiles()
    }

    public func resetAllStorage() {
        YDBStorage.deleteYDBStorage()
        do {
            try keyFetcher.clear()
        } catch {
            owsFailDebug("Could not clear keychain: \(error)")
        }
        grdbStorage.resetAllStorage()
    }

    // MARK: - Observation

    public func appendDatabaseChangeDelegate(_ databaseChangeDelegate: DatabaseChangeDelegate) {
        guard let databaseChangeObserver = grdbStorage.databaseChangeObserver else {
            owsFailDebug("Missing databaseChangeObserver.")
            return
        }
        databaseChangeObserver.appendDatabaseChangeDelegate(databaseChangeDelegate)
    }

    // MARK: - Id Mapping

    @objc
    public func updateIdMapping(thread: TSThread, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdb):
            DatabaseChangeObserver.serializedSync {
                if let databaseChangeObserver = grdbStorage.databaseChangeObserver {
                    databaseChangeObserver.updateIdMapping(thread: thread, transaction: grdb)
                } else if appReadiness.isAppReady {
                    owsFailDebug("databaseChangeObserver was unexpectedly nil")
                }
            }
        }
    }

    @objc
    public func updateIdMapping(interaction: TSInteraction, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdb):
            DatabaseChangeObserver.serializedSync {
                if let databaseChangeObserver = grdbStorage.databaseChangeObserver {
                    databaseChangeObserver.updateIdMapping(interaction: interaction, transaction: grdb)
                } else if appReadiness.isAppReady {
                    owsFailDebug("databaseChangeObserver was unexpectedly nil")
                }
            }
        }
    }

    // MARK: - Touch

    @objc(touchInteraction:shouldReindex:transaction:)
    public func touch(interaction: TSInteraction, shouldReindex: Bool, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdb):
            DatabaseChangeObserver.serializedSync {
                if let databaseChangeObserver = grdbStorage.databaseChangeObserver {
                    databaseChangeObserver.didTouch(interaction: interaction, transaction: grdb)
                } else if appReadiness.isAppReady {
                    owsFailDebug("databaseChangeObserver was unexpectedly nil")
                }
            }
        }
        if shouldReindex, let message = interaction as? TSMessage {
            FullTextSearchIndexer.update(message, tx: transaction)
        }
    }

    /// See note on `shouldUpdateChatListUi` parameter in docs for ``TSGroupThread.updateWithGroupModel:shouldUpdateChatListUi:transaction``.
    @objc(touchThread:shouldReindex:shouldUpdateChatListUi:transaction:)
    public func touch(thread: TSThread, shouldReindex: Bool, shouldUpdateChatListUi: Bool, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdb):
            DatabaseChangeObserver.serializedSync {
                if let databaseChangeObserver = grdbStorage.databaseChangeObserver {
                    databaseChangeObserver.didTouch(thread: thread, shouldUpdateChatListUi: shouldUpdateChatListUi, transaction: grdb)
                } else if appReadiness.isAppReady {
                    // This can race with observation setup when app becomes ready.
                    Logger.warn("databaseChangeObserver was unexpectedly nil")
                }
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

    @objc(touchStoryMessage:transaction:)
    public func touch(storyMessage: StoryMessage, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdb):
            DatabaseChangeObserver.serializedSync {
                if let databaseChangeObserver = grdbStorage.databaseChangeObserver {
                    databaseChangeObserver.didTouch(storyMessage: storyMessage, transaction: grdb)
                } else if appReadiness.isAppReady {
                    owsFailDebug("databaseChangeObserver was unexpectedly nil")
                }
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

    @objc
    public static let didReceiveCrossProcessNotificationActiveAsync = Notification.Name("didReceiveCrossProcessNotificationActiveAsync")
    @objc
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

    @objc(readWithBlock:file:function:line:)
    public func readObjC(block: (SDSAnyReadTransaction) -> Void, file: UnsafePointer<CChar>, function: UnsafePointer<CChar>, line: Int) {
        read(file: String(cString: file), function: String(cString: function), line: line, block: block)
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

    public func writeThrows<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (SDSAnyWriteTransaction) throws -> T
    ) throws -> T {
        #if DEBUG
        // When running in a Task, we should ensure that callers don't use
        // synchronous writes, as that could block forward progress for other
        // tasks. This seems like a reasonable way to check for this in debug
        // builds without adding overhead for other types of builds.
        withUnsafeCurrentTask {
            owsAssertDebug(Thread.isMainThread || $0 == nil, "Must use awaitableWrite in Tasks.")
        }
        #endif

        let benchTitle = "Slow Write Transaction \(Self.owsFormatLogMessage(file: file, function: function, line: line))"
        let timeoutThreshold = DebugFlags.internalLogging ? 0.1 : 0.5

        defer {
            Task { @MainActor in
                crossProcess.notifyChanged()
            }
        }

        return try grdbStorage.write { tx in
            return try Bench(title: benchTitle, logIfLongerThan: timeoutThreshold, logInProduction: true) {
                return try block(tx.asAnyWrite)
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
            return try writeThrows(file: file, function: function, line: line, block: block)
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
        return try _write(file: file, function: function, line: line, block: block, rescue: { throw $0 })
    }

    // The "rescue" pattern is used in LibDispatch (and replicated here) to
    // allow "rethrows" to work properly.
    private func _write<T>(
        file: String,
        function: String,
        line: Int,
        block: (SDSAnyWriteTransaction) throws -> T,
        rescue: (Error) throws -> Never
    ) rethrows -> T {
        var value: T!
        var thrown: Error?
        write(file: file, function: function, line: line) { tx in
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

    // MARK: - Async

    @objc(asyncReadWithBlock:)
    public func asyncReadObjC(block: @escaping (SDSAnyReadTransaction) -> Void) {
        asyncRead(file: "objc", function: "block", line: 0, block: block)
    }

    @objc(asyncReadWithBlock:completion:)
    public func asyncReadObjC(block: @escaping (SDSAnyReadTransaction) -> Void, completion: @escaping () -> Void) {
        asyncRead(file: "objc", function: "block", line: 0, block: block, completion: completion)
    }

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

    // MARK: - Awaitable

    public func awaitableWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (SDSAnyWriteTransaction) throws -> T
    ) async rethrows -> T {
        return try await _awaitableWrite(file: file, function: function, line: line, block: block, rescue: { throw $0 })
    }

    private func _awaitableWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (SDSAnyWriteTransaction) throws -> T,
        rescue: (Error) throws -> Never
    ) async rethrows -> T {
        let result: Result<T, Error> = await withCheckedContinuation { continuation in
            asyncWriteQueue.async {
                do {
                    let result = try self.write(file: file, function: function, line: line, block: block)
                    continuation.resume(returning: .success(result))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            try rescue(error)
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

    public static func owsFormatLogMessage(file: String = #file,
                                           function: String = #function,
                                           line: Int = #line) -> String {
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
    func write(block: (WriteTransaction) -> Void) throws
}

// MARK: -

@objc
public class SDS: NSObject {
    @objc
    public class func fitsInInt64(_ value: UInt64) -> Bool {
        return value <= Int64.max
    }

    @objc
    public func fitsInInt64(_ value: UInt64) -> Bool {
        return SDS.fitsInInt64(value)
    }

    @objc(fitsInInt64WithNSNumber:)
    public class func fitsInInt64(nsNumber value: NSNumber) -> Bool {
        return fitsInInt64(value.uint64Value)
    }

    @objc(fitsInInt64WithNSNumber:)
    public func fitsInInt64(nsNumber value: NSNumber) -> Bool {
        return SDS.fitsInInt64(nsNumber: value)
    }
}

// MARK: -

@objc
public extension SDSDatabaseStorage {
    func logFileSizes() {
        Logger.info("Database: \(databaseFileSize), WAL: \(databaseWALFileSize), SHM: \(databaseSHMFileSize)")
    }

    var databaseFileSize: UInt64 {
        grdbStorage.databaseFileSize
    }

    var databaseWALFileSize: UInt64 {
        grdbStorage.databaseWALFileSize
    }

    var databaseSHMFileSize: UInt64 {
        grdbStorage.databaseSHMFileSize
    }

    var databaseCombinedFileSize: UInt64 {
        databaseFileSize + databaseWALFileSize + databaseSHMFileSize
    }
}
