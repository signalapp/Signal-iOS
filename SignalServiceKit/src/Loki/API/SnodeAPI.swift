import PromiseKit

@objc(LKSnodeAPI)
public final class SnodeAPI : NSObject {
    internal static let workQueue = DispatchQueue(label: "SnodeAPI.workQueue", qos: .userInitiated) // It's important that this is a serial queue

    /// - Note: Should only be accessed from `LokiAPI.workQueue` to avoid race conditions.
    internal static var snodeFailureCount: [Snode:UInt] = [:]
    /// - Note: Should only be accessed from `LokiAPI.workQueue` to avoid race conditions.
    internal static var snodePool: Set<Snode> = []
    /// - Note: Should only be accessed from `LokiAPI.workQueue` to avoid race conditions.
    internal static var swarmCache: [String:[Snode]] = [:]

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }
    
    // MARK: Settings
    private static let maxRetryCount: UInt = 4
    private static let minimumSnodePoolCount = 64
    private static let minimumSwarmSnodeCount = 2
    private static let seedNodePool: Set<String> = [ "https://storage.seed1.loki.network", "https://storage.seed3.loki.network", "https://public.loki.foundation" ]
    private static let snodeFailureThreshold = 2
    private static let targetSwarmSnodeCount = 2

    internal static var powDifficulty: UInt = 1
    /// - Note: Changing this on the fly is not recommended.
    internal static var useOnionRequests = true
    
    // MARK: Error
    @objc(LKSnodeAPIError)
    public class SnodeAPIError : NSError { // Not called `Error` for Obj-C interoperablity
        
        @objc public static let proofOfWorkCalculationFailed = SnodeAPIError(domain: "LokiAPIErrorDomain", code: 1, userInfo: [ NSLocalizedDescriptionKey : "Failed to calculate proof of work." ])
        @objc public static let messageConversionFailed = SnodeAPIError(domain: "LokiAPIErrorDomain", code: 2, userInfo: [ NSLocalizedDescriptionKey : "Failed to construct message." ])
        @objc public static let clockOutOfSync = SnodeAPIError(domain: "LokiAPIErrorDomain", code: 3, userInfo: [ NSLocalizedDescriptionKey : "Your clock is out of sync with the service node network." ])
        @objc public static let randomSnodePoolUpdatingFailed = SnodeAPIError(domain: "LokiAPIErrorDomain", code: 4, userInfo: [ NSLocalizedDescriptionKey : "Failed to update random service node pool." ])
        @objc public static let missingSnodeVersion = SnodeAPIError(domain: "LokiAPIErrorDomain", code: 5, userInfo: [ NSLocalizedDescriptionKey : "Missing service node version." ])
    }

    // MARK: Type Aliases
    public typealias MessageListPromise = Promise<[SSKProtoEnvelope]>
    public typealias RawResponse = Any
    public typealias RawResponsePromise = Promise<RawResponse>
    
    // MARK: Lifecycle
    override private init() { }
    
    // MARK: Core
    internal static func invoke(_ method: Snode.Method, on snode: Snode, associatedWith publicKey: String, parameters: JSON) -> RawResponsePromise {
        if useOnionRequests {
            return OnionRequestAPI.sendOnionRequest(to: snode, invoking: method, with: parameters, associatedWith: publicKey).map2 { $0 as Any }
        } else {
            let url = "\(snode.address):\(snode.port)/storage_rpc/v1"
            return HTTP.execute(.post, url, parameters: parameters).map2 { $0 as Any }.recover2 { error -> Promise<Any> in
                guard case HTTP.Error.httpRequestFailed(let statusCode, let json) = error else { throw error }
                throw SnodeAPI.handleError(withStatusCode: statusCode, json: json, forSnode: snode, associatedWith: publicKey) ?? error
            }
        }
    }

    internal static func getRandomSnode() -> Promise<Snode> {
        if snodePool.count < minimumSnodePoolCount {
            storage.dbReadConnection.read { transaction in
                snodePool = storage.getSnodePool(in: transaction)
            }
        }
        if snodePool.count < minimumSnodePoolCount {
            let target = seedNodePool.randomElement()!
            let url = "\(target)/json_rpc"
            let parameters: JSON = [
                "method" : "get_n_service_nodes",
                "params" : [
                    "active_only" : true,
                    "fields" : [
                        "public_ip" : true, "storage_port" : true, "pubkey_ed25519" : true, "pubkey_x25519" : true
                    ]
                ]
            ]
            print("[Loki] Populating snode pool using: \(target).")
            let (promise, seal) = Promise<Snode>.pending()
            attempt(maxRetryCount: 4, recoveringOn: SnodeAPI.workQueue) {
                HTTP.execute(.post, url, parameters: parameters, useSeedNodeURLSession: true).map2 { json -> Snode in
                    guard let intermediate = json["result"] as? JSON, let rawSnodes = intermediate["service_node_states"] as? [JSON] else { throw SnodeAPIError.randomSnodePoolUpdatingFailed }
                    snodePool = try Set(rawSnodes.flatMap { rawSnode in
                        guard let address = rawSnode["public_ip"] as? String, let port = rawSnode["storage_port"] as? Int,
                            let ed25519PublicKey = rawSnode["pubkey_ed25519"] as? String, let x25519PublicKey = rawSnode["pubkey_x25519"] as? String, address != "0.0.0.0" else {
                            print("[Loki] Failed to parse target from: \(rawSnode).")
                            return nil
                        }
                        return Snode(address: "https://\(address)", port: UInt16(port), publicKeySet: Snode.KeySet(ed25519Key: ed25519PublicKey, x25519Key: x25519PublicKey))
                    })
                    // randomElement() uses the system's default random generator, which is cryptographically secure
                    return snodePool.randomElement()!
                }
            }.done2 { snode in
                seal.fulfill(snode)
                try! Storage.writeSync { transaction in
                    print("[Loki] Persisting snode pool to database.")
                    storage.setSnodePool(SnodeAPI.snodePool, in: transaction)
                }
            }.catch2 { error in
                print("[Loki] Failed to contact seed node at: \(target).")
                seal.reject(error)
            }
            return promise
        } else {
            return Promise<Snode> { seal in
                // randomElement() uses the system's default random generator, which is cryptographically secure
                seal.fulfill(snodePool.randomElement()!)
            }
        }
    }

    internal static func getSwarm(for publicKey: String, isForcedReload: Bool = false) -> Promise<[Snode]> {
        if swarmCache[publicKey] == nil {
            storage.dbReadConnection.read { transaction in
                swarmCache[publicKey] = storage.getSwarm(for: publicKey, in: transaction)
            }
        }
        if let cachedSwarm = swarmCache[publicKey], cachedSwarm.count >= minimumSwarmSnodeCount && !isForcedReload {
            return Promise<[Snode]> { $0.fulfill(cachedSwarm) }
        } else {
            print("[Loki] Getting swarm for: \(publicKey == getUserHexEncodedPublicKey() ? "self" : publicKey).")
            let parameters: [String:Any] = [ "pubKey" : publicKey ]
            return getRandomSnode().then2 {
                invoke(.getSwarm, on: $0, associatedWith: publicKey, parameters: parameters)
            }.map2 { rawSnodes in
                let swarm = parseSnodes(from: rawSnodes)
                swarmCache[publicKey] = swarm
                try! Storage.writeSync { transaction in
                    storage.setSwarm(swarm, for: publicKey, in: transaction)
                }
                return swarm
            }
        }
    }

    internal static func getTargetSnodes(for publicKey: String) -> Promise<[Snode]> {
        // shuffled() uses the system's default random generator, which is cryptographically secure
        return getSwarm(for: publicKey).map2 { Array($0.shuffled().prefix(targetSwarmSnodeCount)) }
    }

    internal static func dropSnodeFromSnodePool(_ snode: Snode) {
        SnodeAPI.snodePool.remove(snode)
        try! Storage.writeSync { transaction in
            storage.dropSnodeFromSnodePool(snode, in: transaction)
        }
    }

    @objc public static func clearSnodePool() {
        snodePool.removeAll()
        try! Storage.writeSync { transaction in
            storage.clearSnodePool(in: transaction)
        }
    }

    internal static func dropSnodeFromSwarmIfNeeded(_ snode: Snode, publicKey: String) {
        let swarm = SnodeAPI.swarmCache[publicKey]
        if var swarm = swarm, let index = swarm.firstIndex(of: snode) {
            swarm.remove(at: index)
            SnodeAPI.swarmCache[publicKey] = swarm
            try! Storage.writeSync { transaction in
                storage.setSwarm(swarm, for: publicKey, in: transaction)
            }
        }
    }

    // MARK: Receiving
    internal static func getRawMessages(from snode: Snode, associatedWith publicKey: String) -> RawResponsePromise {
        try! Storage.writeSync { transaction in
            Storage.pruneLastMessageHashInfoIfExpired(for: snode, associatedWith: publicKey, using: transaction)
        }
        let lastHash = Storage.getLastMessageHash(for: snode, associatedWith: publicKey) ?? ""
        let parameters = [ "pubKey" : publicKey, "lastHash" : lastHash ]
        return invoke(.getMessages, on: snode, associatedWith: publicKey, parameters: parameters)
    }

    public static func getMessages(for publicKey: String) -> Promise<Set<MessageListPromise>> {
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: SnodeAPI.workQueue) {
            getTargetSnodes(for: publicKey).mapValues2 { targetSnode in
                getRawMessages(from: targetSnode, associatedWith: publicKey).map2 {
                    parseRawMessagesResponse($0, from: targetSnode, associatedWith: publicKey)
                }
            }.map2 { Set($0) }
        }
    }

    // MARK: Sending
    @objc(sendSignalMessage:)
    public static func objc_sendSignalMessage(_ signalMessage: SignalMessage) -> AnyPromise {
        let promise = sendSignalMessage(signalMessage).mapValues2 { AnyPromise.from($0) }.map2 { Set($0) }
        return AnyPromise.from(promise)
    }

    public static func sendSignalMessage(_ signalMessage: SignalMessage) -> Promise<Set<RawResponsePromise>> {
        // Convert the message to a Loki message
        guard let lokiMessage = LokiMessage.from(signalMessage: signalMessage) else { return Promise(error: SnodeAPIError.messageConversionFailed) }
        let publicKey = lokiMessage.recipientPublicKey
        let notificationCenter = NotificationCenter.default
        notificationCenter.post(name: .calculatingPoW, object: NSNumber(value: signalMessage.timestamp))
        // Calculate proof of work
        return lokiMessage.calculatePoW().then2 { lokiMessageWithPoW -> Promise<Set<RawResponsePromise>> in
            notificationCenter.post(name: .routing, object: NSNumber(value: signalMessage.timestamp))
            // Get the target snodes
            return getTargetSnodes(for: publicKey).map2 { snodes in
                notificationCenter.post(name: .messageSending, object: NSNumber(value: signalMessage.timestamp))
                let parameters = lokiMessageWithPoW.toJSON()
                return Set(snodes.map { snode in
                    // Send the message to the target snode
                    return attempt(maxRetryCount: maxRetryCount, recoveringOn: SnodeAPI.workQueue) {
                        invoke(.sendMessage, on: snode, associatedWith: publicKey, parameters: parameters)
                    }.map2 { rawResponse in
                        if let json = rawResponse as? JSON, let powDifficulty = json["difficulty"] as? Int {
                            guard powDifficulty != SnodeAPI.powDifficulty, powDifficulty < 100 else { return rawResponse }
                            print("[Loki] Setting proof of work difficulty to \(powDifficulty).")
                            SnodeAPI.powDifficulty = UInt(powDifficulty)
                        } else {
                            print("[Loki] Failed to update proof of work difficulty from: \(rawResponse).")
                        }
                        return rawResponse
                    }
                })
            }
        }
    }
    
    // MARK: Parsing
    
    // The parsing utilities below use a best attempt approach to parsing; they warn for parsing failures but don't throw exceptions.

    private static func parseSnodes(from rawResponse: Any) -> [Snode] {
        guard let json = rawResponse as? JSON, let rawSnodes = json["snodes"] as? [JSON] else {
            print("[Loki] Failed to parse targets from: \(rawResponse).")
            return []
        }
        return rawSnodes.flatMap { rawSnode in
            guard let address = rawSnode["ip"] as? String, let portAsString = rawSnode["port"] as? String, let port = UInt16(portAsString), let ed25519PublicKey = rawSnode["pubkey_ed25519"] as? String, let x25519PublicKey = rawSnode["pubkey_x25519"] as? String, address != "0.0.0.0" else {
                print("[Loki] Failed to parse target from: \(rawSnode).")
                return nil
            }
            return Snode(address: "https://\(address)", port: port, publicKeySet: Snode.KeySet(ed25519Key: ed25519PublicKey, x25519Key: x25519PublicKey))
        }
    }

    internal static func parseRawMessagesResponse(_ rawResponse: Any, from snode: Snode, associatedWith publicKey: String) -> [SSKProtoEnvelope] {
        guard let json = rawResponse as? JSON, let rawMessages = json["messages"] as? [JSON] else { return [] }
        updateLastMessageHashValueIfPossible(for: snode, associatedWith: publicKey, from: rawMessages)
        let rawNewMessages = removeDuplicates(from: rawMessages, associatedWith: publicKey)
        let newMessages = parseProtoEnvelopes(from: rawNewMessages)
        return newMessages
    }
    
    private static func updateLastMessageHashValueIfPossible(for snode: Snode, associatedWith publicKey: String, from rawMessages: [JSON]) {
        if let lastMessage = rawMessages.last, let lastHash = lastMessage["hash"] as? String, let expirationDate = lastMessage["expiration"] as? UInt64 {
            try! Storage.writeSync { transaction in
                Storage.setLastMessageHashInfo(for: snode, associatedWith: publicKey, to: [ "hash" : lastHash, "expirationDate" : NSNumber(value: expirationDate) ], using: transaction)
            }
        } else if (!rawMessages.isEmpty) {
            print("[Loki] Failed to update last message hash value from: \(rawMessages).")
        }
    }
    
    private static func removeDuplicates(from rawMessages: [JSON], associatedWith publicKey: String) -> [JSON] {
        var receivedMessages = Storage.getReceivedMessages(for: publicKey) ?? []
        return rawMessages.filter { rawMessage in
            guard let hash = rawMessage["hash"] as? String else {
                print("[Loki] Missing hash value for message: \(rawMessage).")
                return false
            }
            let isDuplicate = receivedMessages.contains(hash)
            receivedMessages.insert(hash)
            try! Storage.writeSync { transaction in
                Storage.setReceivedMessages(to: receivedMessages, for: publicKey, using: transaction)
            }
            return !isDuplicate
        }
    }
    
    private static func parseProtoEnvelopes(from rawMessages: [JSON]) -> [SSKProtoEnvelope] {
        return rawMessages.compactMap { rawMessage in
            guard let base64EncodedData = rawMessage["data"] as? String, let data = Data(base64Encoded: base64EncodedData) else {
                print("[Loki] Failed to decode data for message: \(rawMessage).")
                return nil
            }
            guard let envelope = try? MessageWrapper.unwrap(data: data) else {
                print("[Loki] Failed to unwrap data for message: \(rawMessage).")
                return nil
            }
            return envelope
        }
    }

    // MARK: Error Handling
    /// - Note: Should only be invoked from `LokiAPI.workQueue` to avoid race conditions.
    internal static func handleError(withStatusCode statusCode: UInt, json: JSON?, forSnode snode: Snode, associatedWith publicKey: String? = nil) -> Error? {
        #if DEBUG
        assertOnQueue(SnodeAPI.workQueue)
        #endif
        func handleBadSnode() {
            let oldFailureCount = SnodeAPI.snodeFailureCount[snode] ?? 0
            let newFailureCount = oldFailureCount + 1
            SnodeAPI.snodeFailureCount[snode] = newFailureCount
            print("[Loki] Couldn't reach snode at: \(snode); setting failure count to \(newFailureCount).")
            if newFailureCount >= SnodeAPI.snodeFailureThreshold {
                print("[Loki] Failure threshold reached for: \(snode); dropping it.")
                if let publicKey = publicKey {
                    SnodeAPI.dropSnodeFromSwarmIfNeeded(snode, publicKey: publicKey)
                }
                SnodeAPI.dropSnodeFromSnodePool(snode)
                print("[Loki] Snode pool count: \(snodePool.count).")
                SnodeAPI.snodeFailureCount[snode] = 0
            }
        }
        switch statusCode {
        case 0, 400, 500, 503:
            // The snode is unreachable
            handleBadSnode()
        case 406:
            print("[Loki] The user's clock is out of sync with the service node network.")
            return SnodeAPI.SnodeAPIError.clockOutOfSync
        case 421:
            // The snode isn't associated with the given public key anymore
            if let publicKey = publicKey {
                print("[Loki] Invalidating swarm for: \(publicKey).")
                SnodeAPI.dropSnodeFromSwarmIfNeeded(snode, publicKey: publicKey)
            } else {
                print("[Loki] Got a 421 without an associated public key.")
            }
        case 432:
            // The proof of work difficulty is too low
            if let powDifficulty = json?["difficulty"] as? UInt {
                if powDifficulty < 100 {
                    print("[Loki] Setting proof of work difficulty to \(powDifficulty).")
                    SnodeAPI.powDifficulty = UInt(powDifficulty)
                } else {
                    handleBadSnode()
                }
            } else {
                print("[Loki] Failed to update proof of work difficulty.")
            }
        default:
            handleBadSnode()
            print("[Loki] Unhandled response code: \(statusCode).")
        }
        return nil
    }
}
