// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import YapDatabase

enum _003_YDBToGRDBMigration: Migration {
    static let target: TargetMigrations.Identifier = .utilitiesKit
    static let identifier: String = "YDBToGRDBMigration"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 0.1
    
    static func migrate(_ db: Database) throws {
        guard let dbConnection: YapDatabaseConnection = SUKLegacy.newDatabaseConnection() else {
            SNLog("[Migration Warning] No legacy database, skipping \(target.key(with: self))")
            return
        }
        
        // MARK: - Read from Legacy Database
        
        // Note: Want to exclude the Snode's we already added from the 'onionRequestPathResult'
        var registeredNumber: String?
        var seedHexString: String?
        var userEd25519SecretKeyHexString: String?
        var userEd25519PublicKeyHexString: String?
        var userX25519KeyPair: SUKLegacy.KeyPair?
        
        // Map the Legacy types for the NSKeyedUnarchiver
        NSKeyedUnarchiver.setClass(
            SUKLegacy.KeyPair.self,
            forClassName: "ECKeyPair"
        )
        
        dbConnection.read { transaction in
            // MARK: --Identity keys
            
            registeredNumber = transaction.object(
                forKey: SUKLegacy.userAccountRegisteredNumberKey,
                inCollection: SUKLegacy.userAccountCollection
            ) as? String
            
            // Note: The 'seed', 'ed25519SecretKey' and 'ed25519PublicKey' were
            // all previously stored as hex strings, so we need to convert them
            // to data before we store them in the new database
            seedHexString = transaction.object(
                forKey: SUKLegacy.identityKeyStoreSeedKey,
                inCollection: SUKLegacy.identityKeyStoreCollection
            ) as? String
            
            userEd25519SecretKeyHexString = transaction.object(
                forKey: SUKLegacy.identityKeyStoreEd25519SecretKey,
                inCollection: SUKLegacy.identityKeyStoreCollection
            ) as? String
            
            userEd25519PublicKeyHexString = transaction.object(
                forKey: SUKLegacy.identityKeyStoreEd25519PublicKey,
                inCollection: SUKLegacy.identityKeyStoreCollection
            ) as? String
            
            userX25519KeyPair = transaction.object(
                forKey: SUKLegacy.identityKeyStoreIdentityKey,
                inCollection: SUKLegacy.identityKeyStoreCollection
            ) as? SUKLegacy.KeyPair
        }
        
        // No need to continue if the user isn't registered
        if registeredNumber == nil { return }
        
        // If the user is registered then it's all-or-nothing for these values
        guard
            let seedHexString: String = seedHexString,
            let userEd25519SecretKeyHexString: String = userEd25519SecretKeyHexString,
            let userEd25519PublicKeyHexString: String = userEd25519PublicKeyHexString,
            let userX25519KeyPair: SUKLegacy.KeyPair = userX25519KeyPair
        else {
            // If this is a fresh install then we would have created all of the Identity
            // values directly within the 'Identity' table so this is actually a valid
            // case and we don't need to throw
            if try Identity.fetchCount(db) == Identity.Variant.allCases.count {
                return
            }
            
            throw StorageError.migrationFailed
        }
        
        // MARK: - Insert into GRDB
        
        try autoreleasepool {
            // MARK: --Identity keys
            
            try Identity(
                variant: .seed,
                data: Data(hex: seedHexString)
            ).migrationSafeInsert(db)
            
            try Identity(
                variant: .ed25519SecretKey,
                data: Data(hex: userEd25519SecretKeyHexString)
            ).migrationSafeInsert(db)
            
            try Identity(
                variant: .ed25519PublicKey,
                data: Data(hex: userEd25519PublicKeyHexString)
            ).migrationSafeInsert(db)
            
            try Identity(
                variant: .x25519PrivateKey,
                data: userX25519KeyPair.privateKey
            ).migrationSafeInsert(db)
            
            try Identity(
                variant: .x25519PublicKey,
                data: userX25519KeyPair.publicKey
            ).migrationSafeInsert(db)
        }
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}
