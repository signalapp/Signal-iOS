// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Curve25519Kit

enum _002_YDBToGRDBMigration: Migration {
    static let identifier: String = "YDBToGRDBMigration"
    
    static func migrate(_ db: Database) throws {
        // MARK: - Identity keys
        
        // Note: Want to exclude the Snode's we already added from the 'onionRequestPathResult'
        var registeredNumber: String?
        var seedHexString: String?
        var userEd25519SecretKeyHexString: String?
        var userEd25519PublicKeyHexString: String?
        var userX25519KeyPair: ECKeyPair?
        
        Storage.read { transaction in
            registeredNumber = transaction.object(
                forKey: Legacy.userAccountRegisteredNumberKey,
                inCollection: Legacy.userAccountCollection
            ) as? String
            
            // Note: The 'seed', 'ed25519SecretKey' and 'ed25519PublicKey' were
            // all previously stored as hex strings, so we need to convert them
            // to data before we store them in the new database
            seedHexString = transaction.object(
                forKey: Legacy.identityKeyStoreSeedKey,
                inCollection: Legacy.identityKeyStoreCollection
            ) as? String
            
            userEd25519SecretKeyHexString = transaction.object(
                forKey: Legacy.identityKeyStoreEd25519SecretKey,
                inCollection: Legacy.identityKeyStoreCollection
            ) as? String
            
            userEd25519PublicKeyHexString = transaction.object(
                forKey: Legacy.identityKeyStoreEd25519PublicKey,
                inCollection: Legacy.identityKeyStoreCollection
            ) as? String
            
            userX25519KeyPair = transaction.keyPair(
                forKey: Legacy.identityKeyStoreIdentityKey,
                in: Legacy.identityKeyStoreCollection
            )
        }
        
        // No need to continue if the user isn't registered
        if registeredNumber == nil { return }
        
        // If the user is registered then it's all-or-nothing for these values
        guard
            let seedHexString: String = seedHexString,
            let userEd25519SecretKeyHexString: String = userEd25519SecretKeyHexString,
            let userEd25519PublicKeyHexString: String = userEd25519PublicKeyHexString,
            let userX25519KeyPair: ECKeyPair = userX25519KeyPair
        else {
            throw GRDBStorageError.migrationFailed
        }
        
        // Insert the data into GRDB
        try Identity(
            variant: .seed,
            data: Data(hex: seedHexString)
        ).insert(db)
        
        try Identity(
            variant: .ed25519SecretKey,
            data: Data(hex: userEd25519SecretKeyHexString)
        ).insert(db)
        
        try Identity(
            variant: .ed25519PublicKey,
            data: Data(hex: userEd25519PublicKeyHexString)
        ).insert(db)
        
        try Identity(
            variant: .x25519PrivateKey,
            data: userX25519KeyPair.privateKey
        ).insert(db)
        
        try Identity(
            variant: .x25519PublicKey,
            data: userX25519KeyPair.publicKey
        ).insert(db)
    }
}
