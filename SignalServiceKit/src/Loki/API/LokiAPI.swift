import PromiseKit

@objc public final class LokiAPI : NSObject {
    internal static let storage = OWSPrimaryStorage.shared()
    
    // MARK: Settings
    private static let version = "v1"
    public static let defaultMessageTTL: UInt64 = 1 * 24 * 60 * 60 * 1000
    private static let maxRetryCount: UInt = 3
    
    private static let ourHexEncodedPubKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
    
    // MARK: Types
    public typealias RawResponse = Any
    
    public enum Error : LocalizedError {
        /// Only applicable to snode targets as proof of work isn't required for P2P messaging.
        case proofOfWorkCalculationFailed
        
        // Failed to send the message'
        case internalError
        
        public var errorDescription: String? {
            switch self {
            case .proofOfWorkCalculationFailed: return NSLocalizedString("Failed to calculate proof of work.", comment: "")
            case .internalError: return "Failed while trying to send message"
            }
        }
    }
    
    // MARK: Lifecycle
    override private init() { }
    
    // MARK: Internal API
    internal static func invoke(_ method: Target.Method, on target: Target, associatedWith hexEncodedPublicKey: String, parameters: [String:Any] = [:]) -> Promise<RawResponse> {
        let url = URL(string: "\(target.address):\(target.port)/\(version)/storage_rpc")!
        let request = TSRequest(url: url, method: "POST", parameters: [ "method" : method.rawValue, "params" : parameters ])
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }
            .handlingSwarmSpecificErrorsIfNeeded(for: target, associatedWith: hexEncodedPublicKey).recoveringNetworkErrorsIfNeeded()
    }
    
    // MARK: Public API
    public static func getMessages() -> Promise<Set<Promise<[SSKProtoEnvelope]>>> {
        return getTargetSnodes(for: ourHexEncodedPubKey).mapValues { targetSnode in
            let lastHash = getLastMessageHashValue(for: targetSnode) ?? ""
            let parameters: [String:Any] = [ "pubKey" : ourHexEncodedPubKey, "lastHash" : lastHash ]
            return invoke(.getMessages, on: targetSnode, associatedWith: ourHexEncodedPubKey, parameters: parameters).map { rawResponse in
                guard let json = rawResponse as? JSON, let rawMessages = json["messages"] as? [JSON] else { return [] }
                updateLastMessageHashValueIfPossible(for: targetSnode, from: rawMessages)
                let newRawMessages = removeDuplicates(from: rawMessages)
                return parseProtoEnvelopes(from: newRawMessages)
            }
        }.retryingIfNeeded(maxRetryCount: maxRetryCount).map { Set($0) }
    }
    
    // MARK: Public API (Obj-C)
    @objc public static func objc_sendSignalMessage(_ signalMessage: SignalMessage, to destination: String, with timestamp: UInt64) -> AnyPromise {
        let promise = sendSignalMessage(signalMessage, to: destination, timestamp: timestamp).mapValues { AnyPromise.from($0) }.map { Set($0) }
        return AnyPromise.from(promise)
    }
    
    // MARK: Sending
    public static func sendSignalMessage(_ signalMessage: SignalMessage, to destination: String, timestamp: UInt64) -> Promise<Set<Promise<RawResponse>>> {
        guard let message = Message.from(signalMessage: signalMessage, timestamp: timestamp) else {
            return Promise(error: Error.internalError)
        }
        
        // Send message through the storage server
        // We put this here because `recover` expects `Promise<Set<Promise<RawResponse>>>`
        let sendThroughStorageServer: () -> Promise<Set<Promise<RawResponse>>> = { () in
            return message.calculatePoW().then { powMessage -> Promise<Set<Promise<RawResponse>>> in
                let snodes = getTargetSnodes(for: powMessage.destination)
                return sendMessage(powMessage, targets: snodes)
            }
        }
        
        // If we have the p2p details and we have marked the user as online OR we are pinging the user, then use peer to peer
        // If that failes then fallback to storage server
        if let p2pDetails = LokiP2PManager.getDetails(forContact: destination), message.isPing || p2pDetails.isOnline {
            let targets = Promise.wrap([p2pDetails.target])
            return sendMessage(message, targets: targets).then { result -> Promise<Set<Promise<RawResponse>>> in
                LokiP2PManager.setOnline(true, forContact: destination)
                return Promise.wrap(result)
            }.recover { error -> Promise<Set<Promise<RawResponse>>> in
                // The user is not online
                LokiP2PManager.setOnline(false, forContact: destination)

                // If it was a ping then don't send to the storage server
                if (message.isPing) {
                    Logger.warn("[Loki] Failed to ping \(destination) - Marking contact as offline.")
                    let nserror = error as NSError
                    nserror.isRetryable = false
                    throw nserror
                }
                
                return sendThroughStorageServer()
            }
        }
        
        return sendThroughStorageServer()
    }
    
    internal static func sendMessage(_ lokiMessage: Message, targets: Promise<[Target]>) -> Promise<Set<Promise<RawResponse>>> {
        let parameters = lokiMessage.toJSON()
        return targets.mapValues { invoke(.sendMessage, on: $0, associatedWith: lokiMessage.destination, parameters: parameters) }.map { Set($0) }
    }
    
    // MARK: Parsing
    
    // The parsing utilities below use a best attempt approach to parsing; they warn for parsing failures but don't throw exceptions.
    
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
            guard let envelope = try? LokiMessageWrapper.unwrap(data: data) else {
                Logger.warn("[Loki] Failed to unwrap data for message: \(rawMessage).")
                return nil
            }
            return envelope
        }
    }
}
