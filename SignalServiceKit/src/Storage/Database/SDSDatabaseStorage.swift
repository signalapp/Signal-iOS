//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

@objc
public protocol SDSDatabaseStorageDelegate {
    var storageCoordinatorState: StorageCoordinatorState { get }
}

// MARK: -

@objc
public class SDSDatabaseStorage: SDSTransactable {

    @objc
    public static var shared: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    weak var delegate: SDSDatabaseStorageDelegate?

    static public var shouldLogDBQueries: Bool = true

    private var hasPendingCrossProcessWrite = false

    private let crossProcess = SDSCrossProcess()

    let observation = SDSDatabaseStorageObservation()

    // MARK: - Initialization / Setup

    @objc
    public var yapPrimaryStorage: OWSPrimaryStorage {
        return yapStorage.storage
    }

    private var _yapStorage: YAPDBStorageAdapter?

    var yapStorage: YAPDBStorageAdapter {
        if let storage = _yapStorage {
            return storage
        } else {
            let storage = createYapStorage()
            _yapStorage = storage
            return storage
        }
    }

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
    required init(delegate: SDSDatabaseStorageDelegate) {
        self.delegate = delegate

        super.init()

        addObservers()
    }

    private func addObservers() {
        // Cross process writes
        switch FeatureFlags.storageMode {
        case .ydb:
            // YDB uses a different mechanism for cross process writes.
            break
        case .grdb, .grdbThrowaway:
            crossProcess.callback = { [weak self] in
                DispatchQueue.main.async {
                    self?.handleCrossProcessWrite()
                }
            }

            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(didBecomeActive),
                                                   name: UIApplication.didBecomeActiveNotification,
                                                   object: nil)
        case .ydbTests, .grdbTests:
            // No need to listen for cross process writes during tests.
            break
        }
    }

    deinit {
        Logger.verbose("")

        NotificationCenter.default.removeObserver(self)
    }

    private lazy var baseDir: URL = {
        let containerUrl = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath(),
                               isDirectory: true)
        if [.grdbThrowaway, .ydbTests, .grdbTests ].contains(FeatureFlags.storageMode) {
            return containerUrl.appendingPathComponent(UUID().uuidString, isDirectory: true)
        } else {
            return containerUrl
        }
    }()

    @objc
    public var grdbDatabaseFileUrl: URL {
        return GRDBDatabaseStorageAdapter.databaseFileUrl(baseDir: baseDir)
    }

    func createGrdbStorage() -> GRDBDatabaseStorageAdapter {
        if !canLoadGrdb {
            Logger.error("storageMode: \(FeatureFlags.storageMode).")
            Logger.error(
                "StorageCoordinatorState: \(storageCoordinatorStateDescription).")

            switch FeatureFlags.storageModeStrictness {
            case .fail:
                owsFail("Unexpected GRDB load.")
            case .failDebug:
                owsFailDebug("Unexpected GRDB load.")
            case .log:
                Logger.error("Unexpected GRDB load.")
            }
        }

        if FeatureFlags.storageMode == .ydb {
            owsFailDebug("Unexpected storage mode: \(FeatureFlags.storageMode)")
        }

        // crash if we can't read the DB.
        return try! GRDBDatabaseStorageAdapter(baseDir: baseDir)
    }

    @objc
    public func deleteGrdbFiles() {
        GRDBDatabaseStorageAdapter.removeAllFiles(baseDir: baseDir)
    }

    func createYapStorage() -> YAPDBStorageAdapter {
        if !canLoadYdb {
            Logger.error("storageMode: \(FeatureFlags.storageMode).")
            Logger.error(
                "StorageCoordinatorState: \(storageCoordinatorStateDescription).")
            switch FeatureFlags.storageModeStrictness {
            case .fail:
                owsFail("Unexpected YDB load.")
            case .failDebug:
                owsFailDebug("Unexpected YDB load.")
            case .log:
                Logger.error("Unexpected YDB load.")
            }
        }

        let yapPrimaryStorage = OWSPrimaryStorage()
        return YAPDBStorageAdapter(storage: yapPrimaryStorage)
    }

    // MARK: - Coordination

    @objc
    public enum DataStore: Int {
        case ydb
        case grdb
    }

    private var storageCoordinatorState: StorageCoordinatorState {
        guard let delegate = delegate else {
            owsFailDebug("Missing storageCoordinator.")
            return .GRDB
        }
        return delegate.storageCoordinatorState
    }

    private var storageCoordinatorStateDescription: String {
        return NSStringFromStorageCoordinatorState(storageCoordinatorState)
    }

    @objc
     var dataStoreForReads: DataStore {
        // Before the migration starts and during the migration, read from YDB.
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration, .duringYDBToGRDBMigration:
            return .ydb
        case .GRDB:
            return .grdb
        case .ydbTests:
            return .ydb
        case .grdbTests:
            return .grdb
        @unknown default:
            owsFailDebug("Unknown state: \(storageCoordinatorState)")
            return .grdb
        }
    }

    @objc
    var dataStoreForWrites: DataStore {
        // Before the migration starts (but NOT during the migration), write to YDB.
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration:
            return .ydb
        case .duringYDBToGRDBMigration, .GRDB:
            return .grdb
        case .ydbTests:
            return .ydb
        case .grdbTests:
            return .grdb
        @unknown default:
            owsFailDebug("Unknown state: \(storageCoordinatorState)")
            return .grdb
        }
    }

    private var dataStoreForReporting: DataStore {
        switch storageCoordinatorState {
        case .YDB:
            return .ydb
        case .beforeYDBToGRDBMigration, .duringYDBToGRDBMigration, .GRDB:
            return .grdb
        case .ydbTests:
            return .ydb
        case .grdbTests:
            return .grdb
        @unknown default:
            owsFailDebug("Unknown state: \(storageCoordinatorState)")
            return .grdb
        }
    }

    @objc
    var canLoadYdb: Bool {
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration, .duringYDBToGRDBMigration:
            return true
        case .GRDB:
            // GRDB TODO: Remove this once we stop loading YDB
            //            unless necessary.
            return FeatureFlags.alwaysLoadYDB
        case .ydbTests, .grdbTests:
            return true
        @unknown default:
            owsFailDebug("Unknown state: \(storageCoordinatorState)")
            return true
        }
    }

    @objc
    var canReadFromYdb: Bool {
        // We can read from YDB before and during the YDB-to-GRDB migration.
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration, .duringYDBToGRDBMigration:
            return true
        case .GRDB:
            // GRDB TODO: Remove this once we stop loading YDB
            //            unless necessary.
            return FeatureFlags.alwaysLoadYDB
        case .ydbTests, .grdbTests:
            return true
        @unknown default:
            owsFailDebug("Unknown state: \(storageCoordinatorState)")
            return true
        }
    }

    @objc
    var canWriteToYdb: Bool {
        // We can write to YDB before but not during the YDB-to-GRDB migration.
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration:
            return true
        case .duringYDBToGRDBMigration, .GRDB:
            return false
        case .ydbTests, .grdbTests:
            return true
        @unknown default:
            owsFailDebug("Unknown state: \(storageCoordinatorState)")
            return true
        }
    }

    @objc
    var canLoadGrdb: Bool {
        switch storageCoordinatorState {
        case .YDB:
            return false
        case .beforeYDBToGRDBMigration, .duringYDBToGRDBMigration, .GRDB:
            return true
        case .ydbTests, .grdbTests:
            return true
        @unknown default:
            owsFailDebug("Unknown state: \(storageCoordinatorState)")
            return true
        }
    }

    @objc
    var canReadFromGrdb: Bool {
        // We can read from GRDB during but not before the YDB-to-GRDB migration.
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration:
            return false
        case .duringYDBToGRDBMigration, .GRDB:
            return true
        case .ydbTests, .grdbTests:
            return true
        @unknown default:
            owsFailDebug("Unknown state: \(storageCoordinatorState)")
            return true
        }
    }

    @objc
    var canWriteToGrdb: Bool {
        // We can write to GRDB during but not before the YDB-to-GRDB migration.
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration:
            return false
        case .duringYDBToGRDBMigration, .GRDB:
            return true
        case .ydbTests, .grdbTests:
            return true
        @unknown default:
            owsFailDebug("Unknown state: \(storageCoordinatorState)")
            return true
        }
    }

    // MARK: -

    @objc
    public func newDatabaseQueue() -> SDSAnyDatabaseQueue {
        var yapDatabaseQueue: YAPDBDatabaseQueue?
        var grdbDatabaseQueue: GRDBDatabaseQueue?

        switch FeatureFlags.storageMode {
        case .ydb:
            yapDatabaseQueue = yapStorage.newDatabaseQueue()
            break
        case .grdb, .grdbThrowaway:
            // If we're about to migrate or already migrating,
            // we need to create a YDB queue as well.
            if storageCoordinatorState == .beforeYDBToGRDBMigration ||
                storageCoordinatorState == .duringYDBToGRDBMigration {
                yapDatabaseQueue = yapStorage.newDatabaseQueue()
            }
            grdbDatabaseQueue = grdbStorage.newDatabaseQueue()
        case .ydbTests, .grdbTests:
            yapDatabaseQueue = yapStorage.newDatabaseQueue()
            grdbDatabaseQueue = grdbStorage.newDatabaseQueue()
            break
        }

        return SDSAnyDatabaseQueue(yapDatabaseQueue: yapDatabaseQueue,
                                   grdbDatabaseQueue: grdbDatabaseQueue,
                                   crossProcess: crossProcess)
    }

    // GRDB TODO: add read/write flavors
    public func uiReadThrows(block: @escaping (SDSAnyReadTransaction) throws -> Void) throws {
        switch dataStoreForReads {
        case .grdb:
            try grdbStorage.uiReadThrows { transaction in
                try autoreleasepool {
                    try block(transaction.asAnyRead)
                }
            }
        case .ydb:
            try yapStorage.uiReadThrows { transaction in
                try block(transaction.asAnyRead)
            }
        }
    }

    @objc
    public func uiRead(block: @escaping (SDSAnyReadTransaction) -> Void) {
        switch dataStoreForReads {
        case .grdb:
            do {
                try grdbStorage.uiRead { transaction in
                    block(transaction.asAnyRead)
                }
            } catch {
                owsFail("error: \(error)")
            }
        case .ydb:
            yapStorage.uiRead { transaction in
                block(transaction.asAnyRead)
            }
        }
    }

    @objc
    public override func read(block: @escaping (SDSAnyReadTransaction) -> Void) {
        switch dataStoreForReads {
        case .grdb:
            do {
                try grdbStorage.read { transaction in
                    block(transaction.asAnyRead)
                }
            } catch {
                owsFail("error: \(error)")
            }
        case .ydb:
            yapStorage.read { transaction in
                block(transaction.asAnyRead)
            }
        }
    }

    @objc
    public override func write(block: @escaping (SDSAnyWriteTransaction) -> Void) {
        switch dataStoreForWrites {
        case .grdb:
            do {
                try grdbStorage.write { transaction in
                    Bench(title: "Slow Write Transaction", logIfLongerThan: 0.1) {
                        block(transaction.asAnyWrite)
                    }
                }
            } catch {
                owsFail("error: \(error)")
            }
        case .ydb:
            yapStorage.write { transaction in
                Bench(title: "Slow Write Transaction", logIfLongerThan: 0.1) {
                    block(transaction.asAnyWrite)
                }
            }
        }
        crossProcess.notifyChangedAsync()
    }

    // MARK: - Value Methods

    public func uiReadReturningResult<T>(block: @escaping (SDSAnyReadTransaction) -> T) -> T {
        var value: T!
        uiRead { (transaction) in
            value = block(transaction)
        }
        return value
    }

    public func readReturningResult<T>(block: @escaping (SDSAnyReadTransaction) -> T) -> T {
        var value: T!
        read { (transaction) in
            value = block(transaction)
        }
        return value
    }

    public func readReturningResult<T>(block: @escaping (SDSAnyReadTransaction) throws -> T) throws -> T {
        var value: T!
        var thrown: Error?
        read { (transaction) in
            do {
                value = try block(transaction)
            } catch {
                thrown = error
            }
        }

        if let error = thrown {
            throw error
        }

        return value
    }

    public func writeReturningResult<T>(block: @escaping (SDSAnyWriteTransaction) -> T) -> T {
        var value: T!
        write { (transaction) in
            value = block(transaction)
        }
        return value
    }

    // MARK: - Touch

    @objc(touchInteraction:transaction:)
    public func touch(interaction: TSInteraction, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite(let yap):
            let uniqueId = interaction.uniqueId
            yap.touchObject(forKey: uniqueId, inCollection: TSInteraction.collection())
        case .grdbWrite(let grdb):
            if let conversationViewDatabaseObserver = grdbStorage.conversationViewDatabaseObserver {
                conversationViewDatabaseObserver.touch(interaction: interaction, transaction: grdb)
            } else if AppReadiness.isAppReady() {
                owsFailDebug("conversationViewDatabaseObserver was unexpectedly nil")
            }
            if let genericDatabaseObserver = grdbStorage.genericDatabaseObserver {
                genericDatabaseObserver.touchInteraction(interactionId: interaction.uniqueId,
                                                         transaction: grdb)
            } else if AppReadiness.isAppReady() {
                owsFailDebug("genericDatabaseObserver was unexpectedly nil")
            }
        }
    }

    @objc(touchThread:transaction:)
    public func touch(thread: TSThread, transaction: SDSAnyWriteTransaction) {
        touch(threadId: thread.uniqueId, transaction: transaction)
    }

    @objc(touchThreadId:transaction:)
    public func touch(threadId: String, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite(let yap):
            yap.touchObject(forKey: threadId, inCollection: TSThread.collection())
        case .grdbWrite(let grdb):
            if let homeViewDatabaseObserver = grdbStorage.homeViewDatabaseObserver {
                homeViewDatabaseObserver.touch(threadId: threadId, transaction: grdb)
            } else if AppReadiness.isAppReady() {
                owsFailDebug("homeViewDatabaseObserver was unexpectedly nil")
            }
            if let genericDatabaseObserver = grdbStorage.genericDatabaseObserver {
                genericDatabaseObserver.touchThread(transaction: grdb)
            } else if AppReadiness.isAppReady() {
                owsFailDebug("genericDatabaseObserver was unexpectedly nil")
            }

            // GRDB TODO: I believe we need to update conversation view here as well.
        }
    }

    // MARK: - Cross Process Notifications

    private func handleCrossProcessWrite() {
        AssertIsOnMainThread()

        Logger.info("")

        guard CurrentAppContext().isMainApp else {
            return
        }

        if CurrentAppContext().isMainAppAndActive {
            // If already active, update immediately.
            postCrossProcessNotification()
        } else {
            // If not active, set flag to update when we become active.
            hasPendingCrossProcessWrite = true
        }
    }

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        guard hasPendingCrossProcessWrite else {
            return
        }
        hasPendingCrossProcessWrite = false

        postCrossProcessNotification()
    }

    @objc
    public static let didReceiveCrossProcessNotification = Notification.Name("didReceiveCrossProcessNotification")

    private func postCrossProcessNotification() {
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
        NotificationCenter.default.postNotificationNameAsync(SDSDatabaseStorage.didReceiveCrossProcessNotification, object: nil)
    }

    // MARK: - Misc.

    @objc
    public func logFileSizes() {
        Logger.info("Database : \(databaseFileSize)")
        Logger.info("\t WAL file size: \(databaseWALFileSize)")
        Logger.info("\t SHM file size: \(databaseSHMFileSize)")
    }

    // MARK: - Generic Observation

    @objc(addDatabaseStorageObserver:)
    public func add(databaseStorageObserver: SDSDatabaseStorageObserver) {
        observation.add(databaseStorageObserver: databaseStorageObserver)
    }
}

// MARK: -

protocol SDSDatabaseStorageAdapter {
    associatedtype ReadTransaction
    associatedtype WriteTransaction
    func uiRead(block: @escaping (ReadTransaction) -> Void) throws
    func read(block: @escaping (ReadTransaction) -> Void) throws
    func write(block: @escaping (WriteTransaction) -> Void) throws
}

// MARK: -

struct YAPDBStorageAdapter {
    let storage: OWSPrimaryStorage
}

// MARK: -

extension YAPDBStorageAdapter: SDSDatabaseStorageAdapter {
    func uiReadThrows(block: @escaping (YapDatabaseReadTransaction) throws -> Void) throws {
        var errorToRaise: Error?
        storage.uiDatabaseConnection.read { yapTransaction in
            do {
                try block(yapTransaction)
            } catch {
                errorToRaise = error
            }
        }
        if let error = errorToRaise {
            throw error
        }
    }

    func uiRead(block: @escaping (YapDatabaseReadTransaction) -> Void) {
        storage.uiDatabaseConnection.read { yapTransaction in
            block(yapTransaction)
        }
    }

    func read(block: @escaping (YapDatabaseReadTransaction) -> Void) {
        storage.dbReadConnection.read { yapTransaction in
            block(yapTransaction)
        }
    }

    func write(block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        storage.dbReadWriteConnection.readWrite { yapTransaction in
            block(yapTransaction)
        }
    }

    func newDatabaseQueue() -> YAPDBDatabaseQueue {
        return YAPDBDatabaseQueue(databaseConnection: storage.newDatabaseConnection())
    }
}

// MARK: -

@objc
public class GRDBDatabaseStorageAdapter: NSObject {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    // MARK: -

    static func databaseFileUrl(baseDir: URL) -> URL {
        let databaseDir = baseDir.appendingPathComponent("grdb_database", isDirectory: true)
        OWSFileSystem.ensureDirectoryExists(databaseDir.path)
        return databaseDir.appendingPathComponent("signal.sqlite", isDirectory: false)
    }

    private let databaseUrl: URL

    private let keyServiceName: String = "TSKeyChainService"
    private let keyName: String = "OWSDatabaseCipherKeySpec"

    private let storage: GRDBStorage

    public var pool: DatabasePool {
        return storage.pool
    }

    init(baseDir: URL) throws {
        databaseUrl = GRDBDatabaseStorageAdapter.databaseFileUrl(baseDir: baseDir)

        storage = try GRDBStorage(dbURL: databaseUrl, keyServiceName: keyServiceName, keyName: keyName)

        super.init()

        // Schema migrations are currently simple and fast. If they grow to become long-running,
        // we'll want to ensure that it doesn't block app launch to avoid 0x8badfood.
        try migrator.migrate(pool)

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            BenchEventStart(title: "GRDB Setup", eventId: "GRDB Setup")
            defer { BenchEventComplete(eventId: "GRDB Setup") }
            do {
                try self.setup()
                try self.setupUIDatabase()
            } catch {
                owsFail("unable to setup database: \(error)")
            }
        }
    }

    func newDatabaseQueue() -> GRDBDatabaseQueue {
        return GRDBDatabaseQueue(storageAdapter: self)
    }

    public func add(function: DatabaseFunction) {
        pool.add(function: function)
    }

    static var tables: [SDSTableMetadata] {
        return [
            // Key-Value Stores
            SDSKeyValueStore.table,

            // Models
            TSThread.table,
            TSInteraction.table,
            StickerPack.table,
            InstalledSticker.table,
            KnownStickerPack.table,
            TSAttachment.table,
            SSKJobRecord.table,
            OWSMessageContentJob.table,
            OWSRecipientIdentity.table,
            ExperienceUpgrade.table,
            OWSDisappearingMessagesConfiguration.table,
            SignalRecipient.table,
            SignalAccount.table,
            OWSUserProfile.table,
            TSRecipientReadReceipt.table,
            OWSLinkedDeviceReadReceipt.table,
            OWSDevice.table,
            OWSContactQuery.table
            // NOTE: We don't include OWSMessageDecryptJob,
            // since we should never use it with GRDB.
        ]
    }

    lazy var migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create initial schema") { db in
            for table in GRDBDatabaseStorageAdapter.tables {
                try table.createTable(database: db)
            }

            try db.create(index: "index_interactions_on_id_and_threadUniqueId",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.id),
                            InteractionRecord.columnName(.threadUniqueId)
                ])
            try db.create(index: "index_interactions_on_id_and_timestamp",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.id),
                            InteractionRecord.columnName(.timestamp)
                ])
            try db.create(index: "index_jobs_on_label",
                          on: JobRecordRecord.databaseTableName,
                          columns: [JobRecordRecord.columnName(.label)])
            try db.create(index: "index_interactions_on_view_once",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.isViewOnceMessage),
                            InteractionRecord.columnName(.isViewOnceComplete)
                ])
            try db.create(index: "index_key_value_store_on_collection_and_key",
                          on: SDSKeyValueStore.table.tableName,
                          columns: [
                            SDSKeyValueStore.collectionColumn.columnName,
                            SDSKeyValueStore.keyColumn.columnName
                ])

            // Media Gallery Indices
            try db.create(index: "index_attachments_on_albumMessageId",
                          on: AttachmentRecord.databaseTableName,
                          columns: [AttachmentRecord.columnName(.albumMessageId),
                                    AttachmentRecord.columnName(.recordType)])

            try db.create(index: "index_interactions_on_uniqueId_and_threadUniqueId",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.uniqueId),
                            InteractionRecord.columnName(.threadUniqueId)
                ])

            // Signal Account Indices
            try db.create(
                index: "index_signal_accounts_on_recipientPhoneNumber",
                on: SignalAccountRecord.databaseTableName,
                columns: [SignalAccountRecord.columnName(.recipientPhoneNumber)]
            )

            try db.create(
                index: "index_signal_accounts_on_recipientUUID",
                on: SignalAccountRecord.databaseTableName,
                columns: [SignalAccountRecord.columnName(.recipientUUID)]
            )

            // Signal Recipient Indices
            try db.create(
                index: "index_signal_recipients_on_recipientPhoneNumber",
                on: SignalRecipientRecord.databaseTableName,
                columns: [SignalRecipientRecord.columnName(.recipientPhoneNumber)]
            )

            try db.create(
                index: "index_signal_recipients_on_recipientUUID",
                on: SignalRecipientRecord.databaseTableName,
                columns: [SignalRecipientRecord.columnName(.recipientUUID)]
            )

            // Thread Indices
            try db.create(
                index: "index_thread_on_contactPhoneNumber",
                on: ThreadRecord.databaseTableName,
                columns: [ThreadRecord.columnName(.contactPhoneNumber)]
            )

            try db.create(
                index: "index_tsthread_on_contactUUID",
                on: ThreadRecord.databaseTableName,
                columns: [ThreadRecord.columnName(.contactUUID)]
            )

            // User Profile
            try db.create(
                index: "index_user_profiles_on_recipientPhoneNumber",
                on: UserProfileRecord.databaseTableName,
                columns: [UserProfileRecord.columnName(.recipientPhoneNumber)]
            )

            try db.create(
                index: "index_user_profiles_on_recipientUUID",
                on: UserProfileRecord.databaseTableName,
                columns: [UserProfileRecord.columnName(.recipientUUID)]
            )

            try db.create(
                index: "index_user_profiles_on_username",
                on: UserProfileRecord.databaseTableName,
                columns: [UserProfileRecord.columnName(.username)]
            )

            // Linked Device Read Receipts
            try db.create(
                index: "index_linkedDeviceReadReceipt_on_senderPhoneNumberAndTimestamp",
                on: LinkedDeviceReadReceiptRecord.databaseTableName,
                columns: [LinkedDeviceReadReceiptRecord.columnName(.senderPhoneNumber), LinkedDeviceReadReceiptRecord.columnName(.messageIdTimestamp)]
            )

            try db.create(
                index: "index_linkedDeviceReadReceipt_on_senderUUIDAndTimestamp",
                on: LinkedDeviceReadReceiptRecord.databaseTableName,
                columns: [LinkedDeviceReadReceiptRecord.columnName(.senderUUID), LinkedDeviceReadReceiptRecord.columnName(.messageIdTimestamp)]
            )

            // Interaction Finder
            try db.create(index: "index_interactions_on_timestamp_sourceDeviceId_and_authorUUID",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.timestamp),
                            InteractionRecord.columnName(.sourceDeviceId),
                            InteractionRecord.columnName(.authorUUID)
                ])

            try db.create(index: "index_interactions_on_timestamp_sourceDeviceId_and_authorPhoneNumber",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.timestamp),
                            InteractionRecord.columnName(.sourceDeviceId),
                            InteractionRecord.columnName(.authorPhoneNumber)
                ])
            try db.create(index: "index_interactions_on_threadUniqueId_and_read",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.threadUniqueId),
                            InteractionRecord.columnName(.read)
                ])

            // ContactQuery
            try db.create(index: "index_contact_queries_on_lastQueried",
                          on: ContactQueryRecord.databaseTableName,
                          columns: [
                            ContactQueryRecord.columnName(.lastQueried)
                ])

            try GRDBFullTextSearchFinder.createTables(database: db)
        }
        return migrator
    }()

    // MARK: - Database Snapshot

    private var latestSnapshot: DatabaseSnapshot! {
        return uiDatabaseObserver!.latestSnapshot
    }

    @objc
    public private(set) var uiDatabaseObserver: UIDatabaseObserver?

    @objc
    public private(set) var homeViewDatabaseObserver: HomeViewDatabaseObserver?

    @objc
    public private(set) var conversationViewDatabaseObserver: ConversationViewDatabaseObserver?

    @objc
    public private(set) var mediaGalleryDatabaseObserver: MediaGalleryDatabaseObserver?

    @objc
    public private(set) var genericDatabaseObserver: GRDBGenericDatabaseObserver?

    @objc
    public func setupUIDatabase() throws {
        // UIDatabaseObserver is a general purpose observer, whose delegates
        // are notified when things change, but are not given any specific details
        // about the changes.
        let uiDatabaseObserver = try UIDatabaseObserver(pool: pool)
        self.uiDatabaseObserver = uiDatabaseObserver

        // HomeViewDatabaseObserver is built on top of UIDatabaseObserver
        // but includes the details necessary for rendering collection view
        // batch updates.
        let homeViewDatabaseObserver = HomeViewDatabaseObserver()
        self.homeViewDatabaseObserver = homeViewDatabaseObserver
        uiDatabaseObserver.appendSnapshotDelegate(homeViewDatabaseObserver)

        // ConversationViewDatabaseObserver is built on top of UIDatabaseObserver
        // but includes the details necessary for rendering collection view
        // batch updates.
        let conversationViewDatabaseObserver = ConversationViewDatabaseObserver()
        self.conversationViewDatabaseObserver = conversationViewDatabaseObserver
        uiDatabaseObserver.appendSnapshotDelegate(conversationViewDatabaseObserver)

        // MediaGalleryDatabaseObserver is built on top of UIDatabaseObserver
        // but includes the details necessary for rendering collection view
        // batch updates.
        let mediaGalleryDatabaseObserver = MediaGalleryDatabaseObserver()
        self.mediaGalleryDatabaseObserver = mediaGalleryDatabaseObserver
        uiDatabaseObserver.appendSnapshotDelegate(mediaGalleryDatabaseObserver)

        let genericDatabaseObserver = GRDBGenericDatabaseObserver()
        self.genericDatabaseObserver = genericDatabaseObserver
        uiDatabaseObserver.appendSnapshotDelegate(genericDatabaseObserver)

        try pool.write { db in
            db.add(transactionObserver: homeViewDatabaseObserver, extent: Database.TransactionObservationExtent.observerLifetime)
            db.add(transactionObserver: conversationViewDatabaseObserver, extent: Database.TransactionObservationExtent.observerLifetime)
            db.add(transactionObserver: mediaGalleryDatabaseObserver, extent: Database.TransactionObservationExtent.observerLifetime)
            db.add(transactionObserver: genericDatabaseObserver, extent: Database.TransactionObservationExtent.observerLifetime)
        }

        SDSDatabaseStorage.shared.observation.set(grdbStorage: self)
    }

    func testing_tearDownUIDatabase() {
        // UIDatabaseObserver is a general purpose observer, whose delegates
        // are notified when things change, but are not given any specific details
        // about the changes.
        self.uiDatabaseObserver = nil
        self.homeViewDatabaseObserver = nil
        self.conversationViewDatabaseObserver = nil
        self.mediaGalleryDatabaseObserver = nil
        self.genericDatabaseObserver = nil
    }

    func setup() throws {
        GRDBMediaGalleryFinder.setup(storage: self)
    }
}

// MARK: -

extension GRDBDatabaseStorageAdapter: SDSDatabaseStorageAdapter {
    private func assertCanRead() {
        if !databaseStorage.canReadFromGrdb {
            Logger.error("storageMode: \(FeatureFlags.storageMode).")
            Logger.error(
                "StorageCoordinatorState: \(NSStringFromStorageCoordinatorState(storageCoordinator.state)).")

            switch FeatureFlags.storageModeStrictness {
            case .fail:
                owsFail("Unexpected GRDB read.")
            case .failDebug:
                owsFailDebug("Unexpected GRDB read.")
            case .log:
                Logger.error("Unexpected GRDB read.")
            }
        }
    }

    // TODO readThrows/writeThrows flavors
    public func uiReadThrows(block: @escaping (GRDBReadTransaction) throws -> Void) rethrows {
        assertCanRead()
        AssertIsOnMainThread()
        try latestSnapshot.read { database in
            try autoreleasepool {
                try block(GRDBReadTransaction(database: database))
            }
        }
    }

    public func readReturningResultThrows<T>(block: @escaping (GRDBReadTransaction) throws -> T) throws -> T {
        assertCanRead()
        AssertIsOnMainThread()
        return try pool.read { database in
            try autoreleasepool {
                return try block(GRDBReadTransaction(database: database))
            }
        }
    }

    @objc
    public func uiRead(block: @escaping (GRDBReadTransaction) -> Void) throws {
        assertCanRead()
        AssertIsOnMainThread()
        latestSnapshot.read { database in
            autoreleasepool {
                block(GRDBReadTransaction(database: database))
            }
        }
    }

    @objc
    public func read(block: @escaping (GRDBReadTransaction) -> Void) throws {
        assertCanRead()
        try pool.read { database in
            autoreleasepool {
                block(GRDBReadTransaction(database: database))
            }
        }
    }

    @objc
    public func write(block: @escaping (GRDBWriteTransaction) -> Void) throws {
        if !databaseStorage.canWriteToGrdb {
            Logger.error("storageMode: \(FeatureFlags.storageMode).")
            Logger.error(
                "StorageCoordinatorState: \(NSStringFromStorageCoordinatorState(storageCoordinator.state)).")

            switch FeatureFlags.storageModeStrictness {
            case .fail:
                owsFail("Unexpected GRDB write.")
            case .failDebug:
                owsFailDebug("Unexpected GRDB write.")
            case .log:
                Logger.error("Unexpected GRDB write.")
            }
        }

        var transaction: GRDBWriteTransaction!
        try pool.write { database in
            autoreleasepool {
                transaction = GRDBWriteTransaction(database: database)
                block(transaction)
            }
        }
        for (queue, block) in transaction.completions {
            queue.async(execute: block)
        }
    }
}

// MARK: -

private struct GRDBStorage {

    let pool: DatabasePool

    private let dbURL: URL
    private let configuration: Configuration

    init(dbURL: URL, keyServiceName: String, keyName: String) throws {
        self.dbURL = dbURL
        let keyspec = GRDBKeySpecSource(keyServiceName: keyServiceName, keyName: keyName)

        var configuration = Configuration()
        configuration.readonly = false
        configuration.foreignKeysEnabled = true // Default is already true
        configuration.trace = {
            if SDSDatabaseStorage.shouldLogDBQueries {
                print($0)  // Prints all SQL statements
            }
        }
        configuration.label = "Modern (GRDB) Storage"      // Useful when your app opens multiple databases
        configuration.maximumReaderCount = 10   // The default is 5
        configuration.busyMode = .callback({ (retryCount: Int) -> Bool in
            // sleep 50 milliseconds
            let millis = 50
            usleep(useconds_t(millis * 1000))

            Logger.verbose("retryCount: \(retryCount)")
            let accumulatedWait = millis * (retryCount + 1)
            if accumulatedWait > 0, (accumulatedWait % 250) == 0 {
                Logger.warn("Database busy for \(accumulatedWait)ms")
            }

            return true
        })
        configuration.passphraseBlock = { try keyspec.fetchString() }
        configuration.prepareDatabase = { (db: Database) in
            try db.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
        }
        self.configuration = configuration

        pool = try DatabasePool(path: dbURL.path, configuration: configuration)
        Logger.debug("dbURL: \(dbURL)")

        OWSFileSystem.protectFileOrFolder(atPath: dbURL.path)
    }
}

// MARK: -

private struct GRDBKeySpecSource {
    let keyServiceName: String
    let keyName: String

    func fetchString() throws -> String {
        // Use a raw key spec, where the 96 hexadecimal digits are provided
        // (i.e. 64 hex for the 256 bit key, followed by 32 hex for the 128 bit salt)
        // using explicit BLOB syntax, e.g.:
        //
        // x'98483C6EB40B6C31A448C22A66DED3B5E5E8D5119CAC8327B655C8B5C483648101010101010101010101010101010101'
        let data = try fetchData()

        // 256 bit key + 128 bit salt
        guard data.count == 48 else {
            // crash
            owsFail("unexpected keyspec length")
        }

        let passphrase = "x'\(data.hexadecimalString)'"
        return passphrase
    }

    func fetchData() throws -> Data {
        return try CurrentAppContext().keychainStorage().data(forService: keyServiceName, key: keyName)
    }
}

// MARK: -

@objc
public extension SDSDatabaseStorage {
    var databaseFileSize: UInt64 {
        switch dataStoreForReporting {
        case .grdb:
            return grdbStorage.databaseFileSize
        case .ydb:
            return OWSPrimaryStorage.shared().databaseFileSize()
        }
    }

    var databaseWALFileSize: UInt64 {
        switch dataStoreForReporting {
        case .grdb:
            return grdbStorage.databaseWALFileSize
        case .ydb:
            return OWSPrimaryStorage.shared().databaseWALFileSize()
        }
    }

    var databaseSHMFileSize: UInt64 {
        switch dataStoreForReporting {
        case .grdb:
            return grdbStorage.databaseSHMFileSize
        case .ydb:
            return OWSPrimaryStorage.shared().databaseSHMFileSize()
        }
    }
}

// MARK: -

extension GRDBDatabaseStorageAdapter {
    var databaseFilePath: String {
        return databaseUrl.path
    }

    var databaseWALFilePath: String {
        return databaseUrl.path + "-wal"
    }

    var databaseSHMFilePath: String {
        return databaseUrl.path + "-shm"
    }

    static func removeAllFiles(baseDir: URL) {
        let databaseUrl = GRDBDatabaseStorageAdapter.databaseFileUrl(baseDir: baseDir)
        OWSFileSystem.deleteFileIfExists(databaseUrl.path)
        OWSFileSystem.deleteFileIfExists(databaseUrl.path + "-wal")
        OWSFileSystem.deleteFileIfExists(databaseUrl.path + "-shm")
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
