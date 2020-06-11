import PromiseKit

// TODO: We guarantee that things happen in-order through promise chaining. For performance we should be able to use different queues for everything as long
// as we always modify state from the same queue.

@objc(LKAPI)
public final class LokiAPI : NSObject {

    /// All service node related errors must be handled on this queue to avoid race conditions maintaining e.g. failure counts.
    internal static let errorHandlingQueue = DispatchQueue(label: "LokiAPI.errorHandlingQueue")
    internal static let stateQueue = DispatchQueue(label: "LokiAPI.stateQueue")
    internal static let workQueue = DispatchQueue(label: "LokiAPI.workQueue", qos: .userInitiated)

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }
    
    // MARK: Settings
    private static let maxRetryCount: UInt = 4
    private static let defaultTimeout: TimeInterval = 20
    private static let longPollingTimeout: TimeInterval = 40

    internal static var powDifficulty: UInt = 1
    /// - Note: Changing this on the fly is not recommended.
    internal static var useOnionRequests = true
    
    // MARK: Nested Types
    public typealias RawResponse = Any
    
    @objc public class LokiAPIError : NSError { // Not called `Error` for Obj-C interoperablity
        
        @objc public static let proofOfWorkCalculationFailed = LokiAPIError(domain: "LokiAPIErrorDomain", code: 1, userInfo: [ NSLocalizedDescriptionKey : "Failed to calculate proof of work." ])
        @objc public static let messageConversionFailed = LokiAPIError(domain: "LokiAPIErrorDomain", code: 2, userInfo: [ NSLocalizedDescriptionKey : "Failed to construct message." ])
        @objc public static let clockOutOfSync = LokiAPIError(domain: "LokiAPIErrorDomain", code: 3, userInfo: [ NSLocalizedDescriptionKey : "Your clock is out of sync with the service node network." ])
        @objc public static let randomSnodePoolUpdatingFailed = LokiAPIError(domain: "LokiAPIErrorDomain", code: 4, userInfo: [ NSLocalizedDescriptionKey : "Failed to update random service node pool." ])
        @objc public static let missingSnodeVersion = LokiAPIError(domain: "LokiAPIErrorDomain", code: 5, userInfo: [ NSLocalizedDescriptionKey : "Missing service node version." ])
    }
    
    public typealias MessageListPromise = Promise<[SSKProtoEnvelope]>
    
    public typealias RawResponsePromise = Promise<RawResponse>
    
    // MARK: Lifecycle
    override private init() { }
    
    // MARK: Internal API
    internal static func invoke(_ method: LokiAPITarget.Method, on target: LokiAPITarget, associatedWith hexEncodedPublicKey: String,
        parameters: JSON, headers: [String:String]? = nil, timeout: TimeInterval? = nil) -> RawResponsePromise {
        let url = URL(string: "\(target.address):\(target.port)/storage_rpc/v1")!
        if useOnionRequests {
            return OnionRequestAPI.sendOnionRequest(invoking: method, on: target, with: parameters, associatedWith: hexEncodedPublicKey).map { $0 as Any }
        } else {
            let request = TSRequest(url: url, method: "POST", parameters: [ "method" : method.rawValue, "params" : parameters ])
            if let headers = headers { request.allHTTPHeaderFields = headers }
            request.timeoutInterval = timeout ?? defaultTimeout
            return TSNetworkManager.shared().perform(request, withCompletionQueue: workQueue)
                .map { $0.responseObject }
                .handlingSnodeErrorsIfNeeded(for: target, associatedWith: hexEncodedPublicKey)
                .recoveringNetworkErrorsIfNeeded()
        }
    }
    
    internal static func getRawMessages(from target: LokiAPITarget, usingLongPolling useLongPolling: Bool) -> RawResponsePromise {
        let lastHashValue = getLastMessageHashValue(for: target) ?? ""
        let parameters = [ "pubKey" : getUserHexEncodedPublicKey(), "lastHash" : lastHashValue ]
        let headers: [String:String]? = useLongPolling ? [ "X-Loki-Long-Poll" : "true" ] : nil
        let timeout: TimeInterval? = useLongPolling ? longPollingTimeout : nil
        return invoke(.getMessages, on: target, associatedWith: getUserHexEncodedPublicKey(), parameters: parameters, headers: headers, timeout: timeout)
    }
    
    // MARK: Public API
    public static func getMessages() -> Promise<Set<MessageListPromise>> {
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: workQueue) {
            getTargetSnodes(for: getUserHexEncodedPublicKey()).mapValues { targetSnode in
                getRawMessages(from: targetSnode, usingLongPolling: false).map { parseRawMessagesResponse($0, from: targetSnode) }
            }.map { Set($0) }
        }
    }

    @objc(sendSignalMessage:onP2PSuccess:)
    public static func objc_sendSignalMessage(_ signalMessage: SignalMessage, onP2PSuccess: @escaping () -> Void) -> AnyPromise {
        let promise = sendSignalMessage(signalMessage, onP2PSuccess: onP2PSuccess).mapValues { AnyPromise.from($0) }.map { Set($0) }
        return AnyPromise.from(promise)
    }

    public static func sendSignalMessage(_ signalMessage: SignalMessage, onP2PSuccess: @escaping () -> Void) -> Promise<Set<RawResponsePromise>> {
        guard let lokiMessage = LokiMessage.from(signalMessage: signalMessage) else { return Promise(error: LokiAPIError.messageConversionFailed) }
        let notificationCenter = NotificationCenter.default
        let destination = lokiMessage.destination
        func sendLokiMessage(_ lokiMessage: LokiMessage, to target: LokiAPITarget) -> RawResponsePromise {
            let parameters = lokiMessage.toJSON()
            return attempt(maxRetryCount: maxRetryCount, recoveringOn: workQueue) {
                invoke(.sendMessage, on: target, associatedWith: destination, parameters: parameters)
            }
        }
        func sendLokiMessageUsingSwarmAPI() -> Promise<Set<RawResponsePromise>> {
            notificationCenter.post(name: .calculatingPoW, object: NSNumber(value: signalMessage.timestamp))
            return lokiMessage.calculatePoW().then { lokiMessageWithPoW -> Promise<Set<RawResponsePromise>> in
                notificationCenter.post(name: .routing, object: NSNumber(value: signalMessage.timestamp))
                return getTargetSnodes(for: destination).map { snodes in
                    return Set(snodes.map { snode in
                        notificationCenter.post(name: .messageSending, object: NSNumber(value: signalMessage.timestamp))
                        return sendLokiMessage(lokiMessageWithPoW, to: snode).map { rawResponse in
                            if let json = rawResponse as? JSON, let powDifficulty = json["difficulty"] as? Int {
                                guard powDifficulty != LokiAPI.powDifficulty else { return rawResponse }
                                print("[Loki] Setting proof of work difficulty to \(powDifficulty).")
                                LokiAPI.powDifficulty = UInt(powDifficulty)
                            } else {
                                print("[Loki] Failed to update proof of work difficulty from: \(rawResponse).")
                            }
                            return rawResponse
                        }
                    })
                }
            }
        }
        if let peer = LokiP2PAPI.getInfo(for: destination), (lokiMessage.isPing || peer.isOnline) {
            let target = LokiAPITarget(address: peer.address, port: peer.port, publicKeySet: nil)
            // TODO: Retrying
            return Promise.value([ target ]).mapValues { sendLokiMessage(lokiMessage, to: $0) }.map { Set($0) }.get { _ in
                LokiP2PAPI.markOnline(destination)
                onP2PSuccess()
            }.recover { error -> Promise<Set<RawResponsePromise>> in
                LokiP2PAPI.markOffline(destination)
                if lokiMessage.isPing {
                    print("[Loki] Failed to ping \(destination); marking contact as offline.")
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
    
    // MARK: Parsing
    
    // The parsing utilities below use a best attempt approach to parsing; they warn for parsing failures but don't throw exceptions.
    
    internal static func parseRawMessagesResponse(_ rawResponse: Any, from target: LokiAPITarget) -> [SSKProtoEnvelope] {
        guard let json = rawResponse as? JSON, let rawMessages = json["messages"] as? [JSON] else { return [] }
        updateLastMessageHashValueIfPossible(for: target, from: rawMessages)
        let newRawMessages = removeDuplicates(from: rawMessages)
        let newMessages = parseProtoEnvelopes(from: newRawMessages)
        let newMessageCount = newMessages.count
        return newMessages
    }
    
    private static func updateLastMessageHashValueIfPossible(for target: LokiAPITarget, from rawMessages: [JSON]) {
        if let lastMessage = rawMessages.last, let hashValue = lastMessage["hash"] as? String, let expirationDate = lastMessage["expiration"] as? Int {
            setLastMessageHashValue(for: target, hashValue: hashValue, expirationDate: UInt64(expirationDate))
            // FIXME: Move this out of here 
            if UserDefaults.standard[.isUsingFullAPNs] {
                LokiPushNotificationManager.acknowledgeDelivery(forMessageWithHash: hashValue, expiration: expirationDate, hexEncodedPublicKey: getUserHexEncodedPublicKey())
            }
        } else if (!rawMessages.isEmpty) {
            print("[Loki] Failed to update last message hash value from: \(rawMessages).")
        }
    }
    
    private static func removeDuplicates(from rawMessages: [JSON]) -> [JSON] {
        var receivedMessageHashValues = getReceivedMessageHashValues() ?? []
        return rawMessages.filter { rawMessage in
            guard let hashValue = rawMessage["hash"] as? String else {
                print("[Loki] Missing hash value for message: \(rawMessage).")
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
                print("[Loki] Failed to decode data for message: \(rawMessage).")
                return nil
            }
            guard let envelope = try? LokiMessageWrapper.unwrap(data: data) else {
                print("[Loki] Failed to unwrap data for message: \(rawMessage).")
                return nil
            }
            return envelope
        }
    }

    // MARK: Message Hash Caching
    private static func getLastMessageHashValue(for target: LokiAPITarget) -> String? {
        var result: String? = nil
        // Uses a read/write connection because getting the last message hash value also removes expired messages as needed
        // TODO: This shouldn't be the case; a getter shouldn't have an unexpected side effect
        try! Storage.syncWrite { transaction in
            result = storage.getLastMessageHash(forSnode: target.address, transaction: transaction)
        }
        return result
    }

    private static func setLastMessageHashValue(for target: LokiAPITarget, hashValue: String, expirationDate: UInt64) {
        try! Storage.syncWrite { transaction in
            storage.setLastMessageHash(forSnode: target.address, hash: hashValue, expiresAt: expirationDate, transaction: transaction)
        }
    }
    
    private static let receivedMessageHashValuesKey = "receivedMessageHashValuesKey"
    private static let receivedMessageHashValuesCollection = "receivedMessageHashValuesCollection"
    
    private static func getReceivedMessageHashValues() -> Set<String>? {
        var result: Set<String>? = nil
        storage.dbReadConnection.read { transaction in
            result = transaction.object(forKey: receivedMessageHashValuesKey, inCollection: receivedMessageHashValuesCollection) as! Set<String>?
        }
        return result
    }

    private static func setReceivedMessageHashValues(to receivedMessageHashValues: Set<String>) {
        try! Storage.syncWrite { transaction in
            transaction.setObject(receivedMessageHashValues, forKey: receivedMessageHashValuesKey, inCollection: receivedMessageHashValuesCollection)
        }
    }
}

// MARK: Error Handling
private extension Promise {

    fileprivate func recoveringNetworkErrorsIfNeeded() -> Promise<T> {
        return recover { error -> Promise<T> in
            switch error {
            case NetworkManagerError.taskError(_, let underlyingError): throw underlyingError
            case LokiHTTPClient.HTTPError.networkError(_, _, let underlyingError): throw underlyingError ?? error
            default: throw error
            }
        }
    }
}
