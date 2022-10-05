// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB
import PromiseKit
import SignalCoreKit

open class Storage {
    private static let dbFileName: String = "Session.sqlite"
    private static let keychainService: String = "TSKeyChainService"
    private static let dbCipherKeySpecKey: String = "GRDBDatabaseCipherKeySpec"
    private static let kSQLCipherKeySpecLength: Int32 = 48
    
    private static var sharedDatabaseDirectoryPath: String { "\(OWSFileSystem.appSharedDataDirectoryPath())/database" }
    private static var databasePath: String { "\(Storage.sharedDatabaseDirectoryPath)/\(Storage.dbFileName)" }
    private static var databasePathShm: String { "\(Storage.sharedDatabaseDirectoryPath)/\(Storage.dbFileName)-shm" }
    private static var databasePathWal: String { "\(Storage.sharedDatabaseDirectoryPath)/\(Storage.dbFileName)-wal" }
    
    public static var isDatabasePasswordAccessible: Bool {
        guard (try? getDatabaseCipherKeySpec()) != nil else { return false }
        
        return true
    }
    
    public static let shared: Storage = Storage()
    public private(set) var isValid: Bool = false
    public private(set) var hasCompletedMigrations: Bool = false
    public static let defaultPublisherScheduler: ValueObservationScheduler = .async(onQueue: .main)
    
    fileprivate var dbWriter: DatabaseWriter?
    private var migrator: DatabaseMigrator?
    private var migrationProgressUpdater: Atomic<((String, CGFloat) -> ())>?
    
    // MARK: - Initialization
    
    public init(
        customWriter: DatabaseWriter? = nil,
        customMigrations: [TargetMigrations]? = nil
    ) {
        // Create the database directory if needed and ensure it's protection level is set before attempting to
        // create the database KeySpec or the database itself
        OWSFileSystem.ensureDirectoryExists(Storage.sharedDatabaseDirectoryPath)
        OWSFileSystem.protectFileOrFolder(atPath: Storage.sharedDatabaseDirectoryPath)
        
        // If a custom writer was provided then use that (for unit testing)
        guard customWriter == nil else {
            dbWriter = customWriter
            isValid = true
            perform(migrations: (customMigrations ?? []), async: false, onProgressUpdate: nil, onComplete: { _, _ in })
            return
        }
        
        // Generate the database KeySpec if needed (this MUST be done before we try to access the database
        // as a different thread might attempt to access the database before the key is successfully created)
        //
        // Note: We reset the bytes immediately after generation to ensure the database key doesn't hang
        // around in memory unintentionally
        var tmpKeySpec: Data = Storage.getOrGenerateDatabaseKeySpec()
        tmpKeySpec.resetBytes(in: 0..<tmpKeySpec.count)
        
        // Configure the database and create the DatabasePool for interacting with the database
        var config = Configuration()
        config.maximumReaderCount = 10  // Increase the max read connection limit - Default is 5
        config.observesSuspensionNotifications = true // Minimise `0xDEAD10CC` exceptions
        config.prepareDatabase { db in
            var keySpec: Data = Storage.getOrGenerateDatabaseKeySpec()
            defer { keySpec.resetBytes(in: 0..<keySpec.count) } // Reset content immediately after use
            
            // Use a raw key spec, where the 96 hexadecimal digits are provided
            // (i.e. 64 hex for the 256 bit key, followed by 32 hex for the 128 bit salt)
            // using explicit BLOB syntax, e.g.:
            //
            // x'98483C6EB40B6C31A448C22A66DED3B5E5E8D5119CAC8327B655C8B5C483648101010101010101010101010101010101'
            keySpec = try (keySpec.toHexString().data(using: .utf8) ?? { throw StorageError.invalidKeySpec }())
            keySpec.insert(contentsOf: [120, 39], at: 0)    // "x'" prefix
            keySpec.append(39)                              // "'" suffix
            
            try db.usePassphrase(keySpec)
            
            // According to the SQLCipher docs iOS needs the 'cipher_plaintext_header_size' value set to at least
            // 32 as iOS extends special privileges to the database and needs this header to be in plaintext
            // to determine the file type
            //
            // For more info see: https://www.zetetic.net/sqlcipher/sqlcipher-api/#cipher_plaintext_header_size
            try db.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
        }
        
        // Create the DatabasePool to allow us to connect to the database and mark the storage as valid
        do {
            dbWriter = try DatabasePool(
                path: "\(Storage.sharedDatabaseDirectoryPath)/\(Storage.dbFileName)",
                configuration: config
            )
            isValid = true
        }
        catch {}
    }
    
    // MARK: - Migrations
    
    public func perform(
        migrations: [TargetMigrations],
        async: Bool = true,
        onProgressUpdate: ((CGFloat, TimeInterval) -> ())?,
        onComplete: @escaping (Error?, Bool) -> ()
    ) {
        guard isValid, let dbWriter: DatabaseWriter = dbWriter else { return }
        
        typealias MigrationInfo = (identifier: TargetMigrations.Identifier, migrations: TargetMigrations.MigrationSet)
        let sortedMigrationInfo: [MigrationInfo] = migrations
            .sorted()
            .reduce(into: [[MigrationInfo]]()) { result, next in
                next.migrations.enumerated().forEach { index, migrationSet in
                    if result.count <= index {
                        result.append([])
                    }

                    result[index] = (result[index] + [(next.identifier, migrationSet)])
                }
            }
            .reduce(into: []) { result, next in result.append(contentsOf: next) }
        
        // Setup and run any required migrations
        migrator = {
            var migrator: DatabaseMigrator = DatabaseMigrator()
            sortedMigrationInfo.forEach { migrationInfo in
                migrationInfo.migrations.forEach { migration in
                    migrator.registerMigration(migrationInfo.identifier, migration: migration)
                }
            }
            
            return migrator
        }()
        
        // Determine which migrations need to be performed and gather the relevant settings needed to
        // inform the app of progress/states
        let completedMigrations: [String] = (try? dbWriter.read { db in try migrator?.completedMigrations(db) })
            .defaulting(to: [])
        let unperformedMigrations: [(key: String, migration: Migration.Type)] = sortedMigrationInfo
            .reduce(into: []) { result, next in
                next.migrations.forEach { migration in
                    let key: String = next.identifier.key(with: migration)
                    
                    guard !completedMigrations.contains(key) else { return }
                    
                    result.append((key, migration))
                }
            }
        let migrationToDurationMap: [String: TimeInterval] = unperformedMigrations
            .reduce(into: [:]) { result, next in
                result[next.key] = next.migration.minExpectedRunDuration
            }
        let unperformedMigrationDurations: [TimeInterval] = unperformedMigrations
            .map { _, migration in migration.minExpectedRunDuration }
        let totalMinExpectedDuration: TimeInterval = migrationToDurationMap.values.reduce(0, +)
        let needsConfigSync: Bool = unperformedMigrations
            .contains(where: { _, migration in migration.needsConfigSync })
        
        self.migrationProgressUpdater = Atomic({ targetKey, progress in
            guard let migrationIndex: Int = unperformedMigrations.firstIndex(where: { key, _ in key == targetKey }) else {
                return
            }
            
            let completedExpectedDuration: TimeInterval = (
                (migrationIndex > 0 ? unperformedMigrationDurations[0..<migrationIndex].reduce(0, +) : 0) +
                (unperformedMigrationDurations[migrationIndex] * progress)
            )
            let totalProgress: CGFloat = (completedExpectedDuration / totalMinExpectedDuration)
            
            DispatchQueue.main.async {
                onProgressUpdate?(totalProgress, totalMinExpectedDuration)
            }
        })
        
        // If we have an unperformed migration then trigger the progress updater immediately
        if let firstMigrationKey: String = unperformedMigrations.first?.key {
            self.migrationProgressUpdater?.wrappedValue(firstMigrationKey, 0)
        }
        
        // Store the logic to run when the migration completes
        let migrationCompleted: (Database, Error?) -> () = { [weak self] db, error in
            self?.hasCompletedMigrations = true
            self?.migrationProgressUpdater = nil
            SUKLegacy.clearLegacyDatabaseInstance()
            
            if let error = error {
                SNLog("[Migration Error] Migration failed with error: \(error)")
            }
            
            onComplete(error, needsConfigSync)
        }
        
        // Note: The non-async migration should only be used for unit tests
        guard async else {
            do { try self.migrator?.migrate(dbWriter) }
            catch { try? dbWriter.read { db in migrationCompleted(db, error) } }
            return
        }
        
        self.migrator?.asyncMigrate(dbWriter) { db, error in
            migrationCompleted(db, error)
        }
    }
    
    public static func update(
        progress: CGFloat,
        for migration: Migration.Type,
        in target: TargetMigrations.Identifier
    ) {
        // In test builds ignore any migration progress updates (we run in a custom database writer anyway),
        // this code should be the same as 'CurrentAppContext().isRunningTests' but since the tests can run
        // without being attached to a host application the `CurrentAppContext` might not have been set and
        // would crash as it gets force-unwrapped - better to just do the check explicitly instead
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        
        Storage.shared.migrationProgressUpdater?.wrappedValue(target.key(with: migration), progress)
    }
    
    // MARK: - Security
    
    private static func getDatabaseCipherKeySpec() throws -> Data {
        return try SSKDefaultKeychainStorage.shared.data(forService: keychainService, key: dbCipherKeySpecKey)
    }
    
    @discardableResult private static func getOrGenerateDatabaseKeySpec() -> Data {
        do {
            var keySpec: Data = try getDatabaseCipherKeySpec()
            defer { keySpec.resetBytes(in: 0..<keySpec.count) }
            
            guard keySpec.count == kSQLCipherKeySpecLength else { throw StorageError.invalidKeySpec }
            
            return keySpec
        }
        catch {
            switch (error, (error as? KeychainStorageError)?.code) {
                case (StorageError.invalidKeySpec, _):
                    // For these cases it means either the keySpec or the keychain has become corrupt so in order to
                    // get back to a "known good state" and behave like a new install we need to reset the storage
                    // and regenerate the key
                    if !CurrentAppContext().isRunningTests {
                        // Try to reset app by deleting database.
                        resetAllStorage()
                    }
                    fallthrough
                
                case (_, errSecItemNotFound):
                    // No keySpec was found so we need to generate a new one
                    do {
                        var keySpec: Data = Randomness.generateRandomBytes(kSQLCipherKeySpecLength)
                        defer { keySpec.resetBytes(in: 0..<keySpec.count) } // Reset content immediately after use
                        
                        try SSKDefaultKeychainStorage.shared.set(data: keySpec, service: keychainService, key: dbCipherKeySpecKey)
                        return keySpec
                    }
                    catch {
                        Thread.sleep(forTimeInterval: 15)    // Sleep to allow any background behaviours to complete
                        fatalError("Setting keychain value failed with error: \(error.localizedDescription)")
                    }
                    
                default:
                    // Because we use kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, the keychain will be inaccessible
                    // after device restart until device is unlocked for the first time. If the app receives a push
                    // notification, we won't be able to access the keychain to process that notification, so we should
                    // just terminate by throwing an uncaught exception
                    if CurrentAppContext().isMainApp || CurrentAppContext().isInBackground() {
                        let appState: UIApplication.State = CurrentAppContext().reportedApplicationState
                        
                        // In this case we should have already detected the situation earlier and exited gracefully (in the
                        // app delegate) using isDatabasePasswordAccessible, but we want to stop the app running here anyway
                        Thread.sleep(forTimeInterval: 5)    // Sleep to allow any background behaviours to complete
                        fatalError("CipherKeySpec inaccessible. New install or no unlock since device restart?, ApplicationState: \(NSStringForUIApplicationState(appState))")
                    }
                    
                    Thread.sleep(forTimeInterval: 5)    // Sleep to allow any background behaviours to complete
                    fatalError("CipherKeySpec inaccessible; not main app.")
            }
        }
    }
    
    // MARK: - File Management
    
    public static func resetAllStorage() {
        // Just in case they haven't been removed for some reason, delete the legacy database & keys
        SUKLegacy.clearLegacyDatabaseInstance()
        try? SUKLegacy.deleteLegacyDatabaseFilesAndKey()
        
        Storage.shared.isValid = false
        Storage.shared.hasCompletedMigrations = false
        Storage.shared.dbWriter = nil
        
        self.deleteDatabaseFiles()
        try? self.deleteDbKeys()
    }
    
    private static func deleteDatabaseFiles() {
        OWSFileSystem.deleteFile(databasePath)
        OWSFileSystem.deleteFile(databasePathShm)
        OWSFileSystem.deleteFile(databasePathWal)
    }
    
    private static func deleteDbKeys() throws {
        try SSKDefaultKeychainStorage.shared.remove(service: keychainService, key: dbCipherKeySpecKey)
    }
    
    // MARK: - Functions
    
    @discardableResult public final func write<T>(updates: (Database) throws -> T?) -> T? {
        guard isValid, let dbWriter: DatabaseWriter = dbWriter else { return nil }
        
        return try? dbWriter.write(updates)
    }
    
    open func writeAsync<T>(updates: @escaping (Database) throws -> T) {
        writeAsync(updates: updates, completion: { _, _ in })
    }
    
    open func writeAsync<T>(updates: @escaping (Database) throws -> T, completion: @escaping (Database, Swift.Result<T, Error>) throws -> Void) {
        guard isValid, let dbWriter: DatabaseWriter = dbWriter else { return }
        
        dbWriter.asyncWrite(
            updates,
            completion: { db, result in
                try? completion(db, result)
            }
        )
    }
    
    @discardableResult public final func read<T>(_ value: (Database) throws -> T?) -> T? {
        guard isValid, let dbWriter: DatabaseWriter = dbWriter else { return nil }
        
        return try? dbWriter.read(value)
    }
    
    /// Rever to the `ValueObservation.start` method for full documentation
    ///
    /// - parameter observation: The observation to start
    /// - parameter scheduler: A Scheduler. By default, fresh values are
    ///   dispatched asynchronously on the main queue.
    /// - parameter onError: A closure that is provided eventual errors that
    ///   happen during observation
    /// - parameter onChange: A closure that is provided fresh values
    /// - returns: a DatabaseCancellable
    public func start<Reducer: ValueReducer>(
        _ observation: ValueObservation<Reducer>,
        scheduling scheduler: ValueObservationScheduler = .async(onQueue: .main),
        onError: @escaping (Error) -> Void,
        onChange: @escaping (Reducer.Value) -> Void
    ) -> DatabaseCancellable {
        guard isValid, let dbWriter: DatabaseWriter = dbWriter else { return AnyDatabaseCancellable(cancel: {}) }
        
        return observation.start(
            in: dbWriter,
            scheduling: scheduler,
            onError: onError,
            onChange: onChange
        )
    }
    
    public func addObserver(_ observer: TransactionObserver?) {
        guard isValid, let dbWriter: DatabaseWriter = dbWriter else { return }
        guard let observer: TransactionObserver = observer else { return }
        
        // Note: This actually triggers a write to the database so can be blocked by other
        // writes, since it's usually called on the main thread when creating a view controller
        // this can result in the UI hanging - to avoid this we dispatch (and hope there isn't
        // negative impact)
        DispatchQueue.global(qos: .default).async {
            dbWriter.add(transactionObserver: observer)
        }
    }
    
    public func removeObserver(_ observer: TransactionObserver?) {
        guard isValid, let dbWriter: DatabaseWriter = dbWriter else { return }
        guard let observer: TransactionObserver = observer else { return }
        
        // Note: This actually triggers a write to the database so can be blocked by other
        // writes, since it's usually called on the main thread when creating a view controller
        // this can result in the UI hanging - to avoid this we dispatch (and hope there isn't
        // negative impact)
        DispatchQueue.global(qos: .default).async {
            dbWriter.remove(transactionObserver: observer)
        }
    }
}

// MARK: - Promise Extensions

public extension Storage {
    // FIXME: Would be good to replace these with Swift Combine
    @discardableResult func read<T>(_ value: (Database) throws -> Promise<T>) -> Promise<T> {
        guard isValid, let dbWriter: DatabaseWriter = dbWriter else {
            return Promise(error: StorageError.databaseInvalid)
        }
        
        do {
            return try dbWriter.read(value)
        }
        catch {
            return Promise(error: error)
        }
    }
    
    // FIXME: Can't overrwrite this in `SynchronousStorage` since it's in an extension
    @discardableResult func writeAsync<T>(updates: @escaping (Database) throws -> Promise<T>) -> Promise<T> {
        guard isValid, let dbWriter: DatabaseWriter = dbWriter else {
            return Promise(error: StorageError.databaseInvalid)
        }
        
        let (promise, seal) = Promise<T>.pending()
        
        dbWriter.asyncWrite(
            { db in
                try updates(db)
                    .done { result in seal.fulfill(result) }
                    .catch { error in seal.reject(error) }
                    .retainUntilComplete()
            },
            completion: { _, result in
                switch result {
                    case .failure(let error): seal.reject(error)
                    default: break
                }
            }
        )
        
        return promise
    }
}

// MARK: - Combine Extensions

public extension ValueObservation {
    func publisher(
        in storage: Storage,
        scheduling scheduler: ValueObservationScheduler = Storage.defaultPublisherScheduler
    ) -> AnyPublisher<Reducer.Value, Error> {
        guard storage.isValid, let dbWriter: DatabaseWriter = storage.dbWriter else {
            return Fail(error: StorageError.databaseInvalid).eraseToAnyPublisher()
        }
        
        return self.publisher(in: dbWriter, scheduling: scheduler)
            .eraseToAnyPublisher()
    }
}
