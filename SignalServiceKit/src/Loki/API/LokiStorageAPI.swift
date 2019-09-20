import PromiseKit

@objc(LKStorageAPI)
public final class LokiStorageAPI : NSObject {
    
    // MARK: Lifecycle
    override private init() { }
    
    // MARK: Public API
    public static func addDeviceLink(_ deviceLink: LokiDeviceLink) -> Promise<Void> {
        // Adds the given device link to the user's device mapping on the server
        notImplemented()
    }
    
    public static func removeDeviceLink(_ deviceLink: LokiDeviceLink) -> Promise<Void> {
        // Removes the given device link from the user's device mapping on the server
        notImplemented()
    }
    
    public static func getDeviceLinks(associatedWith hexEncodedPublicKey: String) -> Promise<Set<LokiDeviceLink>> {
        // Gets the device links associated with the given hex encoded public key from the
        // server and stores and returns the valid ones
        notImplemented()
    }
}
