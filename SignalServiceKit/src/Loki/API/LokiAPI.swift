import PromiseKit

@objc(LKAPI)
public final class LokiAPI : NSObject {
    /// Only ever modified from the message processing queue (`OWSBatchMessageProcessor.processingQueue`).
    private static var syncMessageTimestamps: [String:Set<UInt64>] = [:]
    
    public static var _lastDeviceLinkUpdate: [String:Date] = [:]
    /// A mapping from hex encoded public key to date updated.
    public static var lastDeviceLinkUpdate: [String:Date] {
        get { stateQueue.sync { _lastDeviceLinkUpdate } }
        set { stateQueue.sync { _lastDeviceLinkUpdate = newValue } }
    }
    
    private static var _userHexEncodedPublicKeyCache: [String:Set<String>] = [:]
    /// A mapping from thread ID to set of user hex encoded public keys.
    @objc public static var userHexEncodedPublicKeyCache: [String:Set<String>] {
        get { stateQueue.sync { _userHexEncodedPublicKeyCache } }
        set { stateQueue.sync { _userHexEncodedPublicKeyCache = newValue } }
    }
    
    private static let stateQueue = DispatchQueue(label: "stateQueue")
    
    /// All service node related errors must be handled on this queue to avoid race conditions maintaining e.g. failure counts.
    public static let errorHandlingQueue = DispatchQueue(label: "errorHandlingQueue")
    
    // MARK: Convenience
    internal static let storage = OWSPrimaryStorage.shared()
    internal static let userHexEncodedPublicKey = getUserHexEncodedPublicKey()
    
    // MARK: Settings
    private static let apiVersion = "v1"
    private static let maxRetryCount: UInt = 8
    private static let defaultTimeout: TimeInterval = 20
    private static let longPollingTimeout: TimeInterval = 40
    private static var userIDScanLimit: UInt = 4096
    internal static var powDifficulty: UInt = 4
    public static let defaultMessageTTL: UInt64 = 24 * 60 * 60 * 1000
    public static let deviceLinkUpdateInterval: TimeInterval = 20
    
    // MARK: Types
    public typealias RawResponse = Any
    
    @objc public class LokiAPIError : NSError { // Not called `Error` for Obj-C interoperablity
        
        @objc public static let proofOfWorkCalculationFailed = LokiAPIError(domain: "LokiAPIErrorDomain", code: 1, userInfo: [ NSLocalizedDescriptionKey : "Failed to calculate proof of work." ])
        @objc public static let messageConversionFailed = LokiAPIError(domain: "LokiAPIErrorDomain", code: 2, userInfo: [ NSLocalizedDescriptionKey : "Failed to construct message." ])
        @objc public static let clockOutOfSync = LokiAPIError(domain: "LokiAPIErrorDomain", code: 3, userInfo: [ NSLocalizedDescriptionKey : "Your clock is out of sync with the service node network." ])
        @objc public static let randomSnodePoolUpdatingFailed = LokiAPIError(domain: "LokiAPIErrorDomain", code: 4, userInfo: [ NSLocalizedDescriptionKey : "Failed to update random service node pool." ])
    }
    
    @objc(LKDestination)
    public final class Destination : NSObject {
        @objc public let hexEncodedPublicKey: String
        @objc(kind)
        public let objc_kind: String
        
        public var kind: Kind {
            return Kind(rawValue: objc_kind)!
        }
        
        public enum Kind : String { case master, slave }
        
        public init(hexEncodedPublicKey: String, kind: Kind) {
            self.hexEncodedPublicKey = hexEncodedPublicKey
            self.objc_kind = kind.rawValue
        }
        
        @objc public init(hexEncodedPublicKey: String, kind: String) {
            self.hexEncodedPublicKey = hexEncodedPublicKey
            self.objc_kind = kind
        }
        
        override public func isEqual(_ other: Any?) -> Bool {
            guard let other = other as? Destination else { return false }
            return hexEncodedPublicKey == other.hexEncodedPublicKey && kind == other.kind
        }
        
        override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
            return hexEncodedPublicKey.hashValue ^ kind.hashValue
        }

        override public var description: String { return "\(kind.rawValue)(\(hexEncodedPublicKey))" }
    }
    
    public typealias MessageListPromise = Promise<[SSKProtoEnvelope]>
    
    public typealias RawResponsePromise = Promise<RawResponse>
    
    // MARK: Lifecycle
    override private init() { }
    
    // MARK: Internal API
    internal static func invoke(_ method: LokiAPITarget.Method, on target: LokiAPITarget, associatedWith hexEncodedPublicKey: String,
        parameters: [String:Any], headers: [String:String]? = nil, timeout: TimeInterval? = nil) -> RawResponsePromise {
        let url = URL(string: "\(target.address):\(target.port)/storage_rpc/\(apiVersion)")!
        let request = TSRequest(url: url, method: "POST", parameters: [ "method" : method.rawValue, "params" : parameters ])
        if let headers = headers { request.allHTTPHeaderFields = headers }
        request.timeoutInterval = timeout ?? defaultTimeout
        let headers = request.allHTTPHeaderFields ?? [:]
        let headersDescription = headers.isEmpty ? "no custom headers specified" : headers.prettifiedDescription
        print("[Loki] Invoking \(method.rawValue) on \(target) with \(parameters.prettifiedDescription) (\(headersDescription)).")
        return LokiSnodeProxy(for: target).perform(request, withCompletionQueue: DispatchQueue.global())
            .handlingSwarmSpecificErrorsIfNeeded(for: target, associatedWith: hexEncodedPublicKey)
            .recoveringNetworkErrorsIfNeeded()
    }
    
    internal static func getRawMessages(from target: LokiAPITarget, usingLongPolling useLongPolling: Bool) -> RawResponsePromise {
        let lastHashValue = getLastMessageHashValue(for: target) ?? ""
        let parameters = [ "pubKey" : userHexEncodedPublicKey, "lastHash" : lastHashValue ]
        let headers: [String:String]? = useLongPolling ? [ "X-Loki-Long-Poll" : "true" ] : nil
        let timeout: TimeInterval? = useLongPolling ? longPollingTimeout : nil
        return invoke(.getMessages, on: target, associatedWith: userHexEncodedPublicKey, parameters: parameters, headers: headers, timeout: timeout)
    }
    
    // MARK: Public API
    public static func getMessages() -> Promise<Set<MessageListPromise>> {
        return getTargetSnodes(for: userHexEncodedPublicKey).mapValues { targetSnode in
            return getRawMessages(from: targetSnode, usingLongPolling: false).map { parseRawMessagesResponse($0, from: targetSnode) }
        }.map { Set($0) }.retryingIfNeeded(maxRetryCount: maxRetryCount)
    }
    
    public static func getDestinations(for hexEncodedPublicKey: String) -> Promise<[Destination]> {
        var result: Promise<[Destination]>!
        storage.dbReadConnection.readWrite { transaction in
            result = getDestinations(for: hexEncodedPublicKey, in: transaction)
        }
        return result
    }
    
    public static func getDestinations(for hexEncodedPublicKey: String, in transaction: YapDatabaseReadWriteTransaction) -> Promise<[Destination]> {
        let (promise, seal) = Promise<[Destination]>.pending()
        func getDestinations(in transaction: YapDatabaseReadTransaction? = nil) {
            func getDestinationsInternal(in transaction: YapDatabaseReadTransaction) {
                var destinations: [Destination] = []
                let masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: hexEncodedPublicKey, in: transaction) ?? hexEncodedPublicKey
                let masterDestination = Destination(hexEncodedPublicKey: masterHexEncodedPublicKey, kind: .master)
                destinations.append(masterDestination)
                let deviceLinks = storage.getDeviceLinks(for: masterHexEncodedPublicKey, in: transaction)
                let slaveDestinations = deviceLinks.map { Destination(hexEncodedPublicKey: $0.slave.hexEncodedPublicKey, kind: .slave) }
                destinations.append(contentsOf: slaveDestinations)
                seal.fulfill(destinations)
            }
            if let transaction = transaction {
                getDestinationsInternal(in: transaction)
            } else {
                storage.dbReadConnection.read { transaction in
                    getDestinationsInternal(in: transaction)
                }
            }
        }
        let timeSinceLastUpdate: TimeInterval
        if let lastDeviceLinkUpdate = lastDeviceLinkUpdate[hexEncodedPublicKey] {
            timeSinceLastUpdate = Date().timeIntervalSince(lastDeviceLinkUpdate)
        } else {
            timeSinceLastUpdate = .infinity
        }
        if timeSinceLastUpdate > deviceLinkUpdateInterval {
            let masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: hexEncodedPublicKey, in: transaction) ?? hexEncodedPublicKey
            LokiFileServerAPI.getDeviceLinks(associatedWith: masterHexEncodedPublicKey, in: transaction).done(on: DispatchQueue.global()) { _ in
                getDestinations()
                lastDeviceLinkUpdate[hexEncodedPublicKey] = Date()
            }.catch(on: DispatchQueue.global()) { error in
                if (error as? LokiDotNetAPI.LokiDotNetAPIError) == LokiDotNetAPI.LokiDotNetAPIError.parsingFailed {
                    // Don't immediately re-fetch in case of failure due to a parsing error
                    lastDeviceLinkUpdate[hexEncodedPublicKey] = Date()
                    getDestinations()
                } else {
                    seal.reject(error)
                }
            }
        } else {
            getDestinations(in: transaction)
        }
        return promise
    }
    
    public static func sendSignalMessage(_ signalMessage: SignalMessage, onP2PSuccess: @escaping () -> Void) -> Promise<Set<RawResponsePromise>> {
        guard let lokiMessage = LokiMessage.from(signalMessage: signalMessage) else { return Promise(error: LokiAPIError.messageConversionFailed) }
        let notificationCenter = NotificationCenter.default
        let destination = lokiMessage.destination
        func sendLokiMessage(_ lokiMessage: LokiMessage, to target: LokiAPITarget) -> RawResponsePromise {
            let parameters = lokiMessage.toJSON()
            return invoke(.sendMessage, on: target, associatedWith: destination, parameters: parameters)
        }
        func sendLokiMessageUsingSwarmAPI() -> Promise<Set<RawResponsePromise>> {
            notificationCenter.post(name: .calculatingPoW, object: NSNumber(value: signalMessage.timestamp))
            return lokiMessage.calculatePoW().then(on: DispatchQueue.global()) { lokiMessageWithPoW -> Promise<Set<RawResponsePromise>> in
                notificationCenter.post(name: .contactingNetwork, object: NSNumber(value: signalMessage.timestamp))
                return getTargetSnodes(for: destination).map { swarm in
                    return Set(swarm.map { target in
                        notificationCenter.post(name: .sendingMessage, object: NSNumber(value: signalMessage.timestamp))
                        return sendLokiMessage(lokiMessageWithPoW, to: target).map { rawResponse in
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
                }.retryingIfNeeded(maxRetryCount: maxRetryCount)
            }
        }
        if let peer = LokiP2PAPI.getInfo(for: destination), (lokiMessage.isPing || peer.isOnline) {
            let target = LokiAPITarget(address: peer.address, port: peer.port, publicKeySet: nil)
            return Promise.value([ target ]).mapValues { sendLokiMessage(lokiMessage, to: $0) }.map { Set($0) }.retryingIfNeeded(maxRetryCount: maxRetryCount).get { _ in
                LokiP2PAPI.markOnline(destination)
                onP2PSuccess()
            }.recover(on: DispatchQueue.global()) { error -> Promise<Set<RawResponsePromise>> in
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
    
    // MARK: Public API (Obj-C)
    @objc(getDestinationsFor:)
    public static func objc_getDestinations(for hexEncodedPublicKey: String) -> AnyPromise {
        let promise = getDestinations(for: hexEncodedPublicKey)
        return AnyPromise.from(promise)
    }
    
    @objc(getDestinationsFor:inTransaction:)
    public static func objc_getDestinations(for hexEncodedPublicKey: String, in transaction: YapDatabaseReadWriteTransaction) -> AnyPromise {
        let promise = getDestinations(for: hexEncodedPublicKey, in: transaction)
        return AnyPromise.from(promise)
    }
    
    @objc(sendSignalMessage:onP2PSuccess:)
    public static func objc_sendSignalMessage(_ signalMessage: SignalMessage, onP2PSuccess: @escaping () -> Void) -> AnyPromise {
        let promise = sendSignalMessage(signalMessage, onP2PSuccess: onP2PSuccess).mapValues { AnyPromise.from($0) }.map { Set($0) }
        return AnyPromise.from(promise)
    }
    
    // MARK: Parsing
    
    // The parsing utilities below use a best attempt approach to parsing; they warn for parsing failures but don't throw exceptions.
    
    internal static func parseRawMessagesResponse(_ rawResponse: Any, from target: LokiAPITarget) -> [SSKProtoEnvelope] {
        guard let json = rawResponse as? JSON, let rawMessages = json["messages"] as? [JSON] else { return [] }
        updateLastMessageHashValueIfPossible(for: target, from: rawMessages)
        let newRawMessages = removeDuplicates(from: rawMessages)
        let newMessages = parseProtoEnvelopes(from: newRawMessages)
        let newMessageCount = newMessages.count
        if newMessageCount == 1 {
            print("[Loki] Retrieved 1 new message.")
        } else if (newMessageCount != 0) {
            print("[Loki] Retrieved \(newMessageCount) new messages.")
        }
        return newMessages
    }
    
    private static func updateLastMessageHashValueIfPossible(for target: LokiAPITarget, from rawMessages: [JSON]) {
        if let lastMessage = rawMessages.last, let hashValue = lastMessage["hash"] as? String, let expirationDate = lastMessage["expiration"] as? Int {
            setLastMessageHashValue(for: target, hashValue: hashValue, expirationDate: UInt64(expirationDate))
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
    
    @objc public static func isDuplicateSyncMessage(_ syncMessage: SSKProtoSyncMessageSent, from hexEncodedPublicKey: String) -> Bool {
        var timestamps: Set<UInt64> = syncMessageTimestamps[hexEncodedPublicKey] ?? []
        let hasTimestamp = syncMessage.timestamp != 0
        guard hasTimestamp else { return false }
        let result = timestamps.contains(syncMessage.timestamp)
        timestamps.insert(syncMessage.timestamp)
        syncMessageTimestamps[hexEncodedPublicKey] = timestamps
        return result
    }

    // MARK: Message Hash Caching
    private static func getLastMessageHashValue(for target: LokiAPITarget) -> String? {
        var result: String? = nil
        // Uses a read/write connection because getting the last message hash value also removes expired messages as needed
        // TODO: This shouldn't be the case; a getter shouldn't have an unexpected side effect
        storage.dbReadWriteConnection.readWrite { transaction in
            result = storage.getLastMessageHash(forServiceNode: target.address, transaction: transaction)
        }
        return result
    }

    private static func setLastMessageHashValue(for target: LokiAPITarget, hashValue: String, expirationDate: UInt64) {
        storage.dbReadWriteConnection.readWrite { transaction in
            storage.setLastMessageHash(forServiceNode: target.address, hash: hashValue, expiresAt: expirationDate, transaction: transaction)
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
        storage.dbReadWriteConnection.readWrite { transaction in
            transaction.setObject(receivedMessageHashValues, forKey: receivedMessageHashValuesKey, inCollection: receivedMessageHashValuesCollection)
        }
    }
    
    // MARK: User ID Caching
    @objc public static func cache(_ hexEncodedPublicKey: String, for threadID: String) {
        if let cache = userHexEncodedPublicKeyCache[threadID] {
            userHexEncodedPublicKeyCache[threadID] = cache.union([ hexEncodedPublicKey ])
        } else {
            userHexEncodedPublicKeyCache[threadID] = [ hexEncodedPublicKey ]
        }
    }
    
    @objc public static func getMentionCandidates(for query: String, in threadID: String) -> [Mention] {
        // Prepare
        guard let cache = userHexEncodedPublicKeyCache[threadID] else { return [] }
        var candidates: [Mention] = []
        // Gather candidates
        var publicChat: LokiPublicChat?
        storage.dbReadConnection.read { transaction in
            publicChat = LokiDatabaseUtilities.getPublicChat(for: threadID, in: transaction)
        }
        storage.dbReadConnection.read { transaction in
            candidates = cache.flatMap { hexEncodedPublicKey in
                let uncheckedDisplayName: String?
                if let publicChat = publicChat {
                    uncheckedDisplayName = UserDisplayNameUtilities.getPublicChatDisplayName(for: hexEncodedPublicKey, in: publicChat.channel, on: publicChat.server)
                } else {
                    uncheckedDisplayName = UserDisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey)
                }
                guard let displayName = uncheckedDisplayName else { return nil }
                guard !displayName.hasPrefix("Anonymous") else { return nil }
                return Mention(hexEncodedPublicKey: hexEncodedPublicKey, displayName: displayName)
            }
        }
        candidates = candidates.filter { $0.hexEncodedPublicKey != userHexEncodedPublicKey }
        // Sort alphabetically first
        candidates.sort { $0.displayName < $1.displayName }
        if query.count >= 2 {
            // Filter out any non-matching candidates
            candidates = candidates.filter { $0.displayName.lowercased().contains(query.lowercased()) }
            // Sort based on where in the candidate the query occurs
            candidates.sort {
                $0.displayName.lowercased().range(of: query.lowercased())!.lowerBound < $1.displayName.lowercased().range(of: query.lowercased())!.lowerBound
            }
        }
        // Return
        return candidates
    }
    
    @objc public static func populateUserHexEncodedPublicKeyCacheIfNeeded(for threadID: String, in transaction: YapDatabaseReadWriteTransaction? = nil) {
        guard userHexEncodedPublicKeyCache[threadID] == nil else { return }
        var result: Set<String> = []
        func populate(in transaction: YapDatabaseReadWriteTransaction) {
            guard let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) else { return }
            let interactions = transaction.ext(TSMessageDatabaseViewExtensionName) as! YapDatabaseViewTransaction
            interactions.enumerateKeysAndObjects(inGroup: threadID) { _, _, object, index, _ in
                guard let message = object as? TSIncomingMessage, index < userIDScanLimit else { return }
                result.insert(message.authorId)
            }
        }
        if let transaction = transaction {
            populate(in: transaction)
        } else {
            storage.dbReadWriteConnection.readWrite { transaction in
                populate(in: transaction)
            }
        }
        result.insert(userHexEncodedPublicKey)
        userHexEncodedPublicKeyCache[threadID] = result
    }
}

// MARK: Error Handling
private extension Promise {

    fileprivate func recoveringNetworkErrorsIfNeeded() -> Promise<T> {
        return recover(on: DispatchQueue.global()) { error -> Promise<T> in
            switch error {
            case NetworkManagerError.taskError(_, let underlyingError): throw underlyingError
            case LokiHTTPClient.HTTPError.networkError(_, _, let underlyingError): throw underlyingError ?? error
            default: throw error
            }
        }
    }
}
