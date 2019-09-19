import PromiseKit

@objc(LKDeviceLinkingAPI)
final class LokiDeviceLinkingAPI : NSObject {

    // MARK: Settings
    private static let listeningTimeout = 60

    // MARK: Types
    public struct Account {
        public let hexEncodedPublicKey: String
        public let isMaster: Bool
    }

    // MARK: Lifecycle
    override private init() { }

    // MARK: Public API
    @objc public static func startListeningForLinkingRequests(onLinkingRequestReceived: (String) -> Void, onTimeout: () -> Void) {
        // Listens for linking requests until either one is received or listeningTimeout is reached
    }

    @objc public static func authorizeLinkingRequest(with signature: String) {
        // Authorize the linking request with the given signature
    }

    public static func addSlaveAccount(with hexEncodedPublicKey: String) -> Promise<String> {
        // Adds the given slave account to the user's device mapping on the server
        notImplemented()
    }

    public static func removeSlaveAccount(with hexEncodedPublicKey: String) -> Promise<String> {
        // Removes the given slave account from the user's device mapping on the server
        notImplemented()
    }

    public static func getAccounts(for hexEncodedPublicKey: String) -> Promise<[Account]> {
        // Gets the accounts associated with the given hex encoded public key from the server
        notImplemented()
    }
}

//LokiDeviceLinkingAPI.startListeningForLinkingRequests(onLinkingRequestReceived: { signature in
//    // 1. Validate the signature
//    // 2. Ask the user to accept
//    // 2.1. If the user declined, we're done
//    // 2.2, If the user accepted: LokiDeviceLinkingAPI.authorizeLinkingRequest(with: signature)
//}, onTimeout: {
//    // Notify the user
//})
