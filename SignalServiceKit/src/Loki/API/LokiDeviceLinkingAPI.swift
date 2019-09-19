import PromiseKit

@objc(LKDeviceLinkingAPI)
final class LokiDeviceLinkingAPI : NSObject {

    private static var timerStartDate: Date?
    public static var isListeningForLinkingRequests = false

    // MARK: Settings
    private static let listeningTimeout: TimeInterval = 60

    // MARK: Lifecycle
    override private init() { }

    // MARK: Public API
    @objc public static func startListeningForLinkingRequests(onLinkingRequestReceived: (String) -> Void, onTimeout: @escaping () -> Void) {
        isListeningForLinkingRequests = true
        timerStartDate = Date()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if Date().timeIntervalSince1970 - timerStartDate!.timeIntervalSince1970 >= listeningTimeout {
                isListeningForLinkingRequests = false
                onTimeout()
            }
        }
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

    public static func getOtherAccounts(for hexEncodedPublicKey: String) -> Promise<[String]> {
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
