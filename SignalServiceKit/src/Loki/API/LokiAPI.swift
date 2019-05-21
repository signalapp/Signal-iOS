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
    private static func invoke(_ method: Method, on target: Target, with parameters: [String:Any] = [:]) -> Promise<RawResponse> {
        let url = URL(string: "\(target.address):\(target.port)/\(version)/storage_rpc")!
        let request = TSRequest(url: url, method: "POST", parameters: [ "method" : method.rawValue, "params" : parameters ])
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }
    }
    
    public static func getRandomSnode() -> Promise<Target> {
        return Promise<Target> { seal in
            seal.fulfill(Target(address: "http://13.238.53.205", port: 8080)) // TODO: Temporary
        }
    }
    
    public static func getMessages() -> Promise<[SSKProtoEnvelope]> {
        let parameters = [
            "pubKey" : OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey,
            "lastHash" : "" // TODO: Implement
        ]
        return getRandomSnode().then { invoke(.getMessages, on: $0, with: parameters) }.map { rawResponse in // TODO: Use getSwarm()
            guard let json = rawResponse as? JSON, let messages = json["messages"] as? [JSON] else { return [] }
            return messages.compactMap { message in
                guard let base64EncodedData = message["data"] as? String, let data = Data(base64Encoded: base64EncodedData) else {
                    Logger.warn("[Loki] Failed to decode data for message: \(message).")
                    return nil
                }
                guard let envelope = try? unwrap(data: data) else {
                    Logger.warn("[Loki] Failed to unwrap data for message: \(message).")
                    return nil
                }
                return envelope
            }
        }
    }
    
    public static func sendMessage(_ lokiMessage: Message) -> Promise<RawResponse> {
        return getRandomSnode().then { invoke(.sendMessage, on: $0, with: lokiMessage.toJSON()) } // TODO: Use getSwarm()
    }
    
    public static func ping(_ hexEncodedPublicKey: String) -> Promise<RawResponse> {
        return getRandomSnode().then { invoke(.sendMessage, on: $0, with: [ "pubKey" : hexEncodedPublicKey ]) } // TODO: Use getSwarm() and figure out correct parameters
    }
    
    public static func getSwarm(for hexEncodedPublicKey: String) -> Promise<Set<Target>> {
        return getRandomSnode().then { invoke(.getSwarm, on: $0, with: [ "pubKey" : hexEncodedPublicKey ]) }.map { rawResponse in return [] } // TODO: Parse targets from raw response
    }
    
    // MARK: Obj-C API
    @objc public static func objc_sendSignalMessage(_ signalMessage: SignalMessage, to destination: String, timestamp: UInt64, requiringPoW isPoWRequired: Bool) -> AnyPromise {
        let promise = Message.from(signalMessage: signalMessage, timestamp: timestamp, requiringPoW: isPoWRequired)
            .then(sendMessage)
            .recoverNetworkErrorIfNeeded(on: DispatchQueue.global())
        let anyPromise = AnyPromise(promise)
        anyPromise.retainUntilComplete()
        return anyPromise
    }
}

// MARK: - Convenience

private extension Promise {

    func recoverNetworkErrorIfNeeded(on queue: DispatchQueue) -> Promise<T> {
        return self.recover(on: queue) { error -> Promise<T> in
            switch error {
            case NetworkManagerError.taskError(_, let underlyingError): throw underlyingError
            default: throw error
            }
        }
    }
}

// MARK: Last Hash

extension LokiAPI {
    
    private var primaryStorage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }
    
    fileprivate func updateLastHash(for node: Target, hash: String, expiresAt: UInt64) {
        primaryStorage.dbReadWriteConnection.readWrite { transaction in
            self.primaryStorage.setLastMessageHash(hash, expiresAt: expiresAt, serviceNode: node.address, transaction: transaction)
        }
    }
    
    fileprivate func getLastHash(for node: Target) -> String? {
        var lastHash: String? = nil
        primaryStorage.dbReadWriteConnection.readWrite { transaction in
            lastHash = self.primaryStorage.getLastMessageHash(forServiceNode: node.address, transaction: transaction)
        }
        return lastHash
    }
}
