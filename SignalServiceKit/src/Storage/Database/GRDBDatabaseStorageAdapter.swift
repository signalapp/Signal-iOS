//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

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

    private let storage: GRDBStorage

    public var pool: DatabasePool {
        return storage.pool
    }

    init(baseDir: URL) throws {
        databaseUrl = GRDBDatabaseStorageAdapter.databaseFileUrl(baseDir: baseDir)

        try GRDBDatabaseStorageAdapter.ensureDatabaseKeySpecExists(baseDir: baseDir)

        storage = try GRDBStorage(dbURL: databaseUrl, keyspec: GRDBDatabaseStorageAdapter.keyspec)

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

            try db.create(index: "index_interactions_on_threadUniqueId_and_id",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.threadUniqueId),
                            InteractionRecord.columnName(.id)
                ])

            // Durable Job Queue

            try db.create(index: "index_jobs_on_label_and_id",
                          on: JobRecordRecord.databaseTableName,
                          columns: [JobRecordRecord.columnName(.label),
                                    JobRecordRecord.columnName(.id)])

            try db.create(index: "index_jobs_on_status_and_label_and_id",
                          on: JobRecordRecord.databaseTableName,
                          columns: [JobRecordRecord.columnName(.label),
                                    JobRecordRecord.columnName(.status),
                                    JobRecordRecord.columnName(.id)])

            try db.create(index: "index_jobs_on_uniqueId",
                          on: JobRecordRecord.databaseTableName,
                          columns: [JobRecordRecord.columnName(.uniqueId)])

            // View Once
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
            try db.create(index: "index_interactions_on_recordType_and_threadUniqueId_and_errorType",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.recordType),
                            InteractionRecord.columnName(.threadUniqueId),
                            InteractionRecord.columnName(.errorType)
                ])

            try db.create(index: "index_message_content_job_on_uniqueId",
                          on: MessageContentJobRecord.databaseTableName,
                          columns: [
                            MessageContentJobRecord.columnName(.uniqueId)
                ])

            // Media Gallery Indices
            try db.create(index: "index_attachments_on_albumMessageId",
                          on: AttachmentRecord.databaseTableName,
                          columns: [AttachmentRecord.columnName(.albumMessageId),
                                    AttachmentRecord.columnName(.recordType)])

            try db.create(index: "index_attachments_on_uniqueId",
                          on: AttachmentRecord.databaseTableName,
                          columns: [
                            AttachmentRecord.columnName(.uniqueId)
                ])

            try db.create(index: "index_interactions_on_uniqueId_and_threadUniqueId",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.threadUniqueId),
                            InteractionRecord.columnName(.uniqueId)
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

            // Disappearing Messages
            try db.create(index: "index_interactions_on_expiresInSeconds_and_expiresAt",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.expiresAt),
                            InteractionRecord.columnName(.expiresInSeconds)
                ])
            try db.create(index: "index_interactions_on_threadUniqueId_storedShouldStartExpireTimer_and_expiresAt",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.expiresAt),
                            InteractionRecord.columnName(.storedShouldStartExpireTimer),
                            InteractionRecord.columnName(.threadUniqueId)
                ])

            // ContactQuery
            try db.create(index: "index_contact_queries_on_lastQueried",
                          on: ContactQueryRecord.databaseTableName,
                          columns: [
                            ContactQueryRecord.columnName(.lastQueried)
                ])

            // Backup
            try db.create(index: "index_attachments_on_lazyRestoreFragmentId",
                          on: AttachmentRecord.databaseTableName,
                          columns: [
                            AttachmentRecord.columnName(.lazyRestoreFragmentId)
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

    // MARK: -

    private static let keyServiceName: String = "GRDBKeyChainService"
    private static let keyName: String = "GRDBDatabaseCipherKeySpec"
    private static var keyspec: GRDBKeySpecSource {
        return GRDBKeySpecSource(keyServiceName: keyServiceName, keyName: keyName)
    }

    @objc
    public static var isKeyAccessible: Bool {
        do {
            return try keyspec.fetchString().count > 0
        } catch {
            owsFailDebug("Key not accessible: \(error)")
            return false
        }
    }

    @objc
    public static func ensureDatabaseKeySpecExists(baseDir: URL) throws {

        do {
            _ = try keyspec.fetchString()
            // Key exists and is valid.
            return
        } catch {
            Logger.warn("Key not accessible: \(error)")
        }

        // Because we use kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        // the keychain will be inaccessible after device restart until
        // device is unlocked for the first time.  If the app receives
        // a push notification, we won't be able to access the keychain to
        // process that notification, so we should just terminate by throwing
        // an uncaught exception.
        var errorDescription = "CipherKeySpec inaccessible. New install or no unlock since device restart?"
        if CurrentAppContext().isMainApp {
            let applicationState = CurrentAppContext().reportedApplicationState
            errorDescription += ", ApplicationState: \(NSStringForUIApplicationState(applicationState))"
        }
        Logger.error(errorDescription)
        Logger.flush()

        if CurrentAppContext().isMainApp {
            if CurrentAppContext().isInBackground() {
                // Rather than crash here, we should have already detected the situation earlier
                // and exited gracefully (in the app delegate) using isDatabasePasswordAccessible.
                // This is a last ditch effort to avoid blowing away the user's database.
                throw OWSAssertionError(errorDescription)
            }
        } else {
            throw OWSAssertionError("CipherKeySpec inaccessible; not main app.")
        }

        // At this point, either this is a new install so there's no existing password to retrieve
        // or the keychain has become corrupt.  Either way, we want to get back to a
        // "known good state" and behave like a new install.
        let databaseUrl = GRDBDatabaseStorageAdapter.databaseFileUrl(baseDir: baseDir)
        let doesDBExist = FileManager.default.fileExists(atPath: databaseUrl.path)
        if doesDBExist {
            owsFailDebug("Could not load database metadata")
        }

        if !CurrentAppContext().isRunningTests {
            // Try to reset app by deleting database.
            resetAllStorage(baseDir: baseDir)
        }

        keyspec.generateAndStore()
    }

    @objc
    public static func resetAllStorage(baseDir: URL) {
        // This might be redundant but in the spirit of thoroughness...

        GRDBDatabaseStorageAdapter.removeAllFiles(baseDir: baseDir)

        deleteDBKeys()

        KeyBackupService.clearKeychain()

        if (CurrentAppContext().isMainApp) {
            TSAttachmentStream.deleteAttachments()
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

    init(dbURL: URL, keyspec: GRDBKeySpecSource) throws {
        self.dbURL = dbURL

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
    // 256 bit key + 128 bit salt
    private let kSQLCipherKeySpecLength: UInt = 48

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

    func fetchData() throws -> Data {
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

    func store(data: Data) throws {
        guard data.count == kSQLCipherKeySpecLength else {
            owsFail("unexpected keyspec length")
        }
        try CurrentAppContext().keychainStorage().set(data: data, service: keyServiceName, key: keyName)
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
            return OWSPrimaryStorage.shared?.databaseFileSize() ?? 0
        }
    }

    var databaseWALFileSize: UInt64 {
        switch dataStoreForReporting {
        case .grdb:
            return grdbStorage.databaseWALFileSize
        case .ydb:
            return OWSPrimaryStorage.shared?.databaseWALFileSize() ?? 0
        }
    }

    var databaseSHMFileSize: UInt64 {
        switch dataStoreForReporting {
        case .grdb:
            return grdbStorage.databaseSHMFileSize
        case .ydb:
            return OWSPrimaryStorage.shared?.databaseSHMFileSize() ?? 0
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
