// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Curve25519Kit

public enum Legacy {
    // MARK: - Collections and Keys
    
    internal static let userAccountRegisteredNumberKey = "TSStorageRegisteredNumberKey"
    internal static let userAccountCollection = "TSStorageUserAccountCollection"
    
    internal static let identityKeyStoreSeedKey = "LKLokiSeed"
    internal static let identityKeyStoreEd25519SecretKey = "LKED25519SecretKey"
    internal static let identityKeyStoreEd25519PublicKey = "LKED25519PublicKey"
    internal static let identityKeyStoreIdentityKey = "TSStorageManagerIdentityKeyStoreIdentityKey"
    internal static let identityKeyStoreCollection = "TSStorageManagerIdentityKeyStoreCollection"
}

// MARK: - Legacy Extensions

internal extension YapDatabaseReadTransaction {
    func keyPair(forKey key: String, in collection: String) -> ECKeyPair? {
        return (self.object(forKey: key, inCollection: collection) as? ECKeyPair)
    }
}
