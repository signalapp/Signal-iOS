//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit
import UIKit

@objc
public class GRDBDatabaseStorageAdapter: NSObject {

    // 256 bit key + 128 bit salt
    public static let kSQLCipherKeySpecLength: UInt = 48

    @objc
    public enum DirectoryMode: Int {
        public static let commonGRDBPrefix = "grdb"
        public static var primaryFolderNameKey: String { "GRDBPrimaryDirectoryNameKey" }
        public static var transferFolderNameKey: String { "GRDBTransferDirectoryNameKey" }
        static var storedPrimaryFolderName: String? {
            get {
                CurrentAppContext().appUserDefaults().string(forKey: primaryFolderNameKey)
            } set {
                guard newValue != nil else { return owsFailDebug("Stored primary database name can never be cleared") }
                CurrentAppContext().appUserDefaults().set(newValue, forKey: primaryFolderNameKey)
            }
        }
        static var storedTransferFolderName: String? {
            get { CurrentAppContext().appUserDefaults().string(forKey: transferFolderNameKey) }
            set { CurrentAppContext().appUserDefaults().set(newValue, forKey: transferFolderNameKey) }
        }

        /// A static directory that always stored our primary database
        case primaryLegacy
        /// A static directory that served as the temporary home of our post-restore database
        case hotswapLegacy
        /// A dynamic directory that refers to the current location of our primary database (defaults to "grdb" initially), but can post-restore
        case primary

        /// A dynamic directory that refers to a staging directory that our post-restore database is setup in during restoration
        @available(iOSApplicationExtension, unavailable)
        case transfer

        /// The name for a given directoryMode
        /// All directory modes will always be non-nil *except* for the transfer directory
        /// It is incorrect to request a transfer directory without first calling `createNewTransferDirectory()`
        var folderName: String! {
            let result: String?
            switch self {
            case .primary: result = Self.storedPrimaryFolderName ?? DirectoryMode.primaryLegacy.folderName
            case .transfer: result = Self.storedTransferFolderName
            case .primaryLegacy: result = "grdb"
            case .hotswapLegacy: result = "grdb-hotswap"
            }
            owsAssertDebug(result?.hasPrefix(Self.commonGRDBPrefix) != false)
            return result
        }

        static func updateTransferDirectoryName() {
            storedTransferFolderName = "\(Self.commonGRDBPrefix)_\(Date.ows_millisecondTimestamp())_\(Int.random(in: 0..<1000))"
        }
    }

    @objc
    public static func databaseDirUrl(directoryMode: DirectoryMode = .primary) -> URL {
        return SDSDatabaseStorage.baseDir.appendingPathComponent(directoryMode.folderName, isDirectory: true)
    }

    @objc
    public static func databaseFileUrl(directoryMode: DirectoryMode = .primary) -> URL {
        let databaseDir = databaseDirUrl(directoryMode: directoryMode)
        OWSFileSystem.ensureDirectoryExists(databaseDir.path)
        return databaseDir.appendingPathComponent("signal.sqlite", isDirectory: false)
    }

    public static func databaseWalUrl(directoryMode: DirectoryMode = .primary) -> URL {
        let databaseDir = databaseDirUrl(directoryMode: directoryMode)
        OWSFileSystem.ensureDirectoryExists(databaseDir.path)
        return databaseDir.appendingPathComponent("signal.sqlite-wal", isDirectory: false)
    }

    private let checkpointQueue = DispatchQueue(label: "org.signal.checkpoint", qos: .utility)
    private let checkpointState = AtomicValue<CheckpointState>(CheckpointState(), lock: AtomicLock())

    private struct CheckpointState {
        /// The number of writes we can perform until our next checkpoint attempt.
        var budget: Int = 1

        /// The last time we successfully performed a truncating checkpoint.
        ///
        /// We use CLOCK_UPTIME_RAW here to match the one used by `asyncAfter`.
        var lastCheckpointTimestamp: UInt64?

        static func currentTimestamp() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    }

    private let databaseFileUrl: URL

    private let storage: GRDBStorage

    public var pool: DatabasePool {
        return storage.pool
    }

    init(databaseFileUrl: URL) throws {
        self.databaseFileUrl = databaseFileUrl

        do {
            // Crash if keychain is inaccessible.
            try GRDBDatabaseStorageAdapter.ensureDatabaseKeySpecExists()
        } catch {
            owsFail("\(error)")
        }

        do {
            // Crash if storage can't be initialized.
            storage = try GRDBStorage(dbURL: databaseFileUrl, keyspec: GRDBDatabaseStorageAdapter.keyspec)
        } catch {
            DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            throw error
        }

        super.init()
        setUpDatabasePathKVO()

        AppReadiness.runNowOrWhenAppWillBecomeReady { [weak self] in
            // This adapter may have been discarded after running
            // schema migrations.            
            guard let self = self else { return }

            do {
                try self.setup()
            } catch {
                owsFail("unable to setup database: \(error)")
            }
        }
    }

    deinit {
        if didRegisterDatabasePathKVO {
            let userDefaults = CurrentAppContext().appUserDefaults()
            userDefaults.removeObserver(self, forKeyPath: DirectoryMode.primaryFolderNameKey, context: &Self.databasePathKVOContext)
        }
    }

    static var tables: [SDSTableMetadata] {
        [
            // Models
            TSThread.table,
            TSInteraction.table,
            StickerPack.table,
            InstalledSticker.table,
            KnownStickerPack.table,
            TSAttachment.table,
            OWSMessageContentJob.table,
            OWSRecipientIdentity.table,
            OWSDisappearingMessagesConfiguration.table,
            TestModel.table,
            IncomingGroupsV2MessageJob.table,
            TSPaymentModel.table
        ]
    }

    static var swiftTables: [TableRecord.Type] {
        [
            ThreadAssociatedData.self,
            PendingReadReceiptRecord.self,
            PendingViewedReceiptRecord.self,
            MediaGalleryRecord.self,
            MessageSendLog.Payload.self,
            MessageSendLog.Recipient.self,
            MessageSendLog.Message.self,
            ProfileBadge.self,
            StoryMessage.self,
            StoryContextAssociatedData.self,
            DonationReceipt.self,
            OWSReaction.self,
            TSGroupMember.self,
            TSMention.self,
            ExperienceUpgrade.self,
            CancelledGroupRing.self,
            CdsPreviousE164.self,
            SpamReportingTokenRecord.self,
            UsernameLookupRecord.self,
            JobRecord.self,
            OWSDevice.self,
            SignalAccount.self,
            EditRecord.self,
            SignalRecipient.self,
            HiddenRecipient.self,
            TSPaymentsActivationRequestModel.self,
            CallRecord.self,
            OWSUserProfile.self,
            DeletedCallRecord.self
        ]
    }

    // MARK: - DatabasePathObservation

    private static var databasePathKVOContext = 0
    var didRegisterDatabasePathKVO = false

    func setUpDatabasePathKVO() {
        let appUserDefaults = CurrentAppContext().appUserDefaults()

        if CurrentAppContext().isMainApp == false {
            appUserDefaults.addObserver(
                self,
                forKeyPath: DirectoryMode.primaryFolderNameKey,
                options: [],
                context: &Self.databasePathKVOContext
            )
            didRegisterDatabasePathKVO = true
        }
    }

    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == DirectoryMode.primaryFolderNameKey, context == &Self.databasePathKVOContext {
            checkForDatabasePathChange()
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    private func checkForDatabasePathChange() {
        if databaseFileUrl != GRDBDatabaseStorageAdapter.databaseFileUrl() {
            Logger.warn("Remote process changed the active database path. Exiting...")
            Logger.flush()
            exit(0)
        } else {
            Logger.info("Spurious database change observation")
        }
    }

    // MARK: - DatabaseChangeObserver

    @objc
    public private(set) var databaseChangeObserver: DatabaseChangeObserver?

    @objc
    public func setupDatabaseChangeObserver() throws {
        owsAssertDebug(self.databaseChangeObserver == nil)

        // DatabaseChangeObserver is a general purpose observer, whose delegates
        // are notified when things change, but are not given any specific details
        // about the changes.
        let databaseChangeObserver = DatabaseChangeObserver()
        self.databaseChangeObserver = databaseChangeObserver

        try pool.write { db in
            db.add(transactionObserver: databaseChangeObserver, extent: Database.TransactionObservationExtent.observerLifetime)
        }
    }

    // NOTE: This should only be used in exceptional circumstances,
    // e.g. after reloading the database due to a device transfer.
    func publishUpdatesImmediately() {
        databaseChangeObserver?.publishUpdatesImmediately()
    }

    func testing_tearDownDatabaseChangeObserver() {
        // DatabaseChangeObserver is a general purpose observer, whose delegates
        // are notified when things change, but are not given any specific details
        // about the changes.
        self.databaseChangeObserver = nil
    }

    func setup() throws {
        try setupDatabaseChangeObserver()
    }

    // MARK: -

    private static let keyServiceName: String = "GRDBKeyChainService"
    private static let keyName: String = "GRDBDatabaseCipherKeySpec"
    public static var keyspec: GRDBKeySpecSource {
        return GRDBKeySpecSource(keyServiceName: keyServiceName, keyName: keyName)
    }

    @objc
    public static var isKeyAccessible: Bool {
        do {
            return try !keyspec.fetchString().isEmpty
        } catch {
            owsFailDebug("Key not accessible: \(error)")
            return false
        }
    }

    /// Fetches the GRDB key data from the keychain.
    /// - Note: Will fatally assert if not running in a debug or test build.
    /// - Returns: The key data, if available.
    @objc
    public static var debugOnly_keyData: Data? {
        owsAssert(OWSIsTestableBuild() || DebugFlags.internalSettings)
        return try? keyspec.fetchData()
    }

    @objc
    public static func ensureDatabaseKeySpecExists() throws {
        do {
            _ = try keyspec.fetchString()
            // Key exists and is valid.
            return
        } catch where CurrentAppContext().isMainApp && !CurrentAppContext().isInBackground() {
            // We're the main app, so we can proceed to create a new database key.
            //
            // However, if we're in the background, we don't create a new key (because
            // it might exist and not be accessible). Note that we should catch this
            // earlier using `isKeyAccessible` and terminate before this point.
            //
            // TODO: Handle "not set" vs. "permission denied" errors here.
        }

        // Because we use kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, the
        // keychain will be inaccessible after device restart until device is
        // unlocked for the first time. If the app receives a push notification, we
        // won't be able to access the keychain to process that notification, so we
        // should just terminate by throwing an uncaught exception.

        // At this point, either:
        //
        // * This is a new install so there's no existing password to retrieve.
        // * The keychain has become corrupt.
        let databaseUrl = GRDBDatabaseStorageAdapter.databaseFileUrl()
        let doesDBExist = FileManager.default.fileExists(atPath: databaseUrl.path)
        if doesDBExist {
            owsFail("Could not load database metadata")
        }

        keyspec.generateAndStore()
    }

    public static func resetAllStorage() {
        Logger.info("")

        // This might be redundant but in the spirit of thoroughness...

        GRDBDatabaseStorageAdapter.removeAllFiles()

        deleteDBKeys()

        if CurrentAppContext().isMainApp {
            TSAttachmentStream.deleteAttachmentsFromDisk()
        }

        // TODO: Delete Profiles on Disk?
    }

    private static func deleteDBKeys() {
        do {
            try keyspec.clear()
        } catch {
            owsFailDebug("Could not clear keychain: \(error)")
        }
    }

    static func prepareDatabase(db: Database, keyspec: GRDBKeySpecSource) throws {
        let keyspec = try keyspec.fetchString()
        try db.execute(sql: "PRAGMA key = \"\(keyspec)\"")
        try db.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
        try db.execute(sql: "PRAGMA checkpoint_fullfsync = ON")
        try SqliteUtil.setBarrierFsync(db: db, enabled: true)

        if !CurrentAppContext().isMainApp {
            let perConnectionCacheSizeInKibibytes = 2000 / (GRDBStorage.maximumReaderCountInExtensions + 1)
            // Limit the per-connection cache size based on the number of possible readers.
            // (The default is 2000KiB per connection regardless of how many other connections there are).
            // The minus sign indicates that this is in KiB rather than the database's page size.
            // An alternative would be to use SQLite's "shared cache" mode to have a single memory pool,
            // but unfortunately that changes the locking model in a way GRDB doesn't support.
            try db.execute(sql: "PRAGMA cache_size = -\(perConnectionCacheSizeInKibibytes)")
        }
    }
}

// MARK: - Directory Swaps

@available(iOSApplicationExtension, unavailable)
extension GRDBDatabaseStorageAdapter {
    @objc
    public static var hasAssignedTransferDirectory: Bool { DirectoryMode.storedTransferFolderName != nil }

    /// This should be called during restoration to set up a staging database directory name
    /// Once a transfer directory has been written to, it's a fatal error to call this again until restoration has completed and `promoteTransferDirectoryToPrimary` is called
    public static func createNewTransferDirectory() {
        // A bit of a preamble to make sure we're not clearing out important data.
        if hasAssignedTransferDirectory {
            Logger.warn("Transfer directory already assigned a name. Verifying it contains no data...")
            let transferDatabaseDir = databaseDirUrl(directoryMode: .transfer)
            var isDirectory: ObjCBool = false

            // We're already in an unexpected (but recoverable) state. However if the currently active transfer
            // path is a file or a non-empty directory, we're too close to losing data and we should fail.
            if FileManager.default.fileExists(atPath: transferDatabaseDir.path, isDirectory: &isDirectory) {
                owsAssert(isDirectory.boolValue)
                owsAssert(try! FileManager.default.contentsOfDirectory(atPath: transferDatabaseDir.path).isEmpty)
            }
            OWSFileSystem.deleteFileIfExists(transferDatabaseDir.path)
            clearTransferDirectory()
        }

        DirectoryMode.updateTransferDirectoryName()
        Logger.info("Established new transfer directory: \(String(describing: DirectoryMode.transfer.folderName))")

        // Double check everything turned out okay. These should never happen, but if it does we can recover by trying again.
        if DirectoryMode.transfer.folderName == DirectoryMode.primary.folderName || DirectoryMode.transfer.folderName == nil {
            owsFailDebug("Unexpected transfer name. Primary: \(DirectoryMode.primary.folderName ?? "nil"). Transfer: \(DirectoryMode.primary.folderName ?? "nil")")
            clearTransferDirectory()
            createNewTransferDirectory()
        }
    }

    public static func promoteTransferDirectoryToPrimary() {
        owsAssert(CurrentAppContext().isMainApp, "Only the main app can't swap databases")

        // Ordering matters here. We should be able to crash and recover without issue
        // A prior run may have already performed the swap but crashed, so we should not expect a transfer folder
        if let newPrimaryName = DirectoryMode.transfer.folderName {
            DirectoryMode.storedPrimaryFolderName = newPrimaryName
            Logger.info("Updated primary database directory to: \(newPrimaryName)")
            clearTransferDirectory()
        }
    }

    private static func clearTransferDirectory() {
        if hasAssignedTransferDirectory, DirectoryMode.primary.folderName != DirectoryMode.transfer.folderName {
            do {
                let transferDirectoryUrl = databaseDirUrl(directoryMode: .transfer)
                Logger.info("Deleting contents of \(transferDirectoryUrl)")
                try OWSFileSystem.deleteFileIfExists(url: transferDirectoryUrl)
            } catch {
                // Unexpected, but not unrecoverable. Orphan data cleaner can take care of this since we're clearing the folder name
                owsFailDebug("Failed to reset transfer directory: \(error)")
            }
        }
        DirectoryMode.storedTransferFolderName = nil
        Logger.info("Finished resetting database transfer directory")
    }

    // Removes all directories with the common prefix that aren't the current primary GRDB directory
    public static func removeOrphanedGRDBDirectories() {
        allGRDBDirectories
            .filter { $0 != databaseDirUrl(directoryMode: .primary) }
            .forEach {
                do {
                    Logger.info("Deleting: \($0)")
                    try OWSFileSystem.deleteFileIfExists(url: $0)
                } catch {
                    owsFailDebug("Failed to delete: \($0). Error: \(error)")
                }
            }
    }
}

// MARK: -

extension GRDBDatabaseStorageAdapter: SDSDatabaseStorageAdapter {

    #if TESTABLE_BUILD
    // TODO: We could eventually eliminate all nested transactions.
    private static let detectNestedTransactions = false

    // In debug builds, we can detect transactions opened within transaction.
    // These checks can also be used to detect unexpected "sneaky" transactions.
    @ThreadBacked(key: "canOpenTransaction", defaultValue: true)
    public static var canOpenTransaction: Bool
    #endif

    @discardableResult
    public func read<T>(block: (GRDBReadTransaction) throws -> T) throws -> T {

        #if TESTABLE_BUILD
        owsAssertDebug(Self.canOpenTransaction)
        // Check for nested tractions.
        if Self.detectNestedTransactions {
            // Check for nested tractions.
            Self.canOpenTransaction = false
        }
        defer {
            if Self.detectNestedTransactions {
                Self.canOpenTransaction = true
            }
        }
        #endif

        return try pool.read { database in
            try autoreleasepool {
                try block(GRDBReadTransaction(database: database))
            }
        }
    }

    @discardableResult
    public func write<T>(block: (GRDBWriteTransaction) throws -> T) throws -> T {

        var value: T!
        var thrown: Error?
        try write { (transaction) in
            do {
                value = try block(transaction)
            } catch {
                thrown = error
            }
        }
        if let error = thrown {
            throw error.grdbErrorForLogging
        }
        return value
    }

    @objc
    public func read(block: (GRDBReadTransaction) -> Void) throws {

        #if TESTABLE_BUILD
        owsAssertDebug(Self.canOpenTransaction)
        if Self.detectNestedTransactions {
            // Check for nested tractions.
            Self.canOpenTransaction = false
        }
        defer {
            if Self.detectNestedTransactions {
                Self.canOpenTransaction = true
            }
        }
        #endif

        try pool.read { database in
            autoreleasepool {
                block(GRDBReadTransaction(database: database))
            }
        }
    }

    @objc
    public func write(block: (GRDBWriteTransaction) -> Void) throws {

        #if TESTABLE_BUILD
        owsAssertDebug(Self.canOpenTransaction)
        // Check for nested tractions.
        if Self.detectNestedTransactions {
            // Check for nested tractions.
            Self.canOpenTransaction = false
        }
        defer {
            if Self.detectNestedTransactions {
                Self.canOpenTransaction = true
            }
        }
        #endif

        var syncCompletions: [GRDBWriteTransaction.CompletionBlock] = []
        var asyncCompletions: [GRDBWriteTransaction.AsyncCompletion] = []

        try pool.write { database in
            autoreleasepool {
                let transaction = GRDBWriteTransaction(database: database)
                block(transaction)
                transaction.finalizeTransaction()

                syncCompletions = transaction.syncCompletions
                asyncCompletions = transaction.asyncCompletions
            }
        }

        checkpointState.update { mutableState in
            mutableState.budget -= 1
            if mutableState.budget == 0 {
                scheduleCheckpoint(lastCheckpointTimestamp: mutableState.lastCheckpointTimestamp)
            }
        }

        // Perform all completions _after_ the write transaction completes.
        for block in syncCompletions {
            block()
        }

        for asyncCompletion in asyncCompletions {
            asyncCompletion.scheduler.async(asyncCompletion.block)
        }
    }

    private func scheduleCheckpoint(lastCheckpointTimestamp: UInt64?) {
        let checkpointDelay: UInt64
        if let lastCheckpointTimestamp {
            // Limit checkpoint frequency by time so that heavy write activity won't
            // bog down other threads trying to write.
            let minimumCheckpointInterval: UInt64 = 250 * NSEC_PER_MSEC
            let nextCheckpointTimestamp = lastCheckpointTimestamp + minimumCheckpointInterval
            let currentTimestamp = CheckpointState.currentTimestamp()
            if nextCheckpointTimestamp > currentTimestamp {
                checkpointDelay = nextCheckpointTimestamp - currentTimestamp
            } else {
                checkpointDelay = 0
            }
        } else {
            checkpointDelay = 0
        }
        let backgroundTask = OWSBackgroundTask(label: #function)
        checkpointQueue.asyncAfter(deadline: .init(uptimeNanoseconds: checkpointDelay)) { [weak self] in
            self?.tryToCheckpoint()
            backgroundTask.end()
        }
    }

    private func tryToCheckpoint() {
        // What Is Checkpointing?
        //
        // Checkpointing is the process of integrating the WAL into the main
        // database file. Without it, the WAL will grow indefinitely. A large WAL
        // affects read performance. Therefore we want to keep the WAL small.
        //
        // The SQLite WAL consists of "frames", representing changes to the
        // database. Frames are appended to the tail of the WAL. The WAL tracks how
        // many of its frames have been integrated into the database.
        //
        // Checkpointing entails some subset of the following tasks:
        //
        // - Integrating some or all of the frames of the WAL into the database.
        //
        // - "Restarting" the WAL so the next frame is written to the head of the
        // WAL file, not the tail. The WAL file size doesn't change, but since
        // subsequent writes overwrite from the start of the WAL, WAL file size
        // growth can be bounded.
        //
        // - "Truncating" the WAL so that that the WAL file is deleted or returned
        // to an empty state.
        //
        // The more unintegrated frames there are in the WAL, the longer a
        // checkpoint takes to complete. Long-running checkpoints can cause
        // problems in the app, e.g. blocking the main thread (note: we currently
        // do _NOT_ checkpoint on the main thread). Therefore we want to bound
        // overall WAL file size _and_ the number of unintegrated frames.
        //
        // To bound WAL file size, it's important to periodically "restart" or
        // (preferably) truncate the WAL file. We currently always truncate.
        //
        // To bound the number of unintegrated frames, we can use passive
        // checkpoints. We don't explicitly initiate passive checkpoints, but leave
        // this to SQLite auto-checkpointing.
        //
        // Checkpoint Types
        //
        // Checkpointing has several flavors: passive, full, restart, truncate.
        //
        // - Passive checkpoints abort immediately if there are any database
        // readers or writers. This makes them "cheap" in the sense that they won't
        // block for long. However they only integrate WAL contents; they don't
        // "restart" or "truncate", so they don't inherently limit WAL growth. My
        // understanding is that they can have partial success, e.g. integrating
        // some but not all of the frames of the WAL. This is beneficial.
        //
        // - Full/Restart/Truncate checkpoints will block using the busy-handler.
        // We use truncate checkpoints since they truncate the WAL file. See
        // GRDBStorage.buildConfiguration for our busy-handler (aka busyMode
        // callback). It aborts after ~50ms. These checkpoints are more expensive
        // and will block while they do their work but will limit WAL growth.
        //
        // SQLite has auto-checkpointing enabled by default, meaning that it is
        // continually trying to perform passive checkpoints in the background.
        // This is beneficial.
        //
        // Exclusion
        //
        // Note that we are navigating multiple exclusion mechanisms.
        //
        // - SQLite (as we have configured it) excludes database writes using write
        // locks (POSIX advisory locking on the database files). This locking
        // protects the database from cross-process writes.
        //
        // - GRDB writers use a serial DispatchQueue to exclude writes from each
        // other within a given DatabasePool / DatabaseQueue. AFAIK this does not
        // protect any GRDB internal state; it allows GRDB to detect re-entrancy,
        // etc.
        //
        // SQLite cannot checkpoint if there are any readers or writers. Therefore
        // we cannot checkpoint within a SQLite write transaction. We checkpoint
        // after write transactions using DatabasePool.writeWithoutTransaction().
        // This method uses the GRDB exclusion mechanism but not the SQL one.
        //
        // Our approach:
        //
        // - Always (not including auto-checkpointing) use truncate checkpoints to
        // limit WAL size.
        //
        // - It's expensive and unnecessary to do a checkpoint on every write, so
        // we only checkpoint once every N writes. We always checkpoint after the
        // first write. Large (in terms of file size) writes should be rare, so WAL
        // file size should be bounded and quite small.
        //
        // - Use a "budget" to tracking the urgency of trying to perform a
        // checkpoint after the next write. When the budget reaches zero, we should
        // try after the next write. Successes bump up the budget considerably,
        // failures bump it up a little.
        //
        // - Retry more often after failures, via the budget.
        //
        // What could go wrong:
        //
        // - Checkpointing could be expensive in some cases, causing blocking. This
        // shouldn't be an issue: we're more aggressive than ever about keeping the
        // WAL small.
        //
        // - Cross-process activity could interfere with checkpointing. This
        // shouldn't be an issue: We shouldn't have more than one of the apps (main
        // app, SAE, NSE) active at the same time for long.
        //
        // - Checkpoints might frequently fail if we're constantly doing reads.
        // This shouldn't be an issue: A checkpoint should eventually succeed when
        // db activity settles. This checkpoint might take a while but that's
        // unavoidable. The counter-argument is that we only try to checkpoint
        // immediately after a write. We often do reads immediately after writes to
        // update the UI to reflect the DB changes. Those reads _might_ frequently
        // interfere with checkpointing.
        //
        // - We might not be checkpointing often enough, or we might be
        // checkpointing too often. Either way, it's about balancing overall perf
        // with the perf cost of the next successful checkpoint. We can tune this
        // behavior using the "checkpoint budget".
        //
        // Reference
        //
        // * https://www.sqlite.org/c3ref/wal_checkpoint_v2.html
        // * https://www.sqlite.org/wal.html
        // * https://www.sqlite.org/howtocorrupt.html
        assertOnQueue(checkpointQueue)

        // Set checkpointTimeout flag.
        owsAssertDebug(GRDBStorage.checkpointTimeout == nil)
        GRDBStorage.checkpointTimeout = GRDBStorage.maxBusyTimeoutMs
        owsAssertDebug(GRDBStorage.checkpointTimeout != nil)
        defer {
            // Clear checkpointTimeout flag.
            owsAssertDebug(GRDBStorage.checkpointTimeout != nil)
            GRDBStorage.checkpointTimeout = nil
            owsAssertDebug(GRDBStorage.checkpointTimeout == nil)
        }

        pool.writeWithoutTransaction { database in
            guard database.sqliteConnection != nil else {
                Logger.warn("Skipping checkpoint for database that's already closed.")
                return
            }
            Bench(title: "Checkpoint", logIfLongerThan: 0.005, logInProduction: true) {
                do {
                    try database.checkpoint(.truncate)

                    // If the checkpoint succeeded, wait N writes before performing another checkpoint.
                    let currentTimestamp = CheckpointState.currentTimestamp()
                    checkpointState.update { mutableState in
                        mutableState.budget = 32
                        mutableState.lastCheckpointTimestamp = currentTimestamp
                    }
                } catch {
                    if (error as? DatabaseError)?.resultCode == .SQLITE_BUSY {
                        // It is expected that the busy-handler (aka busyMode callback)
                        // will abort checkpoints if there is contention.
                        Logger.warn("Didn't checkpoint because we were busy")
                    } else {
                        owsFailDebug("Checkpoint failed. Error: \(error.grdbErrorForLogging)")
                    }

                    // If the checkpoint failed, try again after a few more writes.
                    checkpointState.update { mutableState in
                        mutableState.budget = 5
                    }
                }
            }
        }
    }
}

// MARK: -

func filterForDBQueryLog(_ input: String) -> String {
    var result = input
    while let matchRange = result.range(of: "x'[0-9a-f\n]*'", options: .regularExpression) {
        let charCount = result.distance(from: matchRange.lowerBound, to: matchRange.upperBound)
        let byteCount = Int64(charCount) / 2
        let formattedByteCount = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .memory)
        result = result.replacingCharacters(in: matchRange, with: "x'<\(formattedByteCount)>'")
    }
    return result
}

private func dbQueryLog(_ value: String) {
    let filteredValue = filterForDBQueryLog(value)

    // Remove any newlines/leading space to put the log message on a single line
    let re = try! NSRegularExpression(pattern: #"\n *"#, options: [])
    let finalValue = re.stringByReplacingMatches(
        in: filteredValue,
        range: filteredValue.entireRange,
        withTemplate: " ")

    Logger.debug(finalValue)
}

// MARK: -

private struct GRDBStorage {

    let pool: DatabasePool

    private let dbURL: URL
    private let poolConfiguration: Configuration

    fileprivate static let maxBusyTimeoutMs = 50

    init(dbURL: URL, keyspec: GRDBKeySpecSource) throws {
        self.dbURL = dbURL

        self.poolConfiguration = Self.buildConfiguration(keyspec: keyspec)
        self.pool = try Self.buildPool(dbURL: dbURL, poolConfiguration: poolConfiguration)

        OWSFileSystem.protectFileOrFolder(atPath: dbURL.path)
    }

    // See: https://github.com/groue/GRDB.swift/blob/master/Documentation/SharingADatabase.md
    private static func buildPool(dbURL: URL, poolConfiguration: Configuration) throws -> DatabasePool {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var newPool: DatabasePool?
        var dbError: Error?
        coordinator.coordinate(writingItemAt: dbURL,
                               options: .forMerging,
                               error: &coordinatorError,
                               byAccessor: { url in
            do {
                newPool = try DatabasePool(path: url.path, configuration: poolConfiguration)
            } catch {
                dbError = error
            }
        })
        if let error = dbError ?? coordinatorError {
            throw error
        }
        guard let pool = newPool else {
            throw OWSAssertionError("Missing pool.")
        }
        return pool
    }

    // The checkpointTimeout flag is backed by a thread local.
    // We don't want to affect the behavior of the busy-handler (aka busyMode callback)
    // in other threads while checkpointing.
    fileprivate static var checkpointTimeoutKey: String { "GRDBStorage.checkpointTimeoutKey" }
    fileprivate static var checkpointTimeout: Int? {
        get {
            Thread.current.threadDictionary[Self.checkpointTimeoutKey] as? Int
        }
        set {
            Thread.current.threadDictionary[Self.checkpointTimeoutKey] = newValue
        }
    }

    fileprivate static var maximumReaderCountInExtensions: Int { 4 }

    private static func buildConfiguration(keyspec: GRDBKeySpecSource) -> Configuration {
        var configuration = Configuration()
        configuration.readonly = false
        configuration.foreignKeysEnabled = true // Default is already true

        #if DEBUG
        configuration.publicStatementArguments = true
        #endif

        // TODO: We should set this to `false` (or simply remove this line, as `false` is the default).
        // Historically, we took advantage of SQLite's old permissive behavior, but the SQLite
        // developers [regret this][0] and may change it in the future.
        //
        // [0]: https://sqlite.org/quirks.html#dblquote
        configuration.acceptsDoubleQuotedStringLiterals = true

        // Useful when your app opens multiple databases
        configuration.label = "GRDB Storage"
        let isMainApp = CurrentAppContext().isMainApp
        configuration.maximumReaderCount = isMainApp ? 10 : maximumReaderCountInExtensions
        configuration.busyMode = .callback({ (retryCount: Int) -> Bool in
            // sleep N milliseconds
            let millis = 25
            usleep(useconds_t(millis * 1000))
            let accumulatedWaitMs = millis * (retryCount + 1)
            if accumulatedWaitMs > 0, (accumulatedWaitMs % 250) == 0 {
                Logger.warn("Database busy for \(accumulatedWaitMs)ms")
            }

            // Only time out during checkpoints, not writes.
            if let checkpointTimeout = self.checkpointTimeout {
                if accumulatedWaitMs > checkpointTimeout {
                    return false
                }
                return true
            } else {
                return true
            }
        })
        configuration.prepareDatabase { db in
            try GRDBDatabaseStorageAdapter.prepareDatabase(db: db, keyspec: keyspec)

            #if DEBUG
            let shouldLogDbQueries = false
            if shouldLogDbQueries {
                db.trace { dbQueryLog("\($0)") }
            }
            #endif

            MediaGalleryManager.setup(database: db)
        }
        configuration.defaultTransactionKind = .immediate
        configuration.allowsUnsafeTransactions = true
        configuration.automaticMemoryManagement = false
        return configuration
    }
}

// MARK: -

public struct GRDBKeySpecSource {

    private var kSQLCipherKeySpecLength: UInt {
        GRDBDatabaseStorageAdapter.kSQLCipherKeySpecLength
    }

    let keyServiceName: String
    let keyName: String

    func fetchString() throws -> String {
        // Use a raw key spec, where the 96 hexadecimal digits are provided
        // (i.e. 64 hex for the 256 bit key, followed by 32 hex for the 128 bit salt)
        // using explicit BLOB syntax, e.g.:
        //
        // x'98483C6EB40B6C31A448C22A66DED3B5E5E8D5119CAC8327B655C8B5C483648101010101010101010101010101010101'
        let data = try fetchData()

        guard data.count == kSQLCipherKeySpecLength else {
            owsFail("unexpected keyspec length")
        }

        let passphrase = "x'\(data.hexadecimalString)'"
        return passphrase
    }

    public func fetchData() throws -> Data {
        return try CurrentAppContext().keychainStorage().data(forService: keyServiceName, key: keyName)
    }

    func clear() throws {
        Logger.info("")

        try CurrentAppContext().keychainStorage().remove(service: keyServiceName, key: keyName)
    }

    func generateAndStore() {
        Logger.info("")

        do {
            let keyData = Randomness.generateRandomBytes(Int32(kSQLCipherKeySpecLength))
            try store(data: keyData)
        } catch {
            owsFail("Could not generate key for GRDB: \(error)")
        }
    }

    public func store(data: Data) throws {
        guard data.count == kSQLCipherKeySpecLength else {
            owsFail("unexpected keyspec length")
        }
        try CurrentAppContext().keychainStorage().set(data: data, service: keyServiceName, key: keyName)
    }
}

// MARK: -

fileprivate extension URL {
    func appendingPathString(_ string: String) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path += string
        return components.url
    }
}

extension GRDBDatabaseStorageAdapter {
    public static func walFileUrl(for databaseFileUrl: URL) -> URL {
        guard let result = databaseFileUrl.appendingPathString("-wal") else {
            owsFail("Could not get WAL URL")
        }
        return result
    }

    public static func shmFileUrl(for databaseFileUrl: URL) -> URL {
        guard let result = databaseFileUrl.appendingPathString("-shm") else {
            owsFail("Could not get SHM URL")
        }
        return result
    }

    public var databaseFilePath: String {
        return databaseFileUrl.path
    }

    public var databaseWALFilePath: String {
        Self.walFileUrl(for: databaseFileUrl).path
    }

    public var databaseSHMFilePath: String {
        Self.shmFileUrl(for: databaseFileUrl).path
    }

    static func removeAllFiles() {
        // First, delete our primary database
        let databaseUrl = GRDBDatabaseStorageAdapter.databaseFileUrl()
        OWSFileSystem.deleteFileIfExists(databaseUrl.path)
        OWSFileSystem.deleteFileIfExists(databaseUrl.path + "-wal")
        OWSFileSystem.deleteFileIfExists(databaseUrl.path + "-shm")

        // In the spirit of thoroughness, since we're deleting all of our data anyway, let's
        // also delete every item in our container directory with the "grdb" prefix just in
        // case we have a leftover database directory from a prior restoration.
        allGRDBDirectories.forEach {
            do {
                try OWSFileSystem.deleteFileIfExists(url: $0)
            } catch {
                owsFailDebug("Failed to delete: \($0). Error: \(error)")
            }
        }
    }

    /// A list of the URLs for every GRDB directory, both primary and orphaned
    /// Returns all directories with the DirectoryMode.commonGRDBPrefix in the database base directory
    static var allGRDBDirectories: [URL] {
        let containerDirectory = SDSDatabaseStorage.baseDir
        let containerPathItems: [String]
        do {
            containerPathItems = try FileManager.default.contentsOfDirectory(atPath: containerDirectory.path)
        } catch {
            owsFailDebug("Failed to fetch other directory items: \(error)")
            containerPathItems = []
        }

        return containerPathItems
            .filter { $0.hasPrefix(DirectoryMode.commonGRDBPrefix) }
            .map { containerDirectory.appendingPathComponent($0) }
    }

    /// Run database integrity checks and log their results.
    @discardableResult
    public static func checkIntegrity() -> SqliteUtil.IntegrityCheckResult {
        let storageCoordinator: StorageCoordinator
        if SSKEnvironment.hasShared {
            storageCoordinator = SSKEnvironment.shared.storageCoordinator
        } else {
            storageCoordinator = StorageCoordinator()
        }
        let databaseStorage = storageCoordinator.nonGlobalDatabaseStorage

        func read<T>(block: (Database) -> T) -> T {
            return databaseStorage.read { block($0.unwrapGrdbRead.database) }
        }

        read { db in
            Logger.info("PRAGMA cipher_provider")
            Logger.info(SqliteUtil.cipherProvider(db: db))
        }

        let cipherIntegrityCheckResult = read { db in
            Logger.info("PRAGMA cipher_integrity_check")
            return SqliteUtil.cipherIntegrityCheck(db: db)
        }

        let quickCheckResult = read { db in
            Logger.info("PRAGMA quick_check")
            return SqliteUtil.quickCheck(db: db)
        }

        return cipherIntegrityCheckResult && quickCheckResult
    }
}

// MARK: - Reporting

extension GRDBDatabaseStorageAdapter {
    var databaseFileSize: UInt64 {
        guard let fileSize = OWSFileSystem.fileSize(ofPath: databaseFilePath) else {
            owsFailDebug("Could not determine file size.")
            return 0
        }
        return fileSize.uint64Value
    }

    var databaseWALFileSize: UInt64 {
        guard let fileSize = OWSFileSystem.fileSize(ofPath: databaseWALFilePath) else {
            owsFailDebug("Could not determine file size.")
            return 0
        }
        return fileSize.uint64Value
    }

    var databaseSHMFileSize: UInt64 {
        guard let fileSize = OWSFileSystem.fileSize(ofPath: databaseSHMFilePath) else {
            owsFailDebug("Could not determine file size.")
            return 0
        }
        return fileSize.uint64Value
    }
}

// MARK: - Checkpoints

extension GRDBDatabaseStorageAdapter {
    @objc
    public func syncTruncatingCheckpoint() throws {
        SDSDatabaseStorage.shared.logFileSizes()

        try GRDBDatabaseStorageAdapter.checkpoint(pool: pool)

        SDSDatabaseStorage.shared.logFileSizes()
    }

    private static func checkpoint(pool: DatabasePool) throws {
        try Bench(title: "Slow checkpoint", logIfLongerThan: 0.01, logInProduction: true) {
            // Set checkpointTimeout flag.
            // If we hit the timeout, we get back SQLITE_BUSY, which is ignored below.
            owsAssertDebug(GRDBStorage.checkpointTimeout == nil)
            GRDBStorage.checkpointTimeout = 3000  // 3s
            owsAssertDebug(GRDBStorage.checkpointTimeout != nil)
            defer {
                // Clear checkpointTimeout flag.
                owsAssertDebug(GRDBStorage.checkpointTimeout != nil)
                GRDBStorage.checkpointTimeout = nil
                owsAssertDebug(GRDBStorage.checkpointTimeout == nil)
            }

            #if TESTABLE_BUILD
            let startTime = CACurrentMediaTime()
            #endif
            try pool.writeWithoutTransaction { db in
                #if TESTABLE_BUILD
                let startElapsedSeconds: TimeInterval = CACurrentMediaTime() - startTime
                let slowStartSeconds: TimeInterval = TimeInterval(GRDBStorage.maxBusyTimeoutMs) / 1000
                if startElapsedSeconds > slowStartSeconds * 2 {
                    // maxBusyTimeoutMs isn't a hard limit, but slow starts should be very rare.
                    let formattedTime = String(format: "%0.2fms", startElapsedSeconds * 1000)
                    owsFailDebug("Slow checkpoint start: \(formattedTime)")
                }
                #endif

                do {
                    try db.checkpoint(.truncate)
                    Logger.info("Truncating checkpoint succeeded")
                } catch {
                    if (error as? DatabaseError)?.resultCode == .SQLITE_BUSY {
                        // Busy is not an error.
                        Logger.info("Truncating checkpoint failed due to busy")
                    } else {
                        throw error
                    }
                }
            }
        }
    }
}

// MARK: -

public extension Error {
    var grdbErrorForLogging: Error {
        // If not a GRDB error, return unmodified.
        guard let grdbError = self as? GRDB.DatabaseError else {
            return self
        }
        // DatabaseError.description includes the arguments.
        Logger.verbose("grdbError: \(grdbError))")
        // DatabaseError.description does not include the extendedResultCode.
        Logger.verbose("resultCode: \(grdbError.resultCode), extendedResultCode: \(grdbError.extendedResultCode), message: \(String(describing: grdbError.message)), sql: \(String(describing: grdbError.sql))")
        let error = GRDB.DatabaseError(resultCode: grdbError.extendedResultCode,
                                       message: "\(String(describing: grdbError.message)) (extended result code: \(grdbError.extendedResultCode.rawValue))",
                                       sql: nil,
                                       arguments: nil)
        return error
    }
}
