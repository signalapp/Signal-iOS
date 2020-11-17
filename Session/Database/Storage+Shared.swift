
extension Storage {

    public static let shared = Storage()

    public func with(_ work: @escaping (Any) -> Void) {
        Storage.writeSync { work($0) }
    }

    public func withAsync(_ work: @escaping (Any) -> Void, completion: @escaping () -> Void) {
        Storage.write(with: { work($0) }, completion: completion)
    }

    public func getUserPublicKey() -> String? {
        return OWSIdentityManager.shared().identityKeyPair()?.publicKey.toHexString()
    }

    public func getUserKeyPair() -> ECKeyPair? {
        return OWSIdentityManager.shared().identityKeyPair()
    }

    public func getUserDisplayName() -> String? { fatalError() }
}
