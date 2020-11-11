
extension Storage {

    public static let shared = Storage()

    public func with(_ work: @escaping (Any) -> Void) {
        Storage.writeSync { work($0) }
    }

    public func getUserPublicKey() -> String? {
        return OWSIdentityManager.shared().identityKeyPair()?.publicKey.toHexString()
    }
}
