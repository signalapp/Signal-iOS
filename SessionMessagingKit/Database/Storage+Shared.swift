import PromiseKit
import Sodium

extension Storage {

    @discardableResult
    public func write(with block: @escaping (Any) -> Void) -> Promise<Void> {
        Storage.write(with: { block($0) })
    }
    
    @discardableResult
    public func write(with block: @escaping (Any) -> Void, completion: @escaping () -> Void) -> Promise<Void> {
        Storage.write(with: { block($0) }, completion: completion)
    }
    
    public func writeSync(with block: @escaping (Any) -> Void) {
        Storage.writeSync { block($0) }
    }

    @objc public func getUserPublicKey() -> String? {
        return OWSIdentityManager.shared().identityKeyPair()?.hexEncodedPublicKey
    }

    public func getUserKeyPair() -> ECKeyPair? {
        return OWSIdentityManager.shared().identityKeyPair()
    }
    
    public func getUserED25519KeyPair() -> Box.KeyPair? {
        let dbConnection = OWSIdentityManager.shared().dbConnection
        let collection = OWSPrimaryStorageIdentityKeyStoreCollection
        guard let hexEncodedPublicKey = dbConnection.object(forKey: LKED25519PublicKey, inCollection: collection) as? String,
            let hexEncodedSecretKey = dbConnection.object(forKey: LKED25519SecretKey, inCollection: collection) as? String else { return nil }
        let publicKey = Box.KeyPair.PublicKey(hex: hexEncodedPublicKey)
        let secretKey = Box.KeyPair.SecretKey(hex: hexEncodedSecretKey)
        return Box.KeyPair(publicKey: publicKey, secretKey: secretKey)
    }

    @objc public func getUser() -> Contact? {
        guard let userPublicKey = getUserPublicKey() else { return nil }
        var result: Contact?
        Storage.read { transaction in
            result = Storage.shared.getContact(with: userPublicKey)
            // HACK: Apparently it's still possible for the user's contact info to be missing
            if result == nil, let profile = OWSUserProfile.fetch(uniqueId: kLocalProfileUniqueId, transaction: transaction),
                let userPublicKey = Storage.shared.getUserPublicKey() {
                let user = Contact(sessionID: userPublicKey)
                user.name = profile.profileName
                user.profilePictureURL = profile.avatarUrlPath
                user.profilePictureFileName = profile.avatarFileName
                user.profilePictureEncryptionKey = profile.profileKey
                result = user
            }
        }
        return result
    }
}
