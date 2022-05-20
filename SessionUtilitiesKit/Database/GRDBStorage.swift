// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SignalCoreKit

public enum GRDBStorageError: Error {  // TODO: Rename to `StorageError`
    case generic
    case migrationFailed
    case invalidKeySpec
    case decodingFailed
    
    case failedToSave
    case objectNotFound
    case objectNotSaved
    
    case invalidSearchPattern
}

// TODO: Protocol for storage (just need to have 'read' and 'write' methods and mock 'Database'?

// TODO: Rename to `Storage`
public final class GRDBStorage {
    public static var shared: GRDBStorage!  // TODO: Figure out how/if we want to do this
    
    private static let dbFileName: String = "Session.sqlite"
    private static let keychainService: String = "TSKeyChainService"
    private static let dbCipherKeySpecKey: String = "GRDBDatabaseCipherKeySpec"
    private static let kSQLCipherKeySpecLength: Int32 = 48
    
    private static var sharedDatabaseDirectoryPath: String { "\(OWSFileSystem.appSharedDataDirectoryPath())/database" }
    private static var databasePath: String { "\(GRDBStorage.sharedDatabaseDirectoryPath)/\(GRDBStorage.dbFileName)" }
    private static var databasePathShm: String { "\(GRDBStorage.sharedDatabaseDirectoryPath)/\(GRDBStorage.dbFileName)-shm" }
    private static var databasePathWal: String { "\(GRDBStorage.sharedDatabaseDirectoryPath)/\(GRDBStorage.dbFileName)-wal" }
    
    public static var isDatabasePasswordAccessible: Bool {
        guard (try? getDatabaseCipherKeySpec()) != nil else { return false }
        
        return true
    }
    
    private let dbPool: DatabasePool
    private let migrator: DatabaseMigrator
    
    // MARK: - Initialization
    
    public init?(
        migrations: [TargetMigrations]
    ) throws {
        print("RAWR START \("\(GRDBStorage.sharedDatabaseDirectoryPath)/\(GRDBStorage.dbFileName)")")
        GRDBStorage.deleteDatabaseFiles() // TODO: Remove this
        try! GRDBStorage.deleteDbKeys() // TODO: Remove this
        
        // Create the database directory if needed and ensure it's protection level is set before attempting to
        // create the database KeySpec or the database itself
        OWSFileSystem.ensureDirectoryExists(GRDBStorage.sharedDatabaseDirectoryPath)
        OWSFileSystem.protectFileOrFolder(atPath: GRDBStorage.sharedDatabaseDirectoryPath)
        
        // Generate the database KeySpec if needed (this MUST be done before we try to access the database
        // as a different thread might attempt to access the database before the key is successfully created)
        //
        // Note: We reset the bytes immediately after generation to ensure the database key doesn't hang
        // around in memory unintentionally
        var tmpKeySpec: Data = GRDBStorage.getOrGenerateDatabaseKeySpec()
        tmpKeySpec.resetBytes(in: 0..<tmpKeySpec.count)
        
        // Configure the database and create the DatabasePool for interacting with the database
        var config = Configuration()
        config.maximumReaderCount = 10  // Increase the max read connection limit - Default is 5
        config.prepareDatabase { db in
            var keySpec: Data = GRDBStorage.getOrGenerateDatabaseKeySpec()
            defer { keySpec.resetBytes(in: 0..<keySpec.count) } // Reset content immediately after use
            // Use a raw key spec, where the 96 hexadecimal digits are provided
            // (i.e. 64 hex for the 256 bit key, followed by 32 hex for the 128 bit salt)
            // using explicit BLOB syntax, e.g.:
            //
            // x'98483C6EB40B6C31A448C22A66DED3B5E5E8D5119CAC8327B655C8B5C483648101010101010101010101010101010101'
            keySpec = try (keySpec.toHexString().data(using: .utf8) ?? { throw GRDBStorageError.invalidKeySpec }())
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
        
        // Create the DatabasePool to allow us to connect to the database
        dbPool = try DatabasePool(
            path: "\(GRDBStorage.sharedDatabaseDirectoryPath)/\(GRDBStorage.dbFileName)",
            configuration: config
        )
        
        // Setup and run any required migrations
        migrator = {
            var migrator: DatabaseMigrator = DatabaseMigrator()
            migrations
                .sorted()
                .reduce(into: [[(identifier: TargetMigrations.Identifier, migrations: TargetMigrations.MigrationSet)]]()) { result, next in
                    next.migrations.enumerated().forEach { index, migrationSet in
                        if result.count <= index {
                            result.append([])
                        }

                        result[index] = (result[index] + [(next.identifier, migrationSet)])
                    }
                }
                .compactMap { $0 }
                .forEach { sortedMigrationInfo in
                    sortedMigrationInfo.forEach { migrationInfo in
                        migrationInfo.migrations.forEach { migration in
                            migrator.registerMigration(migrationInfo.identifier, migration: migration)
                        }
                    }
                }
            
            return migrator
        }()
        try! migrator.migrate(dbPool)
        
        GRDBStorage.shared = self   // TODO: Fix this
    }
    
    // MARK: - Security
    
    private static func getDatabaseCipherKeySpec() throws -> Data {
        return try CurrentAppContext().keychainStorage().data(forService: keychainService, key: dbCipherKeySpecKey)
    }
    
    @discardableResult private static func getOrGenerateDatabaseKeySpec() -> Data {
        do {
            var keySpec: Data = try getDatabaseCipherKeySpec()
            defer { keySpec.resetBytes(in: 0..<keySpec.count) }
            
            guard keySpec.count == kSQLCipherKeySpecLength else { throw GRDBStorageError.invalidKeySpec }
            
            return keySpec
        }
        catch {
            print("RAWR \(error.localizedDescription), \((error as? KeychainStorageError)?.code), \(errSecItemNotFound)")
            
            switch (error, (error as? KeychainStorageError)?.code) {
                // TODO: Are there other errors we know about that indicate an invalid keychain?
//                errSecNotAvailable: OSStatus { get } /* No keychain is available. You may need to restart your computer. */
//                public var errSecNoSuchKeychain
                    
                    //errSecInteractionNotAllowed
                    
                case (GRDBStorageError.invalidKeySpec, _):
                    // For these cases it means either the keySpec or the keychain has become corrupt so in order to
                    // get back to a "known good state" and behave like a new install we need to reset the storage
                    // and regenerate the key
                    // TODO: Check what this 'isRunningTests' does (use the approach to check if XCTTestCase exists instead?)
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
                        
                        try CurrentAppContext().keychainStorage().set(data: keySpec, service: keychainService, key: dbCipherKeySpecKey)
                        print("RAWR new keySpec generated and saved")
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
    
    private static func resetAllStorage() {
        NotificationCenter.default.post(name: .resetStorage, object: nil)
        
        // This might be redundant but in the spirit of thoroughness...
        self.deleteDatabaseFiles()

        try? self.deleteDbKeys()

        if CurrentAppContext().isMainApp {
//            TSAttachmentStream.deleteAttachments()
        }

        // TODO: Delete Profiles on Disk?
    }
    
    private static func deleteDatabaseFiles() {
        OWSFileSystem.deleteFile(databasePath)
        OWSFileSystem.deleteFile(databasePathShm)
        OWSFileSystem.deleteFile(databasePathWal)
    }
    
    private static func deleteDbKeys() throws {
        try CurrentAppContext().keychainStorage().remove(service: keychainService, key: dbCipherKeySpecKey)
    }
    
    // MARK: - Functions
    
    @discardableResult public func write<T>(updates: (Database) throws -> T?) -> T? {
        return try? dbPool.write(updates)
    }
    
    public func writeAsync<T>(updates: @escaping (Database) throws -> T) {
        writeAsync(updates: updates, completion: { _, _ in })
    }
    
    public func writeAsync<T>(updates: @escaping (Database) throws -> T, completion: @escaping (Database, Swift.Result<T, Error>) throws -> Void) {
        dbPool.asyncWrite(
            updates,
            completion: { db, result in
                try? completion(db, result)
            }
        )
    }
    
    @discardableResult public func read<T>(_ value: (Database) throws -> T?) -> T? {
        return try? dbPool.read(value)
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
        observation.start(
            in: dbPool,
            scheduling: scheduler,
            onError: onError,
            onChange: onChange
        )
    }
    
    public func addObserver(_ observer: TransactionObserver) {
        dbPool.add(transactionObserver: observer)
    }
}

// MARK: - Promise Extensions

public extension GRDBStorage {
    // FIXME: Would be good to replace these with Swift Combine
    @discardableResult func read<T>(_ value: (Database) throws -> Promise<T>) -> Promise<T> {
        do {
            return try dbPool.read(value)
        }
        catch {
            return Promise(error: error)
        }
    }
    
    @discardableResult func write<T>(updates: (Database) throws -> Promise<T>) -> Promise<T> {
        do {
            return try dbPool.write(updates)
        }
        catch {
            return Promise(error: error)
        }
    }
}
