import PromiseKit

public extension LokiAPI {
    private static var snodeVersion: [LokiAPITarget:String] = [:]

    /// Only ever accessed from `LokiAPI.errorHandlingQueue` to avoid race conditions.
    fileprivate static var failureCount: [LokiAPITarget:UInt] = [:]

    // MARK: Settings
    private static let minimumSnodeCount = 2
    private static let targetSnodeCount = 3
    fileprivate static let failureThreshold = 2
    
    // MARK: Caching
    internal static var swarmCache: [String:[LokiAPITarget]] = [:]
    
    internal static func dropIfNeeded(_ target: LokiAPITarget, hexEncodedPublicKey: String) {
        let swarm = LokiAPI.swarmCache[hexEncodedPublicKey]
        if var swarm = swarm, let index = swarm.firstIndex(of: target) {
            swarm.remove(at: index)
            LokiAPI.swarmCache[hexEncodedPublicKey] = swarm
        }
    }
    
    // MARK: Clearnet Setup
    fileprivate static let seedNodePool: Set<String> = [ "http://storage.seed1.loki.network:22023", "http://storage.seed2.loki.network:38157", "http://149.56.148.124:38157" ]
    fileprivate static var randomSnodePool: Set<LokiAPITarget> = []

    @objc public static func clearRandomSnodePool() {
        randomSnodePool.removeAll()
    }
    
    // MARK: Internal API
    internal static func getRandomSnode() -> Promise<LokiAPITarget> {
        // All of this has to happen on DispatchQueue.global() due to the way OWSMessageManager works
        if randomSnodePool.isEmpty {
            let target = seedNodePool.randomElement()!
            let url = URL(string: "\(target)/json_rpc")!
            let request = TSRequest(url: url, method: "POST", parameters: [
                "method" : "get_service_nodes",
                "params" : [
                    "active_only" : true,
                    "fields" : [
                        "public_ip" : true,
                        "storage_port" : true,
                        "pubkey_ed25519": true,
                        "pubkey_x25519": true
                    ]
                ]
            ])
            print("[Loki] Invoking get_n_service_nodes on \(target).")
            return TSNetworkManager.shared().perform(request, withCompletionQueue: DispatchQueue.global()).map(on: DispatchQueue.global()) { intermediate in
                let rawResponse = intermediate.responseObject
                guard let json = rawResponse as? JSON, let intermediate = json["result"] as? JSON, let rawTargets = intermediate["service_node_states"] as? [JSON] else { throw LokiAPIError.randomSnodePoolUpdatingFailed }
                randomSnodePool = try Set(rawTargets.flatMap { rawTarget in
                    guard let address = rawTarget["public_ip"] as? String, let port = rawTarget["storage_port"] as? Int, let idKey = rawTarget["pubkey_ed25519"] as? String, let encryptionKey = rawTarget["pubkey_x25519"] as? String, address != "0.0.0.0" else {
                        print("[Loki] Failed to parse target from: \(rawTarget).")
                        return nil
                    }
                    return LokiAPITarget(address: "https://\(address)", port: UInt16(port), publicKeySet: LokiAPITarget.KeySet(idKey: idKey, encryptionKey: encryptionKey))
                })
                // randomElement() uses the system's default random generator, which is cryptographically secure
                return randomSnodePool.randomElement()!
            }.recover(on: DispatchQueue.global()) { error -> Promise<LokiAPITarget> in
                print("[Loki] Failed to contact seed node at: \(target).")
                throw error
            }.retryingIfNeeded(maxRetryCount: 16) // The seed nodes have historically been unreliable
        } else {
            return Promise<LokiAPITarget> { seal in
                // randomElement() uses the system's default random generator, which is cryptographically secure
                seal.fulfill(randomSnodePool.randomElement()!)
            }
        }
    }
    
    internal static func getSwarm(for hexEncodedPublicKey: String) -> Promise<[LokiAPITarget]> {
        if let cachedSwarm = swarmCache[hexEncodedPublicKey], cachedSwarm.count >= minimumSnodeCount {
            return Promise<[LokiAPITarget]> { $0.fulfill(cachedSwarm) }
        } else {
            let parameters: [String:Any] = [ "pubKey" : hexEncodedPublicKey ]
            // All of this has to happen on DispatchQueue.global() due to the way OWSMessageManager works
            return getRandomSnode().then(on: DispatchQueue.global()) { invoke(.getSwarm, on: $0, associatedWith: hexEncodedPublicKey, parameters: parameters) }.map { parseTargets(from: $0) }.get { swarmCache[hexEncodedPublicKey] = $0 }
        }
    }

    internal static func getTargetSnodes(for hexEncodedPublicKey: String) -> Promise<[LokiAPITarget]> {
        // shuffled() uses the system's default random generator, which is cryptographically secure
        return getSwarm(for: hexEncodedPublicKey).map { Array($0.shuffled().prefix(targetSnodeCount)) }
    }

    internal static func getFileServerProxy() -> Promise<LokiAPITarget> {
        // All of this has to happen on DispatchQueue.global() due to the way OWSMessageManager works
        let (promise, seal) = Promise<LokiAPITarget>.pending()
        func getVersion(for snode: LokiAPITarget) -> Promise<String> {
            let url = URL(string: "\(snode.address):\(snode.port)/get_stats/v1")!
            let request = TSRequest(url: url)
            if let version = snodeVersion[snode] {
                return Promise { $0.fulfill(version) }
            } else {
                return TSNetworkManager.shared().perform(request, withCompletionQueue: DispatchQueue.global()).map(on: DispatchQueue.global()) { intermediate in
                    let rawResponse = intermediate.responseObject
                    guard let json = rawResponse as? JSON, let version = json["version"] as? String else { throw LokiAPIError.missingSnodeVersion }
                    snodeVersion[snode] = version
                    return version
                }
            }
        }
        getRandomSnode().done(on: DispatchQueue.global()) { snode in
            getVersion(for: snode).then(on: DispatchQueue.global()) { version -> Promise<LokiAPITarget> in
                if version >= "2.0.2" {
                    print("[Loki] Using file server proxy with version number \(version).")
                    return Promise { $0.fulfill(snode) }
                } else {
                    print("[Loki] Rejecting file server proxy with version number \(version).")
                    return getFileServerProxy()
                }
            }.recover(on: DispatchQueue.global()) { error in
                return getFileServerProxy()
            }
        }.catch(on: DispatchQueue.global()) { error in
            seal.reject(error)
        }
        return promise
    }
    
    // MARK: Parsing
    private static func parseTargets(from rawResponse: Any) -> [LokiAPITarget] {
        guard let json = rawResponse as? JSON, let rawTargets = json["snodes"] as? [JSON] else {
            print("[Loki] Failed to parse targets from: \(rawResponse).")
            return []
        }
        return rawTargets.flatMap { rawTarget in
            guard let address = rawTarget["ip"] as? String, let portAsString = rawTarget["port"] as? String, let port = UInt16(portAsString), let idKey = rawTarget["pubkey_ed25519"] as? String, let encryptionKey = rawTarget["pubkey_x25519"] as? String, address != "0.0.0.0" else {
                print("[Loki] Failed to parse target from: \(rawTarget).")
                return nil
            }
            return LokiAPITarget(address: "https://\(address)", port: port, publicKeySet: LokiAPITarget.KeySet(idKey: idKey, encryptionKey: encryptionKey))
        }
    }
}

// MARK: Error Handling
internal extension Promise {
    
    internal func handlingSwarmSpecificErrorsIfNeeded(for target: LokiAPITarget, associatedWith hexEncodedPublicKey: String) -> Promise<T> {
        return recover(on: LokiAPI.errorHandlingQueue) { error -> Promise<T> in
            if let error = error as? LokiHTTPClient.HTTPError {
                switch error.statusCode {
                case 0, 400, 500, 503:
                    // The snode is unreachable
                    let oldFailureCount = LokiAPI.failureCount[target] ?? 0
                    let newFailureCount = oldFailureCount + 1
                    LokiAPI.failureCount[target] = newFailureCount
                    print("[Loki] Couldn't reach snode at: \(target); setting failure count to \(newFailureCount).")
                    if newFailureCount >= LokiAPI.failureThreshold {
                        print("[Loki] Failure threshold reached for: \(target); dropping it.")
                        LokiAPI.dropIfNeeded(target, hexEncodedPublicKey: hexEncodedPublicKey) // Remove it from the swarm cache associated with the given public key
                        LokiAPI.randomSnodePool.remove(target) // Remove it from the random snode pool
                        LokiAPI.failureCount[target] = 0
                    }
                case 406:
                    print("[Loki] The user's clock is out of sync with the service node network.")
                    throw LokiAPI.LokiAPIError.clockOutOfSync
                case 421:
                    // The snode isn't associated with the given public key anymore
                    print("[Loki] Invalidating swarm for: \(hexEncodedPublicKey).")
                    LokiAPI.dropIfNeeded(target, hexEncodedPublicKey: hexEncodedPublicKey)
                case 432:
                    // The PoW difficulty is too low
                    if case LokiHTTPClient.HTTPError.networkError(_, let result, _) = error, let json = result as? JSON, let powDifficulty = json["difficulty"] as? Int {
                        print("[Loki] Setting proof of work difficulty to \(powDifficulty).")
                        LokiAPI.powDifficulty = UInt(powDifficulty)
                    } else {
                        print("[Loki] Failed to update proof of work difficulty.")
                    }
                    break
                default: break
                }
            }
            throw error
        }
    }
}
