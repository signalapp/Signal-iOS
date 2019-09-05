import PromiseKit

extension String : Error { }

public extension LokiAPI {
    
    fileprivate static var failureCount: [LokiAPITarget:UInt] = [:]
    
    // MARK: Settings
    private static let minimumSnodeCount = 2
    private static let targetSnodeCount = 3
    fileprivate static let failureThreshold = 2
    
    // MARK: Caching
    private static let swarmCacheKey = "swarmCacheKey"
    private static let swarmCacheCollection = "swarmCacheCollection"
    
    internal static var swarmCache: [String:[LokiAPITarget]] {
        get {
            var result: [String:[LokiAPITarget]]? = nil
            storage.dbReadConnection.read { transaction in
                result = transaction.object(forKey: swarmCacheKey, inCollection: swarmCacheCollection) as! [String:[LokiAPITarget]]?
            }
            return result ?? [:]
        }
        set {
            storage.dbReadWriteConnection.readWrite { transaction in
                transaction.setObject(newValue, forKey: swarmCacheKey, inCollection: swarmCacheCollection)
            }
        }
    }
    
    internal static func dropIfNeeded(_ target: LokiAPITarget, hexEncodedPublicKey: String) {
        let swarm = LokiAPI.swarmCache[hexEncodedPublicKey]
        if var swarm = swarm, let index = swarm.firstIndex(of: target) {
            swarm.remove(at: index)
            LokiAPI.swarmCache[hexEncodedPublicKey] = swarm
        }
    }
    
    // MARK: Clearnet Setup
    fileprivate static let seedNodePool: Set<String> = [ "http://storage.seed1.loki.network:22023", "http://storage.seed2.loki.network:38157", "http://imaginary.stream:38157" ]
    fileprivate static var randomSnodePool: Set<LokiAPITarget> = []

    @objc public static func clearRandomSnodePool() {
        randomSnodePool.removeAll()
    }
    
    // MARK: Internal API
    private static func getRandomSnode() -> Promise<LokiAPITarget> {
        if randomSnodePool.isEmpty {
            let target = seedNodePool.randomElement()!
            let url = URL(string: "\(target)/json_rpc")!
            let request = TSRequest(url: url, method: "POST", parameters: [
                "method" : "get_n_service_nodes",
                "params" : [
                    "active_only" : true,
                    "limit" : 24,
                    "fields" : [
                        "public_ip" : true,
                        "storage_port" : true
                    ]
                ]
            ])
            print("[Loki] Invoking get_n_service_nodes on \(target).")
            return TSNetworkManager.shared().makePromise(request: request).map { intermediate in
                let rawResponse = intermediate.responseObject
                guard let json = rawResponse as? JSON, let intermediate = json["result"] as? JSON, let rawTargets = intermediate["service_node_states"] as? [JSON] else { throw "Failed to update random snode pool from: \(rawResponse)." }
                randomSnodePool = try Set(rawTargets.flatMap { rawTarget in
                    guard let address = rawTarget["public_ip"] as? String, let port = rawTarget["storage_port"] as? Int, address != "0.0.0.0" else {
                        print("Failed to update random snode pool from: \(rawTarget).")
                        return nil
                    }
                    return LokiAPITarget(address: "https://\(address)", port: UInt16(port))
                })
                return randomSnodePool.randomElement()!
            }.recover { error -> Promise<LokiAPITarget> in
                Analytics.shared.track("Seed Node Failed")
                throw error
            }
        } else {
            return Promise<LokiAPITarget> { seal in
                seal.fulfill(randomSnodePool.randomElement()!)
            }
        }
    }
    
    internal static func getSwarm(for hexEncodedPublicKey: String) -> Promise<[LokiAPITarget]> {
        if let cachedSwarm = swarmCache[hexEncodedPublicKey], cachedSwarm.count >= minimumSnodeCount {
            return Promise<[LokiAPITarget]> { $0.fulfill(cachedSwarm) }
        } else {
            let parameters: [String:Any] = [ "pubKey" : hexEncodedPublicKey ]
            return getRandomSnode().then { invoke(.getSwarm, on: $0, associatedWith: hexEncodedPublicKey, parameters: parameters) }.map { parseTargets(from: $0) }.get { swarmCache[hexEncodedPublicKey] = $0 }
        }
    }

    // MARK: Public API
    internal static func getTargetSnodes(for hexEncodedPublicKey: String) -> Promise<[LokiAPITarget]> {
        // shuffled() uses the system's default random generator, which is cryptographically secure
        return getSwarm(for: hexEncodedPublicKey).map { Array($0.shuffled().prefix(targetSnodeCount)) }
    }
    
    // MARK: Parsing
    private static func parseTargets(from rawResponse: Any) -> [LokiAPITarget] {
        guard let json = rawResponse as? JSON, let rawSnodes = json["snodes"] as? [JSON] else {
            print("[Loki] Failed to parse targets from: \(rawResponse).")
            return []
        }
        return rawSnodes.flatMap { rawSnode in
            guard let address = rawSnode["ip"] as? String, let portAsString = rawSnode["port"] as? String, let port = UInt16(portAsString), address != "0.0.0.0" else {
                print("[Loki] Failed to parse target from: \(rawSnode).")
                return nil
            }
            return LokiAPITarget(address: "https://\(address)", port: port)
        }
    }
}

// MARK: Error Handling
internal extension Promise {
    
    internal func handlingSwarmSpecificErrorsIfNeeded(for target: LokiAPITarget, associatedWith hexEncodedPublicKey: String) -> Promise<T> {
        return recover { error -> Promise<T> in
            if let error = error as? NetworkManagerError {
                switch error.statusCode {
                case 0, 400, 500, 503:
                    // The snode is unreachable
                    let oldFailureCount = LokiAPI.failureCount[target] ?? 0
                    let newFailureCount = oldFailureCount + 1
                    LokiAPI.failureCount[target] = newFailureCount
                    print("[Loki] Couldn't reach snode at: \(target); setting failure count to \(newFailureCount).")
                    Analytics.shared.track("Unreachable Snode")
                    if newFailureCount >= LokiAPI.failureThreshold {
                        print("[Loki] Failure threshold reached for: \(target); dropping it.")
                        LokiAPI.dropIfNeeded(target, hexEncodedPublicKey: hexEncodedPublicKey) // Remove it from the swarm cache associated with the given public key
                        LokiAPI.randomSnodePool.remove(target) // Remove it from the random snode pool
                        LokiAPI.failureCount[target] = 0
                    }
                case 421:
                    // The snode isn't associated with the given public key anymore
                    print("[Loki] Invalidating swarm for: \(hexEncodedPublicKey).")
                    Analytics.shared.track("Migrated Snode")
                    LokiAPI.dropIfNeeded(target, hexEncodedPublicKey: hexEncodedPublicKey)
                case 432:
                    // The PoW difficulty is too low
                    if case NetworkManagerError.taskError(_, let underlyingError) = error, let nsError = underlyingError as? NSError,
                        let data = nsError.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] as? Data, let json = try? JSONSerialization.jsonObject(with: data, options: []) as? JSON,
                        let powDifficulty = json["difficulty"] as? Int {
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
