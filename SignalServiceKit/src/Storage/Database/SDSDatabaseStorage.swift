//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public protocol SDSDatabaseStorageDelegate {
    var storageCoordinatorState: StorageCoordinatorState { get }
}

// MARK: -

@objc
public class SDSDatabaseStorage: SDSTransactable {

    private weak var delegate: SDSDatabaseStorageDelegate?

    static public var shouldLogDBQueries: Bool = DebugFlags.logSQLQueries

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
            let storage = createGrdbStorage()
            _grdbStorage = storage
            return storage
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

        Logger.info("")

        let didPerformIncrementalMigrations: Bool = {
            do {
                return try GRDBSchemaMigrator.migrateDatabase(
                    databaseStorage: self,
                    isMainDatabase: true
                )
            } catch {
                owsFail("Database migration failed. Error: \(error.grdbErrorForLogging)")
            }
        }()

        Logger.info("didPerformIncrementalMigrations: \(didPerformIncrementalMigrations)")

        if didPerformIncrementalMigrations {
            reopenGRDBStorage(completion: completion)
        } else {
            DispatchQueue.main.async(execute: completion)
        }
    }

    public func reopenGRDBStorage(completion: @escaping () -> Void = {}) {
        let benchSteps = BenchSteps()

        // There seems to be a rare issue where at least one reader or writer
        // (e.g. SQLite connection) in the GRDB pool ends up "stale" after
        // a schema migration and does not reflect the migrations.
        grdbStorage.pool.releaseMemory()
        weak var weakPool = grdbStorage.pool
        weak var weakGrdbStorage = grdbStorage
        owsAssertDebug(weakPool != nil)
        owsAssertDebug(weakGrdbStorage != nil)
        _grdbStorage = createGrdbStorage()

        DispatchQueue.main.async {
            // We want to make sure all db connections from the old adapter/pool are closed.
            //
            // We only reach this point by a predictable code path; the autoreleasepool
            // should be drained by this point.
            owsAssertDebug(weakPool == nil)
            owsAssertDebug(weakGrdbStorage == nil)

            benchSteps.step("New GRDB adapter.")

            completion()
        }
    }

    public func reloadAsMainDatabase() -> Guarantee<Void> {
        AssertIsOnMainThread()
        assert(storageCoordinatorState == .GRDB)

        Logger.info("")

        let wasRegistered = TSAccountManager.shared.isRegistered

        let (promise, future) = Guarantee<Void>.pending()
        reopenGRDBStorage {
            do {
                try GRDBSchemaMigrator.migrateDatabase(
                    databaseStorage: self,
                    isMainDatabase: true
                )
            } catch {
                owsFail("Database migration failed. Error: \(error.grdbErrorForLogging)")
            }

            self.grdbStorage.publishUpdatesImmediately()

            // We need to do this _before_ warmCaches().
            NotificationCenter.default.post(name: Self.storageDidReload, object: nil, userInfo: nil)

            SSKEnvironment.shared.warmCaches()

            if wasRegistered != TSAccountManager.shared.isRegistered {
                NotificationCenter.default.post(name: .registrationStateDidChange, object: nil, userInfo: nil)
            }
            future.resolve()
        }
        return promise
    }

    func createGrdbStorage() -> GRDBDatabaseStorageAdapter {
        return Bench(title: "Creating GRDB storage") {
            return GRDBDatabaseStorageAdapter(databaseFileUrl: databaseFileUrl)
        }
    }

    @objc
    public func deleteGrdbFiles() {
        GRDBDatabaseStorageAdapter.removeAllFiles()
    }

    @objc
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

    @objc(touchThread:shouldReindex:transaction:)
    public func touch(thread: TSThread, shouldReindex: Bool, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdb):
            DatabaseChangeObserver.serializedSync {
                if let databaseChangeObserver = grdbStorage.databaseChangeObserver {
                    databaseChangeObserver.didTouch(thread: thread, transaction: grdb)
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

    // MARK: - SDSTransactable

    public override func read(file: String = #file,
                              function: String = #function,
                              line: Int = #line,
                              block: (SDSAnyReadTransaction) -> Void) {
        InstrumentsMonitor.measure(category: "db", parent: "read", name: Self.owsFormatLogMessage(file: file, function: function, line: line)) {
            do {
                try grdbStorage.read { transaction in
                    block(transaction.asAnyRead)
                }
            } catch {
                owsFail("error: \(error.grdbErrorForLogging)")
            }
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

    // NOTE: This method is not @objc. See SDSDatabaseStorage+Objc.h.
    public override func write(file: String = #file,
                               function: String = #function,
                               line: Int = #line,
                               block: (SDSAnyWriteTransaction) -> Void) {
        #if TESTABLE_BUILD
        if Thread.isMainThread &&
            AppReadiness.isAppReady {
            Logger.warn("Database write on main thread.")
        }
        #endif

        let benchTitle = "Slow Write Transaction \(Self.owsFormatLogMessage(file: file, function: function, line: line))"
        let timeoutThreshold = DebugFlags.internalLogging ? 0.1 : 0.5

        InstrumentsMonitor.measure(category: "db", parent: "write", name: Self.owsFormatLogMessage(file: file, function: function, line: line)) {
            do {
                try grdbStorage.write { transaction in
                    Bench(title: benchTitle, logIfLongerThan: timeoutThreshold, logInProduction: true) {
                        block(transaction.asAnyWrite)
                    }
                }
            } catch {
                owsFail("error: \(error.grdbErrorForLogging)")
            }
        }
        crossProcess.notifyChangedAsync()
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

    private var storageCoordinatorStateDescription: String {
        NSStringFromStorageCoordinatorState(storageCoordinatorState)
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
        Logger.info("Database : \(databaseFileSize)")
        Logger.info("\t WAL file size: \(databaseWALFileSize)")
        Logger.info("\t SHM file size: \(databaseSHMFileSize)")
    }

    func logAllFileSizes() {
        Logger.info("GDRB Database : \(grdbStorage.databaseFileSize)")
        Logger.info("\t GDRB WAL file size: \(grdbStorage.databaseWALFileSize)")
        Logger.info("\t GDRB SHM file size: \(grdbStorage.databaseSHMFileSize)")
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
