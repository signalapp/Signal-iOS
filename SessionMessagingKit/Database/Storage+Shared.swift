import PromiseKit

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

    public func getUserDisplayName() -> String? {
        return SSKEnvironment.shared.profileManager.localProfileName()
    }
    
    public func getUserProfileKey() -> Data? {
        return SSKEnvironment.shared.profileManager.localProfileKey().keyData
    }
    
    public func getUserProfilePictureURL() -> String? {
        return SSKEnvironment.shared.profileManager.profilePictureURL()
    }
}
