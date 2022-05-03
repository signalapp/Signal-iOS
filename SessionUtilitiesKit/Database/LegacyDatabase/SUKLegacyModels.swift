// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public typealias SUKLegacy = Legacy

public enum Legacy {
    // MARK: - Collections and Keys
    
    internal static let userAccountRegisteredNumberKey = "TSStorageRegisteredNumberKey"
    internal static let userAccountCollection = "TSStorageUserAccountCollection"
    
    internal static let identityKeyStoreSeedKey = "LKLokiSeed"
    internal static let identityKeyStoreEd25519SecretKey = "LKED25519SecretKey"
    internal static let identityKeyStoreEd25519PublicKey = "LKED25519PublicKey"
    internal static let identityKeyStoreIdentityKey = "TSStorageManagerIdentityKeyStoreIdentityKey"
    internal static let identityKeyStoreCollection = "TSStorageManagerIdentityKeyStoreCollection"
    
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
