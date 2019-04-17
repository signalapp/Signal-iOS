//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

@objc
public class SDSDatabaseStorage: NSObject {

    // TODO hoist to environment
    @objc
    public static let shared: SDSDatabaseStorage = try! SDSDatabaseStorage(raisingErrors: ())

    static public var shouldLogDBQueries: Bool = false

    @available(*, unavailable, message:"use other constructor instead.")
    override init() {
        fatalError("unavailable")
    }

    private var hasPendingCrossProcessWrite = false

    private let crossProcess = SDSCrossProcess()

    // MARK: - Initialization / Setup

    let adapter: SDSDatabaseStorageAdapter

    @objc
    required init(raisingErrors: ()) throws {
        adapter = SDSDatabaseStorage.createDefaultStorage()

        super.init()

        addObservers()
    }

    required init(adapter: SDSDatabaseStorageAdapter, raisingErrors: ()) throws {
        self.adapter = adapter

        super.init()

        addObservers()
    }

    class func createDefaultStorage() -> SDSDatabaseStorageAdapter {
        if FeatureFlags.useGRDB {
            return createGrdbStorage()
        } else {
            return createYapStorage()
        }
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

    // `grdbStorage` is useful as an "escape hatch" while we're migrating to GRDB.
    // When an adapter needs to access the backing grdb store directly.
    public var grdbStorage: GRDBDatabaseStorageAdapter {
        assert(FeatureFlags.useGRDB)
        return adapter as! GRDBDatabaseStorageAdapter
    }

    // MARK: -

    public func uiRead(block: @escaping (SDSAnyReadTransaction) -> Void) throws {
        try adapter.uiRead(block: block)
    }

    public func read(block: @escaping (SDSAnyReadTransaction) -> Void) throws {
        try adapter.read(block: block)
    }

    public func write(block: @escaping (SDSAnyWriteTransaction) -> Void) throws {
        try adapter.write(block: block)

        self.notifyCrossProcessWrite()
    }

    // MARK: - Error Swallowing

    // The original yap db access methods don't throw, but the grdb ones can.
    // To minimize disruption at the callsite while migrating, we have these
    // non-throw versions which simply swallow errors.
    //
    // Eventually we probably want to migrate away from these *SwallowingErrors flavors,
    // in favor of explicitly handling errors where possible.

    @objc
    public func uiReadSwallowingErrors(block: @escaping (SDSAnyReadTransaction) -> Void) {
        do {
            try uiRead(block: block)
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    @objc
    public func readSwallowingErrors(block: @escaping (SDSAnyReadTransaction) -> Void) {
        do {
            try read(block: block)
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    @objc
    public func writeSwallowingErrors(block: @escaping (SDSAnyWriteTransaction) -> Void) {
        do {
            try write(block: block)
        } catch {
            owsFailDebug("error: \(error)")
        }
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
    func uiRead(block: @escaping (SDSAnyReadTransaction) -> Void) throws
    func read(block: @escaping (SDSAnyReadTransaction) -> Void) throws
    func write(block: @escaping (SDSAnyWriteTransaction) -> Void) throws
}

struct YAPDBStorageAdapter {
    var storage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }
}

extension YAPDBStorageAdapter: SDSDatabaseStorageAdapter {
    func uiRead(block: @escaping (SDSAnyReadTransaction) -> Void) {
        storage.uiDatabaseConnection.read { yapTransaction in
            block(SDSAnyReadTransaction(.yapRead(yapTransaction)))
        }
    }

    func read(block: @escaping (SDSAnyReadTransaction) -> Void) {
        storage.dbReadConnection.read { yapTransaction in
            block(SDSAnyReadTransaction(.yapRead(yapTransaction)))
        }
    }

    func write(block: @escaping (SDSAnyWriteTransaction) -> Void) {
        storage.dbReadWriteConnection.readWrite { yapTransaction in
            block(SDSAnyWriteTransaction(.yapWrite(yapTransaction)))
        }
    }
}

public struct GRDBDatabaseStorageAdapter {

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

        // Schema migrations are currently simple and fast. If they grow to become long-running,
        // we'll want to ensure that it doesn't block app launch to avoid 0x8badfood.
        try migrator.migrate(pool)

        let mutatingSelf = self
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            do {
                try mutatingSelf.verify()
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }

    func verify() throws {
        try storage.pool.read { db in
            guard let someCount = try UInt.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master") else {
                owsFailDebug("failed to verify storage")
                return
            }
            Logger.debug("verified storage: \(someCount)")
        }
    }

    lazy var migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create initial schema") { db in
            try TSThreadSerializer.table.createTable(database: db)
            try TSInteractionSerializer.table.createTable(database: db)
            try SDSKeyValueStore.table.createTable(database: db)

            try db.create(index: "index_interactions_on_id_and_threadUniqueId",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.id),
                            InteractionRecord.columnName(.threadUniqueId)
                ])

            try db.create(index: "index_interactions_on_sortId_and_threadUniqueId",
                          on: InteractionRecord.databaseTableName,
                          columns: [
                            InteractionRecord.columnName(.sortId),
                            InteractionRecord.columnName(.threadUniqueId)
                ])
        }
        return migrator
    }()
}

extension GRDBDatabaseStorageAdapter: SDSDatabaseStorageAdapter {
    func uiRead(block: @escaping (SDSAnyReadTransaction) -> Void) throws {
        // TODO this should be based on a snapshot
        try pool.read { database in
            block(SDSAnyReadTransaction(.grdbRead(GRDBReadTransaction(database: database))))
        }
    }

    func read(block: @escaping (SDSAnyReadTransaction) -> Void) throws {
        try pool.read { database in
            block(SDSAnyReadTransaction(.grdbRead(GRDBReadTransaction(database: database))))
        }
    }

    func write(block: @escaping (SDSAnyWriteTransaction) -> Void) throws {
        try pool.write { database in
            block(SDSAnyWriteTransaction(.grdbWrite(GRDBWriteTransaction(database: database))))
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
