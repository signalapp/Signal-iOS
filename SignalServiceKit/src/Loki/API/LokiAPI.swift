import PromiseKit

@objc public final class LokiAPI : NSObject {
    
    // MARK: Caching
    private static var swarmCache: [String:Set<Target>] = [:]
    
    // MARK: Settings
    private static let version = "v1"
    private static let targetSnodeCount = 2
    public static let defaultMessageTTL: UInt64 = 4 * 24 * 60 * 60
    
    // MARK: Types
    fileprivate struct Target : Hashable {
        let address: String
        let port: UInt16
        
        enum Method : String {
            case getSwarm = "get_snodes_for_pubkey"
            case getMessages = "retrieve"
            case sendMessage = "store"
        }
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
    
    public typealias MessagesPromise = Promise<[SSKProtoEnvelope]>
    
    // MARK: Lifecycle
    override private init() { }
    
    // MARK: Internal API
    private static func invoke(_ method: Target.Method, on target: Target, with parameters: [String:Any] = [:]) -> Promise<RawResponse> {
        let url = URL(string: "\(target.address):\(target.port)/\(version)/storage_rpc")!
        let request = TSRequest(url: url, method: "POST", parameters: [ "method" : method.rawValue, "params" : parameters ])
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }
    }
    
    private static func getRandomSnode() -> Promise<Target> {
        return Promise<Target> { seal in
            seal.fulfill(Target(address: "http://13.238.53.205", port: 8080)) // TODO: Temporary
        }
    }
    
    private static func getSwarm(for hexEncodedPublicKey: String) -> Promise<Set<Target>> {
        if let cachedSwarm = swarmCache[hexEncodedPublicKey], cachedSwarm.count >= targetSnodeCount {
            return Promise<Set<Target>> { $0.fulfill(cachedSwarm) }
        } else {
            return getRandomSnode().then { invoke(.getSwarm, on: $0, with: [ "pubKey" : hexEncodedPublicKey ]) }.map { rawResponse in
                return [] // TODO: Parse targets from raw response
            }.get { swarmCache[hexEncodedPublicKey] = $0 }
        }
    }
    
    private static func getTargetSnodes(for hexEncodedPublicKey: String) -> Promise<Set<Target>> {
        return getSwarm(for: hexEncodedPublicKey).map { Set(Array($0).shuffled().prefix(targetSnodeCount)) }
    }
    
    // MARK: Public API
    public static func getMessages() -> Promise<[MessagesPromise]> {
        let hexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
        return getTargetSnodes(for: hexEncodedPublicKey).mapValues { targetSnode in
            let lastHash = getLastHash(for: targetSnode) ?? ""
            let parameters: [String:Any] = [ "pubKey" : hexEncodedPublicKey, "lastHash" : lastHash ]
            return invoke(.getMessages, on: targetSnode, with: parameters).map { response in
                if let json = response as? JSON, let messages = json["messages"] as? [JSON], let lastMessage = messages.last,
                    let hash = lastMessage["hash"] as? String, let expiresAt = lastMessage["expiration"] as? Int {
                    updateLastHash(for: targetSnode, hash: hash, expiresAt: UInt64(expiresAt))
                }
                return parseProtoEnvelopes(from: response)
            }
        }
    }
    
    public static func sendMessage(_ lokiMessage: Message) -> Promise<RawResponse> {
        return getRandomSnode().then { invoke(.sendMessage, on: $0, with: lokiMessage.toJSON()) } // TODO: Use getSwarm()
    }
    
    public static func ping(_ hexEncodedPublicKey: String) -> Promise<RawResponse> {
        return getRandomSnode().then { invoke(.sendMessage, on: $0, with: [ "pubKey" : hexEncodedPublicKey ]) } // TODO: Use getSwarm() and figure out correct parameters
    }
    
    // MARK: Public API (Obj-C)
    @objc public static func objc_sendSignalMessage(_ signalMessage: SignalMessage, to destination: String, timestamp: UInt64, requiringPoW isPoWRequired: Bool) -> AnyPromise {
        let promise = Message.from(signalMessage: signalMessage, timestamp: timestamp, requiringPoW: isPoWRequired).then(sendMessage).recoverNetworkErrorIfNeeded(on: DispatchQueue.global())
        let anyPromise = AnyPromise(promise)
        anyPromise.retainUntilComplete()
        return anyPromise
    }
    
    // MARK: Convenience
    private static func parseProtoEnvelopes(from rawResponse: Any) -> [SSKProtoEnvelope] {
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

private extension Promise {

    func recoverNetworkErrorIfNeeded(on queue: DispatchQueue) -> Promise<T> {
        return recover(on: queue) { error -> Promise<T> in
            switch error {
            case NetworkManagerError.taskError(_, let underlyingError): throw underlyingError
            default: throw error
            }
        }
    }
}

// MARK: Last Hash

fileprivate extension LokiAPI {
    
    private static var primaryStorage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }
    
    fileprivate static func updateLastHash(for node: Target, hash: String, expiresAt: UInt64) {
        primaryStorage.dbReadWriteConnection.readWrite { transaction in
            self.primaryStorage.setLastMessageHash(hash, expiresAt: expiresAt, serviceNode: node.address, transaction: transaction)
        }
    }
    
    fileprivate static func getLastHash(for node: Target) -> String? {
        var lastHash: String? = nil
        primaryStorage.dbReadWriteConnection.readWrite { transaction in
            lastHash = self.primaryStorage.getLastMessageHash(forServiceNode: node.address, transaction: transaction)
        }
        return lastHash
    }
}
