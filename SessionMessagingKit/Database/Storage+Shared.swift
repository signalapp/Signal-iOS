
// TODO: Since we now have YapDatabase as a dependency in all modules we can work with YapDatabaseTransactions directly
// rather than passing transactions around as Any everywhere.

extension Storage {

    // TODO: This is essentially a duplicate of Storage.writeSync
    public func with(_ work: @escaping (Any) -> Void) {
        Storage.writeSync { work($0) }
    }

    // TODO: This is essentially a duplicate of Storage.write
    public func withAsync(_ work: @escaping (Any) -> Void, completion: @escaping () -> Void) {
        Storage.write(with: { work($0) }, completion: completion)
    }

    public func getUserPublicKey() -> String? {
        return OWSIdentityManager.shared().identityKeyPair()?.hexEncodedPublicKey
    }

    public func getUserKeyPair() -> ECKeyPair? {
        return OWSIdentityManager.shared().identityKeyPair()
    }

    public func getUserDisplayName() -> String? {
        return SSKEnvironment.shared.profileManager.localProfileName()
    }
}
