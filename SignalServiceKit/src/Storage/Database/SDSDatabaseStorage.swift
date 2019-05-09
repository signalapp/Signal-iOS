//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

@objc
public class SDSDatabaseStorage: NSObject {

    // TODO hoist to environment
    @objc
    public static let shared: SDSDatabaseStorage = SDSDatabaseStorage()

    static public var shouldLogDBQueries: Bool = false

    private var hasPendingCrossProcessWrite = false

    private let crossProcess = SDSCrossProcess()

    // MARK: - Initialization / Setup

    lazy var yapStorage = type(of: self).createYapStorage()

    @objc
    public lazy var grdbStorage = type(of: self).createGrdbStorage()

    @objc
    override init() {
        super.init()

        addObservers()
    }

    private func addObservers() {
        // Cross process writes
        if FeatureFlags.useGRDB {
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
    }

    deinit {
        Logger.verbose("")

        NotificationCenter.default.removeObserver(self)
    }

    class func createGrdbStorage() -> GRDBDatabaseStorageAdapter {
        assert(FeatureFlags.useGRDB)

        let baseDir: URL

        if FeatureFlags.grdbMigratesFreshDBEveryLaunch {
            baseDir = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath(), isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        } else {
            baseDir = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath(), isDirectory: true)
        }
        let dbDir: URL = baseDir.appendingPathComponent("grdb_database", isDirectory: true)

        // crash if we can't read the DB.
        return try! GRDBDatabaseStorageAdapter(dbDir: dbDir)
    }

    class func createYapStorage() -> YAPDBStorageAdapter {
        return YAPDBStorageAdapter()
    }

    // MARK: -

    var useGRDB: Bool = FeatureFlags.useGRDB

    @objc
    public func uiRead(block: @escaping (SDSAnyReadTransaction) -> Void) {
        if useGRDB {
            do {
                try grdbStorage.uiRead { transaction in
                    block(transaction.asAnyRead)
                }
            } catch {
                owsFail("error: \(error)")
            }
        } else {
            yapStorage.uiRead { transaction in
                block(transaction.asAnyRead)
            }
        }
    }

    @objc
    public func read(block: @escaping (SDSAnyReadTransaction) -> Void) {
        if useGRDB {
            do {
                try grdbStorage.read { transaction in
                    block(transaction.asAnyRead)
                }
            } catch {
                owsFail("error: \(error)")
            }
        } else {
            yapStorage.read { transaction in
                block(transaction.asAnyRead)
            }
        }
    }

    @objc
    public func write(block: @escaping (SDSAnyWriteTransaction) -> Void) {
        if useGRDB {
            do {
                try grdbStorage.write { transaction in
                    block(transaction.asAnyWrite)
                }
            } catch {
                owsFail("error: \(error)")
            }
        } else {
            yapStorage.write { transaction in
                block(transaction.asAnyWrite)
            }
        }

        self.notifyCrossProcessWrite()
    }

    // MARK: - Value Methods

    public func uiReadReturningResult<T>(block: @escaping (SDSAnyReadTransaction) -> T?) -> T? {
        var value: T?
        uiRead { (transaction) in
            value = block(transaction)
        }
        return value
    }

    public func readReturningResult<T>(block: @escaping (SDSAnyReadTransaction) -> T?) -> T? {
        var value: T?
        read { (transaction) in
            value = block(transaction)
        }
        return value
    }

    public func writeReturningResult<T>(block: @escaping (SDSAnyWriteTransaction) -> T?) -> T? {
        var value: T?
        write { (transaction) in
            value = block(transaction)
        }
        return value
    }

    // MARK: - Cross Process Notifications

    private func handleCrossProcessWrite() {
        AssertIsOnMainThread()

        Logger.info("")

        guard CurrentAppContext().isMainApp else {
            return
        }

        //
        if CurrentAppContext().isMainAppAndActive {
            // If already active, update immediately.
            postCrossProcessNotification()
        } else {
            // If not active, set flag to update when we become active.
            hasPendingCrossProcessWrite = true
        }
    }

    private func notifyCrossProcessWrite() {
        Logger.info("")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }
            self.crossProcess.notifyChanged()
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
}

protocol SDSDatabaseStorageAdapter {
    associatedtype ReadTransaction
    associatedtype WriteTransaction
    func uiRead(block: @escaping (ReadTransaction) -> Void) throws
    func read(block: @escaping (ReadTransaction) -> Void) throws
    func write(block: @escaping (WriteTransaction) -> Void) throws
}

struct YAPDBStorageAdapter {
    var storage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }
}

extension YAPDBStorageAdapter: SDSDatabaseStorageAdapter {
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
}

@objc
public class GRDBDatabaseStorageAdapter: NSObject {

    private let keyServiceName: String = "TSKeyChainService"
    private let keyName: String = "OWSDatabaseCipherKeySpec"

    private let storage: Storage

    public var pool: DatabasePool {
        return storage.pool
    }

    init(dbDir: URL) throws {
        OWSFileSystem.ensureDirectoryExists(dbDir.path)

        let dbURL = dbDir.appendingPathComponent("signal.sqlite", isDirectory: false)
        storage = try Storage(dbURL: dbURL, keyServiceName: keyServiceName, keyName: keyName)

        super.init()

        // Schema migrations are currently simple and fast. If they grow to become long-running,
        // we'll want to ensure that it doesn't block app launch to avoid 0x8badfood.
        try migrator.migrate(pool)

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            do {
                try self.setupUIDatabase()
            } catch {
                owsFail("unable to setup database: \(error)")
            }
        }
    }

    lazy var migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create initial schema") { db in
            try TSThreadSerializer.table.createTable(database: db)
            try TSInteractionSerializer.table.createTable(database: db)
            try SDSKeyValueStore.table.createTable(database: db)
            try StickerPackSerializer.table.createTable(database: db)
            try InstalledStickerSerializer.table.createTable(database: db)
            try KnownStickerPackSerializer.table.createTable(database: db)
            try TSAttachmentSerializer.table.createTable(database: db)

            try db.create(index: "index_interactions_on_id_and_threadUniqueId",
                          on: TSInteractionRecord.databaseTableName,
                          columns: [
                            TSInteractionRecord.columnName(.id),
                            TSInteractionRecord.columnName(.threadUniqueId)
                ])
        }
        return migrator
    }()

    // MARK: - Database Snapshot

    private var latestSnapshot: DatabaseSnapshot! {
        return uiDatabaseObserver!.latestSnapshot
    }

    @objc
    var uiDatabaseObserver: UIDatabaseObserver?

    @objc
    var homeViewDatabaseObserver: HomeViewDatabaseObserver?

    @objc
    var conversationViewDatabaseObserver: ConversationViewDatabaseObserver?

    func setupUIDatabase() throws {
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

        return try pool.write { db in
            db.add(transactionObserver: homeViewDatabaseObserver, extent: Database.TransactionObservationExtent.observerLifetime)
            db.add(transactionObserver: conversationViewDatabaseObserver, extent: Database.TransactionObservationExtent.observerLifetime)
        }
    }
}

extension GRDBDatabaseStorageAdapter: SDSDatabaseStorageAdapter {

    @objc
    func uiRead(block: @escaping (GRDBReadTransaction) -> Void) throws {
        AssertIsOnMainThread()
        latestSnapshot.read { database in
            block(GRDBReadTransaction(database: database))
        }
    }

    @objc
    func read(block: @escaping (GRDBReadTransaction) -> Void) throws {
        try pool.read { database in
            block(GRDBReadTransaction(database: database))
        }
    }

    @objc
    func write(block: @escaping (GRDBWriteTransaction) -> Void) throws {
        var transaction: GRDBWriteTransaction!
        try pool.write { database in
            transaction = GRDBWriteTransaction(database: database)
            block(transaction)
        }
        for (queue, block) in transaction.completions {
            queue.async(execute: block)
        }
    }
}

private struct Storage {

    // MARK: -

    let pool: DatabasePool

    init(dbURL: URL, keyServiceName: String, keyName: String) throws {
        let keyspec = KeySpecSource(keyServiceName: keyServiceName, keyName: keyName)

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

        configuration.passphraseBlock = { try keyspec.fetchString() }
        configuration.prepareDatabase = { (db: Database) in
            try db.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
        }

        pool = try DatabasePool(path: dbURL.path, configuration: configuration)
        Logger.debug("dbURL: \(dbURL)")

        OWSFileSystem.protectFileOrFolder(atPath: dbURL.path)
    }
}

private struct KeySpecSource {
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
