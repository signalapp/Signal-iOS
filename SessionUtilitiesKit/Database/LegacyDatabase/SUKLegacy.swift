// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import YapDatabase

public enum SUKLegacy {
    // MARK: - YapDatabase
    
    private static let keychainService = "TSKeyChainService"
    private static let keychainDBCipherKeySpec = "OWSDatabaseCipherKeySpec"
    private static let sqlCipherKeySpecLength = 48
    
    private static var database: Atomic<YapDatabase>?
    
    // MARK: - Collections and Keys
    
    internal static let userAccountRegisteredNumberKey = "TSStorageRegisteredNumberKey"
    internal static let userAccountCollection = "TSStorageUserAccountCollection"
    
    internal static let identityKeyStoreSeedKey = "LKLokiSeed"
    internal static let identityKeyStoreEd25519SecretKey = "LKED25519SecretKey"
    internal static let identityKeyStoreEd25519PublicKey = "LKED25519PublicKey"
    internal static let identityKeyStoreIdentityKey = "TSStorageManagerIdentityKeyStoreIdentityKey"
    internal static let identityKeyStoreCollection = "TSStorageManagerIdentityKeyStoreCollection"
    
    // MARK: - Database Functions
    
    public static var legacyDatabaseFilepath: String {
        let sharedDirUrl: URL = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
        
        return sharedDirUrl
            .appendingPathComponent("database")
            .appendingPathComponent("Signal.sqlite")
            .path
    }
    
    private static let legacyDatabaseDeserializer: YapDatabaseDeserializer = {
        return { (collection: String, key: String, data: Data) -> Any in
            /// **Note:** The old `init(forReadingWith:)` method has been deprecated with `init(forReadingFrom:)`
            /// and Apple changed the default of `requiresSecureCoding` to be true, this results in some of the types from failing
            /// to decode, as a result we need to set it to false here
            let unarchiver: NSKeyedUnarchiver? = try? NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver?.requiresSecureCoding = false
            
            guard !data.isEmpty, let result = unarchiver?.decodeObject(forKey: "root") else {
                return UnknownDBObject()
            }
            
            return result
        }
    }()
    
    public static var hasLegacyDatabaseFile: Bool {
        return FileManager.default.fileExists(atPath: legacyDatabaseFilepath)
    }
    
    @discardableResult public static func loadDatabaseIfNeeded() -> Bool {
        guard SUKLegacy.database == nil else { return true }
        
        /// Ensure the databaseKeySpec exists
        var maybeKeyData: Data? = try? SSKDefaultKeychainStorage.shared.data(
            forService: keychainService,
            key: keychainDBCipherKeySpec
        )
        defer { if maybeKeyData != nil { maybeKeyData!.resetBytes(in: 0..<maybeKeyData!.count) } }
        
        guard maybeKeyData != nil, maybeKeyData?.count == sqlCipherKeySpecLength else { return false }
        
        // Setup the database options
        let options: YapDatabaseOptions = YapDatabaseOptions()
        options.corruptAction = .fail
        options.enableMultiProcessSupport = true
        options.cipherUnencryptedHeaderLength = kSqliteHeaderLength // Needed for iOS to support SQLite writes
        options.legacyCipherCompatibilityVersion = 3    // Old DB was SQLCipher V3
        options.cipherKeySpecBlock = {
            /// To avoid holding the keySpec in memory too long we load it as needed, since we have already confirmed
            /// it's existence we can force-try here (the database will crash if it's invalid anyway)
            var keySpec: Data = try! SSKDefaultKeychainStorage.shared.data(
                forService: keychainService,
                key: keychainDBCipherKeySpec
            )
            defer { keySpec.resetBytes(in: 0..<keySpec.count) }
            
            return keySpec
        }
        
        let maybeDatabase: YapDatabase? = YapDatabase(
            path: legacyDatabaseFilepath,
            serializer: nil,
            deserializer: legacyDatabaseDeserializer,
            options: options
        )
        
        guard let database: YapDatabase = maybeDatabase else { return false }
        
        // Store the database instance atomically
        SUKLegacy.database = Atomic(database)
        
        return true
    }
    
    public static func newDatabaseConnection() -> YapDatabaseConnection? {
        SUKLegacy.loadDatabaseIfNeeded()
        
        return self.database?.wrappedValue.newConnection()
    }
    
    public static func clearLegacyDatabaseInstance() {
        self.database = nil
    }
    
    public static func deleteLegacyDatabaseFilesAndKey() throws {
        OWSFileSystem.deleteFile(legacyDatabaseFilepath)
        OWSFileSystem.deleteFile("\(legacyDatabaseFilepath)-shm")
        OWSFileSystem.deleteFile("\(legacyDatabaseFilepath)-wal")
        try SSKDefaultKeychainStorage.shared.remove(service: keychainService, key: keychainDBCipherKeySpec)
    }
    
    // MARK: - UnknownDBObject
    
    @objc(LegacyUnknownDBObject)
    public class UnknownDBObject: NSObject, NSCoding {
        override public init() {}
        public required init?(coder: NSCoder) {}
        public func encode(with coder: NSCoder) { fatalError("Shouldn't be encoding this type") }
    }
    
    // MARK: - LagacyKeyPair
    
    @objc(LegacyKeyPair)
    public class KeyPair: NSObject, NSCoding {
        private static let keyLength: Int = 32
        private static let publicKeyKey: String = "TSECKeyPairPublicKey"
        private static let privateKeyKey: String = "TSECKeyPairPrivateKey"
        
        public let publicKey: Data
        public let privateKey: Data
        
        public init(
            publicKeyData: Data,
            privateKeyData: Data
        ) {
            publicKey = publicKeyData
            privateKey = privateKeyData
        }
        
        public required init?(coder: NSCoder) {
            var pubKeyLength: Int = 0
            var privKeyLength: Int = 0
            
            guard
                let pubKeyBytes: UnsafePointer<UInt8> = coder.decodeBytes(forKey: KeyPair.publicKeyKey, returnedLength: &pubKeyLength),
                let privateKeyBytes: UnsafePointer<UInt8> = coder.decodeBytes(forKey: KeyPair.privateKeyKey, returnedLength: &privKeyLength),
                pubKeyLength == KeyPair.keyLength,
                privKeyLength == KeyPair.keyLength
            else {
                // Fail if the keys aren't the correct length
                return nil
            }
            
            publicKey = Data(bytes: pubKeyBytes, count: pubKeyLength)
            privateKey = Data(bytes: privateKeyBytes, count: privKeyLength)
        }
        
        public func encode(with coder: NSCoder) { fatalError("Shouldn't be encoding this type") }
    }
}
