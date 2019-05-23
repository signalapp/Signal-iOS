import PromiseKit

@objc public final class LokiAPI : NSObject {
    internal static let storage = OWSPrimaryStorage.shared()
    
    // MARK: Settings
    private static let version = "v1"
    public static let defaultMessageTTL: UInt64 = 1 * 24 * 60 * 60
    
    internal static let ourHexEncodedPubKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
    
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
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.handlingSwarmSpecificErrorsIfNeeded(for: target, associatedWith: hexEncodedPublicKey)
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
        }.map { Set($0) }
    }
    
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
        
        // By default our p2p throws and we recover by sending to storage server
        var p2pPromise: Promise<Set<Promise<RawResponse>>> = Promise(error: Error.internalError)
        // TODO: probably only send to p2p if user is online or we are pinging them
        // p2pDetails && (isPing || peerIsOnline)

        if let p2pDetails = contactP2PDetails[destination] {
            p2pPromise = sendMessage(message, targets: [p2pDetails])
        }
        
        // If we have the p2p details then send message to that
        // If that failes then fallback to storage server
        return p2pPromise.recover { _ in return sendThroughStorageServer() }
    }
    
    internal static func sendMessage(_ lokiMessage: Message, targets: [Target]) -> Promise<Set<Promise<RawResponse>>> {
        return sendMessage(lokiMessage, targets: Promise.wrap(targets))
    }
    
    internal static func sendMessage(_ lokiMessage: Message, targets: Promise<[Target]>) -> Promise<Set<Promise<RawResponse>>> {
        let parameters = lokiMessage.toJSON()
        return targets.mapValues { invoke(.sendMessage, on: $0, associatedWith: lokiMessage.destination, parameters: parameters) }.map { Set($0) }
    }
    
    public static func ping(_ hexEncodedPublicKey: String) -> Promise<Set<Promise<RawResponse>>> {
        let isP2PMessagingPossible = false
        if isP2PMessagingPossible {
            // TODO: Send using P2P protocol
        } else {
            let parameters: [String:Any] = [ "pubKey" : hexEncodedPublicKey ] // TODO: Figure out correct parameters
            return getTargetSnodes(for: hexEncodedPublicKey).mapValues { invoke(.sendMessage, on: $0, associatedWith: hexEncodedPublicKey, parameters: parameters) }.map { Set($0) }
        }
    }
    
    // MARK: Public API (Obj-C)
    @objc public static func objc_sendSignalMessage(_ signalMessage: SignalMessage, to destination: String, with timestamp: UInt64) -> AnyPromise {
        let promise = sendSignalMessage(signalMessage, to: destination, timestamp: timestamp).mapValues { AnyPromise.from($0) }.map { Set($0) }
        return AnyPromise.from(promise)
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
