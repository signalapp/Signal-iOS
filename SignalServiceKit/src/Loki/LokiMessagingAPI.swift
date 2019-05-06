import PromiseKit

@objc public final class LokiMessagingAPI : NSObject {
    
    private static var baseURL: String { return textSecureServerURL }
    private static var port: String { return "8080" }
    private static var apiVersion: String { return "v1" }
    
    // MARK: Types
    private enum Method : String {
        case retrieveAllMessages = "retrieve"
        case sendMessage = "store"
    }
    
    public typealias RawResponse = TSNetworkManager.NetworkManagerResult
    
    // MARK: Lifecycle
    override private init() { }
    
    // MARK: API
    private static func invoke(_ method: Method, parameters: [String:String] = [:]) -> (request: TSRequest, promise: Promise<RawResponse>) {
        let url = URL(string: "\(baseURL):\(port)/\(apiVersion)/storage_rpc")!
        let request = TSRequest(url: url, method: "POST", parameters: [ "method" : method.rawValue, "params" : parameters ])
        return (request, TSNetworkManager.shared().makePromise(request: request))
    }

    @objc public static func sendMessage(_ message: [String:String]) -> TSRequest {
        return invoke(.sendMessage, parameters: message).request
    }
    
    public static func retrieveAllMessages() -> Promise<RawResponse> {
        let parameters = [
            "pubKey" : OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey,
            "lastHash" : "" // TODO: Implement
        ]
        return invoke(.retrieveAllMessages, parameters: parameters).promise
    }
}
