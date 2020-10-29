import Sodium

enum KeyPairUtilities {

    static func generate(from seed: Data) -> (ed25519KeyPair: Sign.KeyPair, x25519KeyPair: ECKeyPair) {
        assert(seed.count == 16)
        let padding = Data(repeating: 0, count: 16)
        let ed25519KeyPair = Sodium().sign.keyPair(seed: (seed + padding).bytes)!
        let x25519PublicKey = Sodium().sign.toX25519(ed25519PublicKey: ed25519KeyPair.publicKey)!
        let x25519SecretKey = Sodium().sign.toX25519(ed25519SecretKey: ed25519KeyPair.secretKey)!
        let x25519KeyPair = ECKeyPair(publicKey: Data(x25519PublicKey), privateKey: Data(x25519SecretKey))!
        return (ed25519KeyPair: ed25519KeyPair, x25519KeyPair: x25519KeyPair)
    }

    static func store(seed: Data, ed25519KeyPair: Sign.KeyPair, x25519KeyPair: ECKeyPair) {
        let dbConnection = OWSIdentityManager.shared().dbConnection
        let collection = OWSPrimaryStorageIdentityKeyStoreCollection
        dbConnection.setObject(seed.toHexString(), forKey: LKSeedKey, inCollection: collection)
        dbConnection.setObject(ed25519KeyPair.secretKey.toHexString(), forKey: LKED25519SecretKey, inCollection: collection)
        dbConnection.setObject(ed25519KeyPair.publicKey.toHexString(), forKey: LKED25519PublicKey, inCollection: collection)
        dbConnection.setObject(x25519KeyPair, forKey: OWSPrimaryStorageIdentityKeyStoreIdentityKey, inCollection: collection)
    }
}
