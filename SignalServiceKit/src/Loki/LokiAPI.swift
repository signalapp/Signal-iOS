import PromiseKit

@objc public final class LokiAPI : NSObject {
    
    private static let version = "v1"
    public static let defaultMessageTTL: UInt64 = 4 * 24 * 60 * 60
    
    // MARK: Types
    private enum Method : String {
        case getMessages = "retrieve"
        case sendMessage = "store"
        case getSwarm = "get_snodes_for_pubkey"
    }
    
    public struct Target : Hashable {
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
        let url = URL(string: "\(target.address):\(target.port)/\(version)/storage_rpc")!
        let request = TSRequest(url: url, method: "POST", parameters: [ "method" : method.rawValue, "params" : parameters ])
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }
    }
    
    public static func getRandomSnode() -> Promise<Target> {
        return Promise<Target> { seal in
            seal.fulfill(Target(address: "http://13.238.53.205", port: 8080)) // TODO: Temporary
        }
    }
    
    public static func getMessages() -> Promise<RawResponse> {
        let parameters = [
            "pubKey" : OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey,
            "lastHash" : "" // TODO: Implement
        ]
        return getRandomSnode().then { invoke(.getMessages, on: $0, with: parameters) } // TODO: Use getSwarm()
    }
    
    public static func sendMessage(_ lokiMessage: LokiMessage) -> Promise<RawResponse> {
        return getRandomSnode().then { invoke(.sendMessage, on: $0, with: lokiMessage.toJSON()) } // TODO: Use getSwarm()
    }
    
    public static func ping(_ hexEncodedPublicKey: String) -> Promise<RawResponse> {
        return getRandomSnode().then { invoke(.sendMessage, on: $0, with: [ "destination" : hexEncodedPublicKey ]) } // TODO: Use getSwarm() and figure out correct parameters
    }
    
    public static func getSwarm(for hexEncodedPublicKey: String) -> Promise<Set<Target>> {
        return getRandomSnode().then { invoke(.getSwarm, on: $0, with: [ "pubKey" : hexEncodedPublicKey ]) }.map { rawResponse in return [] } // TODO: Parse targets from raw response
    }
    
    // MARK: Obj-C API
    @objc public static func getMessagesObjc() -> AnyPromise {
        let promise = getMessages()
        let anyPromise = AnyPromise(promise)
        anyPromise.retainUntilComplete()
        return anyPromise
    }
    
    @objc public static func sendSignalMessage(_ signalMessage: SignalMessage, to destination: String, requiringPoW isPoWRequired: Bool) -> AnyPromise {
        let promise = LokiMessage.fromSignalMessage(signalMessage, requiringPoW: isPoWRequired)
            .then(sendMessage)
            .recover(on: DispatchQueue.global()) { error -> Promise<RawResponse> in
                switch error {
                case NetworkManagerError.taskError(_, let underlyingError):
                    throw underlyingError
                default:
                    throw error
                }
        }
        let anyPromise = AnyPromise(promise)
        anyPromise.retainUntilComplete()
        return anyPromise
    }
}
