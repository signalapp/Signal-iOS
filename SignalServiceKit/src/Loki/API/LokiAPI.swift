import PromiseKit

@objc public final class LokiAPI : NSObject {
    internal static let storage = OWSPrimaryStorage.shared()
    
    // MARK: Settings
    private static let version = "v1"
    private static let maxRetryCount: UInt = 3
    public static let defaultMessageTTL: UInt64 = 1 * 24 * 60 * 60 * 1000
    
    // MARK: Types
    public typealias RawResponse = Any
    
    public enum Error : LocalizedError {
        /// Only applicable to snode targets as proof of work isn't required for P2P messaging.
        case proofOfWorkCalculationFailed
        case messageConversionFailed
        
        public var errorDescription: String? {
            switch self {
            case .proofOfWorkCalculationFailed: return NSLocalizedString("Failed to calculate proof of work.", comment: "")
            case .messageConversionFailed: return "Failed to convert Signal message to Loki message."
            }
        }
    }
    
    public typealias MessageListPromise = Promise<[SSKProtoEnvelope]>
    public typealias RawResponsePromise = Promise<RawResponse>
    
    // MARK: Lifecycle
    override private init() { }
    
    // MARK: Internal API
    internal static func invoke(_ method: LokiAPITarget.Method, on target: LokiAPITarget, associatedWith hexEncodedPublicKey: String, parameters: [String:Any] = [:]) -> RawResponsePromise {
        let url = URL(string: "\(target.address):\(target.port)/\(version)/storage_rpc")!
        let request = TSRequest(url: url, method: "POST", parameters: [ "method" : method.rawValue, "params" : parameters ])
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }
            .handlingSwarmSpecificErrorsIfNeeded(for: target, associatedWith: hexEncodedPublicKey).recoveringNetworkErrorsIfNeeded()
    }
    
    // MARK: Public API
    public static func getMessages() -> Promise<Set<MessageListPromise>> {
        let hexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
        return getTargetSnodes(for: hexEncodedPublicKey).mapValues { targetSnode in
            let lastHashValue = getLastMessageHashValue(for: targetSnode) ?? ""
            let parameters: [String:Any] = [ "pubKey" : hexEncodedPublicKey, "lastHash" : lastHashValue ]
            return invoke(.getMessages, on: targetSnode, associatedWith: hexEncodedPublicKey, parameters: parameters).map { rawResponse in
                guard let json = rawResponse as? JSON, let rawMessages = json["messages"] as? [JSON] else { return [] }
                updateLastMessageHashValueIfPossible(for: targetSnode, from: rawMessages)
                let newRawMessages = removeDuplicates(from: rawMessages)
                return parseProtoEnvelopes(from: newRawMessages)
            }
        }.map { Set($0) }.retryingIfNeeded(maxRetryCount: maxRetryCount)
    }
    
    public static func sendSignalMessage(_ signalMessage: SignalMessage, onP2PSuccess: @escaping () -> Void) -> Promise<Set<RawResponsePromise>> {
        guard let lokiMessage = Message.from(signalMessage: signalMessage) else { return Promise(error: Error.messageConversionFailed) }
        let destination = lokiMessage.destination
        func sendLokiMessage(_ lokiMessage: Message, to target: LokiAPITarget) -> RawResponsePromise {
            let parameters = lokiMessage.toJSON()
            return invoke(.sendMessage, on: target, associatedWith: destination, parameters: parameters)
        }
        func sendLokiMessageUsingSwarmAPI() -> Promise<Set<RawResponsePromise>> {
            let powPromise = lokiMessage.calculatePoW()
            let swarmPromise = getTargetSnodes(for: destination)
            return when(fulfilled: powPromise, swarmPromise).map { lokiMessageWithPoW, swarm in
                return Set(swarm.map { sendLokiMessage(lokiMessageWithPoW, to: $0) })
            }.retryingIfNeeded(maxRetryCount: maxRetryCount)
        }
        if let peer = LokiP2PManager.getInfo(for: destination), (lokiMessage.isPing || peer.isOnline) {
            let target = LokiAPITarget(address: peer.address, port: peer.port)
            return Promise.value([ target ]).mapValues { sendLokiMessage(lokiMessage, to: $0) }.map { Set($0) }.retryingIfNeeded(maxRetryCount: maxRetryCount).get { _ in
                LokiP2PManager.markOnline(destination)
                onP2PSuccess()
            }.recover { error -> Promise<Set<RawResponsePromise>> in
                LokiP2PManager.markOffline(destination)
                if lokiMessage.isPing {
                    Logger.warn("[Loki] Failed to ping \(destination); marking contact as offline.")
                    if let error = error as? NSError {
                        error.isRetryable = false
                        throw error
                    } else {
                        throw error
                    }
                }
                return sendLokiMessageUsingSwarmAPI()
            }
        } else {
            return sendLokiMessageUsingSwarmAPI()
        }
    }
    
    // MARK: Public API (Obj-C)
    @objc(sendSignalMessage:onP2PSuccess:)
    public static func objc_sendSignalMessage(_ signalMessage: SignalMessage, onP2PSuccess: @escaping () -> Void) -> AnyPromise {
        let promise = sendSignalMessage(signalMessage, onP2PSuccess: onP2PSuccess).mapValues { AnyPromise.from($0) }.map { Set($0) }
        return AnyPromise.from(promise)
    }
    
    // MARK: Parsing
    
    // The parsing utilities below use a best attempt approach to parsing; they warn for parsing failures but don't throw exceptions.
    
    private static func updateLastMessageHashValueIfPossible(for target: LokiAPITarget, from rawMessages: [JSON]) {
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
