import PromiseKit
import SessionUtilitiesKit

@objc(SNSnodeAPI)
public final class SnodeAPI : NSObject {

    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    internal static var snodeFailureCount: [Snode:UInt] = [:]
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    internal static var snodePool: Set<Snode> = []

    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    public static var swarmCache: [String:Set<Snode>] = [:]
    public static var workQueue: DispatchQueue { Threading.workQueue } // Just to make things fit with legacy code

    // MARK: Settings
    private static let maxRetryCount: UInt = 8
    private static let minimumSnodePoolCount = 64
    private static let minimumSwarmSnodeCount = 2
    private static let seedNodePool: Set<String> = [ "https://storage.seed1.loki.network", "https://storage.seed3.loki.network", "https://public.loki.foundation" ]
    private static let snodeFailureThreshold = 3
    private static let targetSwarmSnodeCount = 2

    /// - Note: Changing this on the fly is not recommended.
    internal static var useOnionRequests = true

    public static var powDifficulty: UInt = 1
    
    // MARK: Error
    public enum Error : LocalizedError {
        case generic
        case clockOutOfSync
        case randomSnodePoolUpdatingFailed

        public var errorDescription: String? {
            switch self {
            case .generic: return "An error occurred."
            case .clockOutOfSync: return "Your clock is out of sync with the service node network."
            case .randomSnodePoolUpdatingFailed: return "Failed to update random service node pool."
            }
        }
    }

    // MARK: Type Aliases
    public typealias MessageListPromise = Promise<[JSON]>
    public typealias RawResponse = Any
    public typealias RawResponsePromise = Promise<RawResponse>
    
    // MARK: Internal API
    public static func invoke(_ method: Snode.Method, on snode: Snode, associatedWith publicKey: String, parameters: JSON) -> RawResponsePromise {
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
            snodePool = SNSnodeKitConfiguration.shared.storage.getSnodePool()
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
            SNLog("Populating snode pool using: \(target).")
            let (promise, seal) = Promise<Snode>.pending()
            Threading.workQueue.async {
                attempt(maxRetryCount: 4, recoveringOn: Threading.workQueue) {
                    HTTP.execute(.post, url, parameters: parameters, useSSLURLSession: true).map2 { json -> Snode in
                        guard let intermediate = json["result"] as? JSON, let rawSnodes = intermediate["service_node_states"] as? [JSON] else { throw Error.randomSnodePoolUpdatingFailed }
                        snodePool = Set(rawSnodes.compactMap { rawSnode in
                            guard let address = rawSnode["public_ip"] as? String, let port = rawSnode["storage_port"] as? Int,
                                let ed25519PublicKey = rawSnode["pubkey_ed25519"] as? String, let x25519PublicKey = rawSnode["pubkey_x25519"] as? String, address != "0.0.0.0" else {
                                SNLog("Failed to parse target from: \(rawSnode).")
                                return nil
                            }
                            return Snode(address: "https://\(address)", port: UInt16(port), publicKeySet: Snode.KeySet(ed25519Key: ed25519PublicKey, x25519Key: x25519PublicKey))
                        })
                        // randomElement() uses the system's default random generator, which is cryptographically secure
                        if !snodePool.isEmpty {
                            return snodePool.randomElement()!
                        } else {
                            throw Error.randomSnodePoolUpdatingFailed
                        }
                    }
                }.done2 { snode in
                    seal.fulfill(snode)
                    SNSnodeKitConfiguration.shared.storage.with { transaction in
                        SNLog("Persisting snode pool to database.")
                        SNSnodeKitConfiguration.shared.storage.setSnodePool(to: SnodeAPI.snodePool, using: transaction)
                    }
                }.catch2 { error in
                    SNLog("Failed to contact seed node at: \(target).")
                    seal.reject(error)
                }
            }
            return promise
        } else {
            return Promise<Snode> { seal in
                // randomElement() uses the system's default random generator, which is cryptographically secure
                seal.fulfill(snodePool.randomElement()!)
            }
        }
    }

    internal static func dropSnodeFromSnodePool(_ snode: Snode) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        var snodePool = SnodeAPI.snodePool
        snodePool.remove(snode)
        SnodeAPI.snodePool = snodePool
        SNSnodeKitConfiguration.shared.storage.with { transaction in
            SNSnodeKitConfiguration.shared.storage.setSnodePool(to: snodePool, using: transaction)
        }
    }

    // MARK: Public API
    @objc public static func clearSnodePool() {
        snodePool.removeAll()
        SNSnodeKitConfiguration.shared.storage.with { transaction in
            SNSnodeKitConfiguration.shared.storage.setSnodePool(to: [], using: transaction)
        }
    }
    
    public static func dropSnodeFromSwarmIfNeeded(_ snode: Snode, publicKey: String) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        let swarm = SnodeAPI.swarmCache[publicKey]
        if var swarm = swarm, let index = swarm.firstIndex(of: snode) {
            swarm.remove(at: index)
            SnodeAPI.swarmCache[publicKey] = swarm
            SNSnodeKitConfiguration.shared.storage.with { transaction in
                SNSnodeKitConfiguration.shared.storage.setSwarm(to: swarm, for: publicKey, using: transaction)
            }
        }
    }

    public static func getTargetSnodes(for publicKey: String) -> Promise<[Snode]> {
        // shuffled() uses the system's default random generator, which is cryptographically secure
        return getSwarm(for: publicKey).map2 { Array($0.shuffled().prefix(targetSwarmSnodeCount)) }
    }

    public static func getSwarm(for publicKey: String, isForcedReload: Bool = false) -> Promise<Set<Snode>> {
        if swarmCache[publicKey] == nil {
            swarmCache[publicKey] = SNSnodeKitConfiguration.shared.storage.getSwarm(for: publicKey)
        }
        if let cachedSwarm = swarmCache[publicKey], cachedSwarm.count >= minimumSwarmSnodeCount && !isForcedReload {
            return Promise<Set<Snode>> { $0.fulfill(cachedSwarm) }
        } else {
            SNLog("Getting swarm for: \((publicKey == SNSnodeKitConfiguration.shared.storage.getUserPublicKey()) ? "self" : publicKey).")
            let parameters: [String:Any] = [ "pubKey" : publicKey ]
            return getRandomSnode().then2 { snode in
                attempt(maxRetryCount: 4, recoveringOn: Threading.workQueue) {
                    invoke(.getSwarm, on: snode, associatedWith: publicKey, parameters: parameters)
                }
            }.map2 { rawSnodes in
                let swarm = parseSnodes(from: rawSnodes)
                swarmCache[publicKey] = swarm
                SNSnodeKitConfiguration.shared.storage.with { transaction in
                    SNSnodeKitConfiguration.shared.storage.setSwarm(to: swarm, for: publicKey, using: transaction)
                }
                return swarm
            }
        }
    }

    public static func getRawMessages(from snode: Snode, associatedWith publicKey: String) -> RawResponsePromise {
        let storage = SNSnodeKitConfiguration.shared.storage
        storage.with { transaction in
            storage.pruneLastMessageHashInfoIfExpired(for: snode, associatedWith: publicKey, using: transaction)
        }
        let lastHash = storage.getLastMessageHash(for: snode, associatedWith: publicKey) ?? ""
        let parameters = [ "pubKey" : publicKey, "lastHash" : lastHash ]
        return invoke(.getMessages, on: snode, associatedWith: publicKey, parameters: parameters)
    }

    public static func getMessages(for publicKey: String) -> Promise<Set<MessageListPromise>> {
        let (promise, seal) = Promise<Set<MessageListPromise>>.pending()
        let storage = SNSnodeKitConfiguration.shared.storage
        Threading.workQueue.async {
            attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                getTargetSnodes(for: publicKey).mapValues2 { targetSnode in
                    storage.with { transaction in
                        storage.pruneLastMessageHashInfoIfExpired(for: targetSnode, associatedWith: publicKey, using: transaction)
                    }
                    let lastHash = storage.getLastMessageHash(for: targetSnode, associatedWith: publicKey) ?? ""
                    let parameters = [ "pubKey" : publicKey, "lastHash" : lastHash ]
                    return invoke(.getMessages, on: targetSnode, associatedWith: publicKey, parameters: parameters).map2 { rawResponse in
                        parseRawMessagesResponse(rawResponse, from: targetSnode, associatedWith: publicKey)
                    }
                }.map2 { Set($0) }
            }.done2 { seal.fulfill($0) }.catch2 { seal.reject($0) }
        }
        return promise
    }

    public static func sendMessage(_ message: SnodeMessage) -> Promise<Set<RawResponsePromise>> {
        let (promise, seal) = Promise<Set<RawResponsePromise>>.pending()
        let publicKey = message.recipient
        Threading.workQueue.async {
            getTargetSnodes(for: publicKey).map2 { targetSnodes in
                let parameters = message.toJSON()
                return Set(targetSnodes.map { targetSnode in
                    let result = attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                        invoke(.sendMessage, on: targetSnode, associatedWith: publicKey, parameters: parameters)
                    }
                    result.done2 { rawResponse in
                        if let json = rawResponse as? JSON, let powDifficulty = json["difficulty"] as? Int {
                            guard powDifficulty != SnodeAPI.powDifficulty, powDifficulty < 100 else { return }
                            SNLog("Setting proof of work difficulty to \(powDifficulty).")
                            SnodeAPI.powDifficulty = UInt(powDifficulty)
                        } else {
                            SNLog("Failed to update proof of work difficulty from: \(rawResponse).")
                        }
                    }
                    return result
                })
            }.done2 { seal.fulfill($0) }.catch2 { seal.reject($0) }
        }
        return promise
    }
    
    // MARK: Parsing
    
    // The parsing utilities below use a best attempt approach to parsing; they warn for parsing failures but don't throw exceptions.

    private static func parseSnodes(from rawResponse: Any) -> Set<Snode> {
        guard let json = rawResponse as? JSON, let rawSnodes = json["snodes"] as? [JSON] else {
            SNLog("Failed to parse targets from: \(rawResponse).")
            return []
        }
        return Set(rawSnodes.compactMap { rawSnode in
            guard let address = rawSnode["ip"] as? String, let portAsString = rawSnode["port"] as? String, let port = UInt16(portAsString), let ed25519PublicKey = rawSnode["pubkey_ed25519"] as? String, let x25519PublicKey = rawSnode["pubkey_x25519"] as? String, address != "0.0.0.0" else {
                SNLog("Failed to parse target from: \(rawSnode).")
                return nil
            }
            return Snode(address: "https://\(address)", port: port, publicKeySet: Snode.KeySet(ed25519Key: ed25519PublicKey, x25519Key: x25519PublicKey))
        })
    }

    public static func parseRawMessagesResponse(_ rawResponse: Any, from snode: Snode, associatedWith publicKey: String) -> [JSON] {
        guard let json = rawResponse as? JSON, let rawMessages = json["messages"] as? [JSON] else { return [] }
        updateLastMessageHashValueIfPossible(for: snode, associatedWith: publicKey, from: rawMessages)
        return removeDuplicates(from: rawMessages, associatedWith: publicKey)
    }
    
    private static func updateLastMessageHashValueIfPossible(for snode: Snode, associatedWith publicKey: String, from rawMessages: [JSON]) {
        if let lastMessage = rawMessages.last, let lastHash = lastMessage["hash"] as? String, let expirationDate = lastMessage["expiration"] as? UInt64 {
            SNSnodeKitConfiguration.shared.storage.with { transaction in
                SNSnodeKitConfiguration.shared.storage.setLastMessageHashInfo(for: snode, associatedWith: publicKey,
                    to: [ "hash" : lastHash, "expirationDate" : NSNumber(value: expirationDate) ], using: transaction)
            }
        } else if (!rawMessages.isEmpty) {
            SNLog("Failed to update last message hash value from: \(rawMessages).")
        }
    }
    
    private static func removeDuplicates(from rawMessages: [JSON], associatedWith publicKey: String) -> [JSON] {
        var receivedMessages = SNSnodeKitConfiguration.shared.storage.getReceivedMessages(for: publicKey)
        return rawMessages.filter { rawMessage in
            guard let hash = rawMessage["hash"] as? String else {
                SNLog("Missing hash value for message: \(rawMessage).")
                return false
            }
            let isDuplicate = receivedMessages.contains(hash)
            receivedMessages.insert(hash)
            SNSnodeKitConfiguration.shared.storage.with { transaction in
                SNSnodeKitConfiguration.shared.storage.setReceivedMessages(to: receivedMessages, for: publicKey, using: transaction)
            }
            return !isDuplicate
        }
    }

    // MARK: Error Handling
    /// - Note: Should only be invoked from `Threading.workQueue` to avoid race conditions.
    @discardableResult
    internal static func handleError(withStatusCode statusCode: UInt, json: JSON?, forSnode snode: Snode, associatedWith publicKey: String? = nil) -> Error? {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        func handleBadSnode() {
            let oldFailureCount = SnodeAPI.snodeFailureCount[snode] ?? 0
            let newFailureCount = oldFailureCount + 1
            SnodeAPI.snodeFailureCount[snode] = newFailureCount
            SNLog("Couldn't reach snode at: \(snode); setting failure count to \(newFailureCount).")
            if newFailureCount >= SnodeAPI.snodeFailureThreshold {
                SNLog("Failure threshold reached for: \(snode); dropping it.")
                if let publicKey = publicKey {
                    SnodeAPI.dropSnodeFromSwarmIfNeeded(snode, publicKey: publicKey)
                }
                SnodeAPI.dropSnodeFromSnodePool(snode)
                SNLog("Snode pool count: \(snodePool.count).")
                SnodeAPI.snodeFailureCount[snode] = 0
            }
        }
        switch statusCode {
        case 0, 400, 500, 503:
            // The snode is unreachable
            handleBadSnode()
        case 406:
            SNLog("The user's clock is out of sync with the service node network.")
            return Error.clockOutOfSync
        case 421:
            // The snode isn't associated with the given public key anymore
            if let publicKey = publicKey {
                SNLog("Invalidating swarm for: \(publicKey).")
                SnodeAPI.dropSnodeFromSwarmIfNeeded(snode, publicKey: publicKey)
            } else {
                SNLog("Got a 421 without an associated public key.")
            }
        case 432:
            // The proof of work difficulty is too low
            if let powDifficulty = json?["difficulty"] as? UInt {
                if powDifficulty < 100 {
                    SNLog("Setting proof of work difficulty to \(powDifficulty).")
                    SnodeAPI.powDifficulty = UInt(powDifficulty)
                } else {
                    handleBadSnode()
                }
            } else {
                SNLog("Failed to update proof of work difficulty.")
            }
        default:
            handleBadSnode()
            SNLog("Unhandled response code: \(statusCode).")
        }
        return nil
    }
}
