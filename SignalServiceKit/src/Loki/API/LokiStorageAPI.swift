import PromiseKit

@objc(LKStorageAPI)
public final class LokiStorageAPI : NSObject {
    
    // MARK: Lifecycle
    override private init() { }
    
    // MARK: Public API
    public static func addSlaveAccount(with hexEncodedPublicKey: String) -> Promise<Void> {
        // Adds the given slave account to the user's device mapping on the server
        notImplemented()
    }
    
    public static func removeSlaveAccount(with hexEncodedPublicKey: String) -> Promise<Void> {
        // Removes the given slave account from the user's device mapping on the server
        notImplemented()
    }
    
    public static func getOtherAccounts(for hexEncodedPublicKey: String) -> Promise<[String]> {
        // Gets the accounts associated with the given hex encoded public key from the server
        notImplemented()
    }
}
