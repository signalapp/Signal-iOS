import PromiseKit

@objc public final class LokiAPI : NSObject {
    private static let storage = OWSPrimaryStorage.shared()
    
    // MARK: Settings
    private static let version = "v1"
    private static let defaultSnodePort: UInt16 = 8080
    private static let targetSnodeCount = 2
    public static let defaultMessageTTL: UInt64 = 4 * 24 * 60 * 60
    
    // MARK: Caching
    private static var swarmCache: [String:[Target]] = [:]
    
    // MARK: Types
    private struct Target : Hashable {
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
    
    // MARK: Lifecycle
    override private init() { }
    
    // MARK: Internal API
    private static func invoke(_ method: Target.Method, on target: Target, with parameters: [String:Any] = [:]) -> Promise<RawResponse> {
        let url = URL(string: "\(target.address):\(target.port)/\(version)/storage_rpc")!
        let request = TSRequest(url: url, method: "POST", parameters: [ "method" : method.rawValue, "params" : parameters ])
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }
    }
    
    private static func getRandomSnode() -> Promise<Target> {
        return Promise<Target> { _ in notImplemented() } // TODO: Implement
    }
    
    private static func getSwarm(for hexEncodedPublicKey: String) -> Promise<[Target]> {
        if let cachedSwarm = swarmCache[hexEncodedPublicKey], cachedSwarm.count >= targetSnodeCount {
            return Promise<[Target]> { $0.fulfill(cachedSwarm) }
        } else {
            let parameters: [String:Any] = [ "pubKey" : hexEncodedPublicKey ]
            return getRandomSnode().then { invoke(.getSwarm, on: $0, with: parameters) }.map { parseTargets(from: $0) }.get { swarmCache[hexEncodedPublicKey] = $0 }
        }
    }
    
    private static func getTargetSnodes(for hexEncodedPublicKey: String) -> Promise<[Target]> {
        // shuffled() uses the system's default random generator, which is cryptographically secure
        return getSwarm(for: hexEncodedPublicKey).map { Array($0.shuffled().prefix(targetSnodeCount)) }
    }
    
    // MARK: Public API
    public static func getMessages() -> Promise<Set<Promise<[SSKProtoEnvelope]>>> {
        let hexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
        return getTargetSnodes(for: hexEncodedPublicKey).mapValues { targetSnode in
            let lastHash = getLastMessageHashValue(for: targetSnode) ?? ""
            let parameters: [String:Any] = [ "pubKey" : hexEncodedPublicKey, "lastHash" : lastHash ]
            return invoke(.getMessages, on: targetSnode, with: parameters).map { rawResponse in
                guard let json = rawResponse as? JSON, let rawMessages = json["messages"] as? [JSON] else { return [] }
                updateLastMessageHashValueIfPossible(for: targetSnode, from: rawMessages)
                let newRawMessages = removeDuplicates(from: rawMessages)
                return parseProtoEnvelopes(from: newRawMessages)
            }
        }.map { Set($0) }
    }
    
    public static func sendMessage(_ lokiMessage: Message) -> Promise<Set<Promise<RawResponse>>> {
        let parameters = lokiMessage.toJSON()
        return getTargetSnodes(for: lokiMessage.destination).mapValues { invoke(.sendMessage, on: $0, with: parameters).recoverNetworkErrorIfNeeded(on: DispatchQueue.global()) }.map { Set($0) }
    }
    
    public static func ping(_ hexEncodedPublicKey: String) -> Promise<Set<Promise<RawResponse>>> {
        let parameters: [String:Any] = [ "pubKey" : hexEncodedPublicKey ] // TODO: Figure out correct parameters
        return getTargetSnodes(for: hexEncodedPublicKey).mapValues { invoke(.sendMessage, on: $0, with: parameters).recoverNetworkErrorIfNeeded(on: DispatchQueue.global()) }.map { Set($0) }
    }
    
    // MARK: Public API (Obj-C)
    @objc public static func objc_sendSignalMessage(_ signalMessage: SignalMessage, to destination: String, timestamp: UInt64, requiringPoW isPoWRequired: Bool) -> AnyPromise {
        let promise = Message.from(signalMessage: signalMessage, timestamp: timestamp, requiringPoW: isPoWRequired).then(sendMessage).mapValues { promise -> AnyPromise in
            let anyPromise = AnyPromise(promise)
            anyPromise.retainUntilComplete()
            return anyPromise
        }.map { Set($0) }
        let anyPromise = AnyPromise(promise)
        anyPromise.retainUntilComplete()
        return anyPromise
    }
    
    // MARK: Parsing
    
    // The parsing utilities below use a best attempt approach to parsing; they warn for parsing failures but don't throw exceptions.
    
    private static func parseTargets(from rawResponse: Any) -> [Target] {
        guard let json = rawResponse as? JSON, let addresses = json["snodes"] as? [String] else {
            Logger.warn("[Loki] Failed to parse targets from: \(rawResponse).")
            return []
        }
        return addresses.map { Target(address: $0, port: defaultSnodePort) }
    }
    
    private static func updateLastMessageHashValueIfPossible(for target: Target, from rawMessages: [JSON]) {
        guard let lastMessage = rawMessages.last, let hashValue = lastMessage["hash"] as? String, let expiresAt = lastMessage["expiration"] as? Int else {
            Logger.warn("[Loki] Failed to update last message hash value from: \(rawMessages).")
            return
        }
        setLastMessageHashValue(for: target, hashValue: hashValue, expiresAt: UInt64(expiresAt))
    }
    
    private static func removeDuplicates(from rawMessages: [JSON]) -> [JSON] {
        var receivedMessageHashValues = getReceivedMessageHashValues() ?? []
        return rawMessages.filter { rawMessage in
            guard let hashValue = rawMessage["hash"] as? String else {
                Logger.warn("[Loki] Missing hash value for message: \(rawMessage).")
                return false
            }
            let isDuplicate = receivedMessageHashValues.contains(hashValue)
            receivedMessageHashValues.insert(hashValue)
            setReceivedMessageHashValues(to: receivedMessageHashValues)
            return !isDuplicate
        }
    }
    
    private static func parseProtoEnvelopes(from rawMessages: [JSON]) -> [SSKProtoEnvelope] {
        return rawMessages.compactMap { rawMessage in
            guard let base64EncodedData = rawMessage["data"] as? String, let data = Data(base64Encoded: base64EncodedData) else {
                Logger.warn("[Loki] Failed to decode data for message: \(rawMessage).")
                return nil
            }
            guard let envelope = try? unwrap(data: data) else {
                Logger.warn("[Loki] Failed to unwrap data for message: \(rawMessage).")
                return nil
            }
            return envelope
        }
    }
    
    // MARK: Convenience
    private static func getLastMessageHashValue(for target: Target) -> String? {
        var result: String? = nil
        // Uses a read/write connection because getting the last message hash value also removes expired messages as needed
        storage.dbReadWriteConnection.readWrite { transaction in
            result = storage.getLastMessageHash(forServiceNode: target.address, transaction: transaction)
        }
        return result
    }
    
    private static func setLastMessageHashValue(for target: Target, hashValue: String, expiresAt: UInt64) {
        storage.dbReadWriteConnection.readWrite { transaction in
            storage.setLastMessageHash(forServiceNode: target.address, hash: hashValue, expiresAt: expiresAt, transaction: transaction)
        }
    }
    
    private static func getReceivedMessageHashValues() -> Set<String>? {
        var result: Set<String>? = nil
        storage.dbReadConnection.read { transaction in
            result = storage.getReceivedMessageHashes(with: transaction)
        }
        return result
    }
    
    private static func setReceivedMessageHashValues(to receivedMessageHashValues: Set<String>) {
        storage.dbReadWriteConnection.readWrite { transaction in
            storage.setReceivedMessageHashes(receivedMessageHashValues, with: transaction)
        }
    }
}

// MARK: Error Handling
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
