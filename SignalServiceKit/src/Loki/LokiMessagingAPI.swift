import PromiseKit

@objc public final class LokiMessagingAPI : NSObject {
    
    private static let apiVersion = "v1"
    public static let defaultTTL: UInt64 = 4 * 24 * 60 * 60
    
    // MARK: Types
    private enum Method : String {
        case retrieveNewMessages = "retrieve"
        case sendMessage = "store"
    }
    
    private struct Target {
        let address: String
        let port: UInt16
    }
    
    public typealias RawResponse = Any
    
    public enum Error : LocalizedError {
        case proofOfWorkCalculationFailed
        
        public var errorDescription: String? {
            switch self {
            case .proofOfWorkCalculationFailed: return NSLocalizedString("Failed to calculate proof of work.", comment: "")
            }
        }
    }
    
    // MARK: Lifecycle
    override private init() { }
    
    // MARK: API
    private static func invoke(_ method: Method, on target: Target, with parameters: [String:String] = [:]) -> Promise<RawResponse> {
        let url = URL(string: "\(target.address):\(target.port)/\(apiVersion)/storage_rpc")!
        let request = TSRequest(url: url, method: "POST", parameters: [ "method" : method.rawValue, "params" : parameters ])
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }
    }
    
    public static func sendSignalMessage(_ signalMessage: SignalMessage, to destination: String, requiringPoW isPoWRequired: Bool) -> Promise<RawResponse> {
        return LokiMessage.fromSignalMessage(signalMessage, requiringPoW: isPoWRequired).then(sendMessage)
    }
    
    public static func sendMessage(_ lokiMessage: LokiMessage) -> Promise<RawResponse> {
        let target = Target(address: "http://13.238.53.205", port: 8080)
        return invoke(.sendMessage, on: target, with: lokiMessage.toJSON())
    }
    
    public static func retrieveAllMessages() -> Promise<RawResponse> {
        let target = Target(address: "http://13.238.53.205", port: 8080)
        let parameters = [
            "pubKey" : OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey,
            "lastHash" : "" // TODO: Implement
        ]
        return invoke(.retrieveNewMessages, on: target, with: parameters)
    }
    
    // MARK: Obj-C API
    @objc public static func sendSignalMessage(_ signalMessage: SignalMessage, to destination: String, requiringPoW isPoWRequired: Bool, completionHandler: ((RawResponse?, NSError?) -> Void)? = nil) {
        sendSignalMessage(signalMessage, to: destination, requiringPoW: isPoWRequired).done { completionHandler?($0, nil) }.catch { completionHandler?(nil, $0 as NSError) }
    }
}
