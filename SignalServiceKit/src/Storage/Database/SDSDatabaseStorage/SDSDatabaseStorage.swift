//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

@objc
public protocol SDSDatabaseStorageDelegate {
    var storageCoordinatorState: StorageCoordinatorState { get }
}

// MARK: -

@objc
public class SDSDatabaseStorage: NSObject {

    private let asyncWriteQueue = DispatchQueue(label: "org.signal.database.write-async", qos: .userInitiated)

    private weak var delegate: SDSDatabaseStorageDelegate?

    private var hasPendingCrossProcessWrite = false

    private let crossProcess = SDSCrossProcess()

    // MARK: - Initialization / Setup

    private let databaseFileUrl: URL

    private var _grdbStorage: GRDBDatabaseStorageAdapter?

    @objc
    public var grdbStorage: GRDBDatabaseStorageAdapter {
        if let storage = _grdbStorage {
            return storage
        } else {
            do {
                let storage = try createGrdbStorage()
                _grdbStorage = storage
                return storage
            } catch {
                owsFail("Unable to initialize storage \(error.grdbErrorForLogging)")
            }
        }
    }

    @objc
    public required init(databaseFileUrl: URL, delegate: SDSDatabaseStorageDelegate) {
        self.databaseFileUrl = databaseFileUrl
        self.delegate = delegate

        super.init()

        addObservers()
    }

    private func addObservers() {
        guard !CurrentAppContext().isRunningTests else {
            return
        }
        // Cross process writes
        crossProcess.callback = { [weak self] in
            DispatchQueue.main.async {
                self?.handleCrossProcessWrite()
            }
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }

    deinit {
        Logger.verbose("")
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

    @objc
    public static let storageDidReload = Notification.Name("storageDidReload")

    // completion is performed on the main queue.
    @objc
    public func runGrdbSchemaMigrationsOnMainDatabase(completion: @escaping () -> Void) {
        guard storageCoordinatorState == .GRDB else {
            owsFailDebug("Not GRDB.")
            return
        }

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
                try reopenGRDBStorage(completion: completion)
            } catch {
                owsFail("Unable to reopen storage \(error.grdbErrorForLogging)")
            }
        } else {
            DispatchQueue.main.async(execute: completion)
        }
    }

    public func reopenGRDBStorage(completion: @escaping () -> Void = {}) throws {
        // There seems to be a rare issue where at least one reader or writer
        // (e.g. SQLite connection) in the GRDB pool ends up "stale" after
        // a schema migration and does not reflect the migrations.
        grdbStorage.pool.releaseMemory()
        weak var weakPool = grdbStorage.pool
        weak var weakGrdbStorage = grdbStorage
        owsAssertDebug(weakPool != nil)
        owsAssertDebug(weakGrdbStorage != nil)
        _grdbStorage = try createGrdbStorage()

        DispatchQueue.main.async {
            // We want to make sure all db connections from the old adapter/pool are closed.
            //
            // We only reach this point by a predictable code path; the autoreleasepool
            // should be drained by this point.
            owsAssertDebug(weakPool == nil)
            owsAssertDebug(weakGrdbStorage == nil)

            completion()
        }
    }

    public enum TransferredDbReloadResult {
        /// Doesn't ever actually happen, but one can hope I guess?
        /// Should just relaunch the app anyway.
        case success
        /// DB did its thing, but crashed when reading, due to SQLCipher
        /// key caching. Should be counted as a "successful" transfer, as
        /// closing and relaunching the app should resolve issues.
        ///
        /// Some context on this: this is resolvable in that we can make it not crash with
        /// some more investigation/effort. The root issue is the old DB (that we set up before
        /// transferring) and the new DB (from the source device) don't use the same SQLCipher
        /// keys, and we need to tell GRDB and SQLCipher to wipe their in memory caches and
        /// use the new keys. But even if that's done, a ton of in memory caches everywhere,
        /// from the SQLite level up to our own classes, keep stale information and cause all
        /// kinds of downstream chaos.
        /// The real fix here is to not set up the full database prior
        /// to transfer and/or registration; we should have a limited DB (just a key value store, really)
        /// for that flow, so we have no state to reset when transferring the "real" DB.
        case relaunchRequired

        /// Fatal errors; do not count as a success. Likely due to
        /// developer error.
        case failedMigration(error: Error)
        case unknownError(error: Error)
    }

    public func reloadTransferredDatabase() -> Guarantee<TransferredDbReloadResult> {
        AssertIsOnMainThread()
        assert(storageCoordinatorState == .GRDB)

        Logger.info("")

        let wasRegistered = DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered

        let (promise, future) = Guarantee<TransferredDbReloadResult>.pending()
        let completion: () -> Void = {
            do {
                try GRDBSchemaMigrator.migrateDatabase(
                    databaseStorage: self,
                    isMainDatabase: true
                )
            } catch {
                owsFailDebug("Database migration failed. Error: \(error.grdbErrorForLogging)")
                future.resolve(.failedMigration(error: error))
            }

            self.grdbStorage.publishUpdatesImmediately()

            // We need to do this _before_ warmCaches().
            NotificationCenter.default.post(name: Self.storageDidReload, object: nil, userInfo: nil)

            SSKEnvironment.shared.warmCaches()

            if wasRegistered != DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered {
                NotificationCenter.default.post(name: .registrationStateDidChange, object: nil, userInfo: nil)
            }
            future.resolve(.success)
        }
        do {
            try reopenGRDBStorage(completion: completion)
        } catch {
            // A SQL logic error when reading the master table
            // is probably (but not necessarily! this is a hack!)
            // due to SQLCipher key cache mismatch, which should
            // resolve on relaunch.
            if
                let grdbError = error as? GRDB.DatabaseError,
                grdbError.resultCode.rawValue == 1,
                grdbError.sql == "SELECT * FROM sqlite_master LIMIT 1"
            {
                future.resolve(.relaunchRequired)
            } else {
                future.resolve(.unknownError(error: error))
            }
        }
        return promise
    }

    func createGrdbStorage() throws -> GRDBDatabaseStorageAdapter {
        return try GRDBDatabaseStorageAdapter(databaseFileUrl: databaseFileUrl)
    }

    @objc
    public func deleteGrdbFiles() {
        GRDBDatabaseStorageAdapter.removeAllFiles()
    }

    public func resetAllStorage() {
        YDBStorage.deleteYDBStorage()
        GRDBDatabaseStorageAdapter.resetAllStorage()
    }

    // MARK: - Observation

    @objc
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
                } else if AppReadiness.isAppReady {
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
                } else if AppReadiness.isAppReady {
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
                } else if AppReadiness.isAppReady {
                    owsFailDebug("databaseChangeObserver was unexpectedly nil")
                }
            }
            if shouldReindex {
                GRDBFullTextSearchFinder.modelWasUpdated(model: interaction, transaction: grdb)
            }
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
                } else if AppReadiness.isAppReady {
                    // This can race with observation setup when app becomes ready.
                    Logger.warn("databaseChangeObserver was unexpectedly nil")
                }
            }
            if shouldReindex {
                GRDBFullTextSearchFinder.modelWasUpdated(model: thread, transaction: grdb)
            }
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
                } else if AppReadiness.isAppReady {
                    owsFailDebug("databaseChangeObserver was unexpectedly nil")
                }
            }
        }
    }

    // MARK: - Cross Process Notifications

    private func handleCrossProcessWrite() {
        AssertIsOnMainThread()

        Logger.info("")

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
        rescue: (Error) throws -> Void
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

    // NOTE: This method is not @objc. See SDSDatabaseStorage+Objc.h.
    public func write(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (SDSAnyWriteTransaction) -> Void
    ) {
        #if TESTABLE_BUILD
        if Thread.isMainThread && AppReadiness.isAppReady {
            Logger.warn("Database write on main thread.")
        }
        #endif

        #if DEBUG
        // When running in a Task, we should ensure that callers don't use
        // synchronous writes, as that could block forward progress for other
        // tasks. This seems like a reasonable way to check for this in debug
        // builds without adding overhead for other types of builds.
        withUnsafeCurrentTask {
            owsAssertDebug($0 == nil, "Must use awaitableWrite in Tasks.")
        }
        #endif

        let benchTitle = "Slow Write Transaction \(Self.owsFormatLogMessage(file: file, function: function, line: line))"
        let timeoutThreshold = DebugFlags.internalLogging ? 0.1 : 0.5

        do {
            try grdbStorage.write { transaction in
                Bench(title: benchTitle, logIfLongerThan: timeoutThreshold, logInProduction: true) {
                    block(transaction.asAnyWrite)
                }
            }
        } catch {
            owsFail("error: \(error.grdbErrorForLogging)")
        }

        crossProcess.notifyChangedAsync()
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
        rescue: (Error) throws -> Void
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

    public func asyncRead(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (SDSAnyReadTransaction) -> Void,
        completionQueue: DispatchQueue = .main,
        completion: (() -> Void)? = nil
    ) {
        DispatchQueue.global().async {
            self.read(file: file, function: function, line: line, block: block)

            if let completion {
                completionQueue.async(execute: completion)
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

    public func asyncWrite(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (SDSAnyWriteTransaction) -> Void,
        completion: (() -> Void)?
    ) {
        asyncWrite(file: file, function: function, line: line, block: block, completionQueue: .main, completion: completion)
    }

    public func asyncWrite(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (SDSAnyWriteTransaction) -> Void,
        completionQueue: DispatchQueue,
        completion: (() -> Void)?
    ) {
        self.asyncWriteQueue.async {
            self.write(file: file, function: function, line: line, block: block)
            if let completion {
                completionQueue.async(execute: completion)
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
        rescue: @escaping (Error) throws -> Void
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
            fatalError()
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

// MARK: - Coordination

extension SDSDatabaseStorage {

    private var storageCoordinatorState: StorageCoordinatorState {
        guard let delegate = delegate else {
            owsFail("Missing delegate.")
        }
        return delegate.storageCoordinatorState
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
