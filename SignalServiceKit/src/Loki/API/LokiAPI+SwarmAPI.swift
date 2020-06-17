import PromiseKit

public extension LokiAPI {

    fileprivate static let seedNodePool: Set<String> = [ "https://storage.seed1.loki.network", "https://storage.seed3.loki.network", "https://public.loki.foundation" ]

    /// - Note: Should only be accessed from `LokiAPI.workQueue` to avoid race conditions.
    internal static var snodeFailureCount: [LokiAPITarget:UInt] = [:]
    // TODO: Read/write this directly from/to the database
    /// - Note: Should only be accessed from `LokiAPI.workQueue` to avoid race conditions.
    internal static var snodePool: Set<LokiAPITarget> = []
    // TODO: Read/write this directly from/to the database
    /// - Note: Should only be accessed from `LokiAPI.workQueue` to avoid race conditions.
    internal static var swarmCache: [String:[LokiAPITarget]] = [:]

    // MARK: Settings
    private static let minimumSnodePoolCount = 32
    private static let minimumSwarmSnodeCount = 2
    private static let targetSwarmSnodeCount = 2
    
    internal static let snodeFailureThreshold = 2
    
    // MARK: Internal API
    internal static func getRandomSnode() -> Promise<LokiAPITarget> {
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
            let (promise, seal) = Promise<LokiAPITarget>.pending()
            attempt(maxRetryCount: 4, recoveringOn: LokiAPI.workQueue) {
                HTTP.execute(.post, url, parameters: parameters).map2 { json -> LokiAPITarget in
                    guard let intermediate = json["result"] as? JSON, let rawTargets = intermediate["service_node_states"] as? [JSON] else { throw LokiAPIError.randomSnodePoolUpdatingFailed }
                    snodePool = try Set(rawTargets.flatMap { rawTarget in
                        guard let address = rawTarget["public_ip"] as? String, let port = rawTarget["storage_port"] as? Int, let ed25519PublicKey = rawTarget["pubkey_ed25519"] as? String, let x25519PublicKey = rawTarget["pubkey_x25519"] as? String, address != "0.0.0.0" else {
                            print("[Loki] Failed to parse target from: \(rawTarget).")
                            return nil
                        }
                        return LokiAPITarget(address: "https://\(address)", port: UInt16(port), publicKeySet: LokiAPITarget.KeySet(ed25519Key: ed25519PublicKey, x25519Key: x25519PublicKey))
                    })
                    // randomElement() uses the system's default random generator, which is cryptographically secure
                    return snodePool.randomElement()!
                }
            }.done2 { snode in
                seal.fulfill(snode)
                try! Storage.writeSync { transaction in
                    print("[Loki] Persisting snode pool to database.")
                    storage.setSnodePool(LokiAPI.snodePool, in: transaction)
                }
            }.catch2 { error in
                print("[Loki] Failed to contact seed node at: \(target).")
                seal.reject(error)
            }
            return promise
        } else {
            return Promise<LokiAPITarget> { seal in
                // randomElement() uses the system's default random generator, which is cryptographically secure
                seal.fulfill(snodePool.randomElement()!)
            }
        }
    }
    
    internal static func getSwarm(for hexEncodedPublicKey: String, isForcedReload: Bool = false) -> Promise<[LokiAPITarget]> {
        if swarmCache[hexEncodedPublicKey] == nil {
            storage.dbReadConnection.read { transaction in
                swarmCache[hexEncodedPublicKey] = storage.getSwarm(for: hexEncodedPublicKey, in: transaction)
            }
        }
        if let cachedSwarm = swarmCache[hexEncodedPublicKey], cachedSwarm.count >= minimumSwarmSnodeCount && !isForcedReload {
            return Promise<[LokiAPITarget]> { $0.fulfill(cachedSwarm) }
        } else {
            print("[Loki] Getting swarm for: \(hexEncodedPublicKey).")
            let parameters: [String:Any] = [ "pubKey" : hexEncodedPublicKey ]
            return getRandomSnode().then2 {
                invoke(.getSwarm, on: $0, associatedWith: hexEncodedPublicKey, parameters: parameters)
            }.map2 {
                parseTargets(from: $0)
            }.get2 { swarm in
                swarmCache[hexEncodedPublicKey] = swarm
                try! Storage.writeSync { transaction in
                    storage.setSwarm(swarm, for: hexEncodedPublicKey, in: transaction)
                }
            }
        }
    }

    internal static func getTargetSnodes(for hexEncodedPublicKey: String) -> Promise<[LokiAPITarget]> {
        // shuffled() uses the system's default random generator, which is cryptographically secure
        return getSwarm(for: hexEncodedPublicKey).map2 { Array($0.shuffled().prefix(targetSwarmSnodeCount)) }
    }

    internal static func dropSnodeFromSnodePool(_ target: LokiAPITarget) {
        LokiAPI.snodePool.remove(target)
        try! Storage.writeSync { transaction in
            storage.dropSnodeFromSnodePool(target, in: transaction)
        }
    }

    internal static func dropSnodeFromSwarmIfNeeded(_ target: LokiAPITarget, hexEncodedPublicKey: String) {
        let swarm = LokiAPI.swarmCache[hexEncodedPublicKey]
        if var swarm = swarm, let index = swarm.firstIndex(of: target) {
            swarm.remove(at: index)
            LokiAPI.swarmCache[hexEncodedPublicKey] = swarm
            try! Storage.writeSync { transaction in
                storage.setSwarm(swarm, for: hexEncodedPublicKey, in: transaction)
            }
        }
    }

    // MARK: Public API
    @objc public static func clearSnodePool() {
        snodePool.removeAll()
        try! Storage.writeSync { transaction in
            storage.clearSnodePool(in: transaction)
        }
    }

    // MARK: Parsing
    private static func parseTargets(from rawResponse: Any) -> [LokiAPITarget] {
        guard let json = rawResponse as? JSON, let rawTargets = json["snodes"] as? [JSON] else {
            print("[Loki] Failed to parse targets from: \(rawResponse).")
            return []
        }
        return rawTargets.flatMap { rawTarget in
            guard let address = rawTarget["ip"] as? String, let portAsString = rawTarget["port"] as? String, let port = UInt16(portAsString), let ed25519PublicKey = rawTarget["pubkey_ed25519"] as? String, let x25519PublicKey = rawTarget["pubkey_x25519"] as? String, address != "0.0.0.0" else {
                print("[Loki] Failed to parse target from: \(rawTarget).")
                return nil
            }
            return LokiAPITarget(address: "https://\(address)", port: port, publicKeySet: LokiAPITarget.KeySet(ed25519Key: ed25519PublicKey, x25519Key: x25519PublicKey))
        }
    }
}

// MARK: Snode Error Handling
internal extension Promise {
    
    internal func handlingSnodeErrorsIfNeeded(for target: LokiAPITarget, associatedWith hexEncodedPublicKey: String) -> Promise<T> {
        return recover2 { error -> Promise<T> in
            if let error = error as? LokiHTTPClient.HTTPError {
                switch error.statusCode {
                case 0, 400, 500, 503:
                    // The snode is unreachable
                    let oldFailureCount = LokiAPI.snodeFailureCount[target] ?? 0
                    let newFailureCount = oldFailureCount + 1
                    LokiAPI.snodeFailureCount[target] = newFailureCount
                    print("[Loki] Couldn't reach snode at: \(target); setting failure count to \(newFailureCount).")
                    if newFailureCount >= LokiAPI.snodeFailureThreshold {
                        print("[Loki] Failure threshold reached for: \(target); dropping it.")
                        LokiAPI.dropSnodeFromSwarmIfNeeded(target, hexEncodedPublicKey: hexEncodedPublicKey)
                        LokiAPI.dropSnodeFromSnodePool(target)
                        LokiAPI.snodeFailureCount[target] = 0
                    }
                case 406:
                    print("[Loki] The user's clock is out of sync with the service node network.")
                    throw LokiAPI.LokiAPIError.clockOutOfSync
                case 421:
                    // The snode isn't associated with the given public key anymore
                    print("[Loki] Invalidating swarm for: \(hexEncodedPublicKey).")
                    LokiAPI.dropSnodeFromSwarmIfNeeded(target, hexEncodedPublicKey: hexEncodedPublicKey)
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
