import PromiseKit

extension String : Error { }

public extension LokiAPI {
    
    // MARK: Settings
    private static let minimumSnodeCount = 2
    private static let targetSnodeCount = 3
    private static let defaultSnodePort: UInt16 = 8080
    
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
    private static var randomSnodePool: Set<LokiAPITarget> = []
    
    // MARK: Internal API
    private static func getRandomSnode() -> Promise<LokiAPITarget> {
        if randomSnodePool.isEmpty {
            let url = URL(string: "http://3.104.19.14:22023/json_rpc")!
            let request = TSRequest(url: url, method: "POST", parameters: [ "method" : "get_service_nodes" ])
            return TSNetworkManager.shared().makePromise(request: request).map { intermediate in
                let rawResponse = intermediate.responseObject
                guard let json = rawResponse as? JSON, let intermediate = json["result"] as? JSON, let rawTargets = intermediate["service_node_states"] as? [JSON] else { throw "Failed to update random snode pool from: \(rawResponse)." }
                randomSnodePool = try Set(rawTargets.flatMap { rawTarget in
                    guard let address = rawTarget["public_ip"] as? String, let port = rawTarget["storage_port"] as? Int else { throw "Failed to update random snode pool from: \(rawTarget)." }
                    return LokiAPITarget(address: "https://\(address)", port: UInt16(port))
                })
                return randomSnodePool.randomElement()!
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
            Logger.warn("[Loki] Failed to parse targets from: \(rawResponse).")
            return []
        }
        return rawSnodes.flatMap { rawSnode in
            guard let address = rawSnode["ip"] as? String, let port = rawSnode["port"] as? Int else { return nil }
            return LokiAPITarget(address: address, port: UInt16(port))
        }
    }
}

// MARK: Error Handling
internal extension Promise {
    
    internal func handlingSwarmSpecificErrorsIfNeeded(for target: LokiAPITarget, associatedWith hexEncodedPublicKey: String) -> Promise<T> {
        return recover { error -> Promise<T> in
            if let error = error as? NetworkManagerError {
                switch error.statusCode {
                case 0:
                    // The snode is unreachable; usually a problem with LokiNet
                    Logger.warn("[Loki] Couldn't reach snode at: \(target.address):\(target.port).")
                case 421:
                    // The snode isn't associated with the given public key anymore
                    Logger.warn("[Loki] Invalidating swarm for: \(hexEncodedPublicKey).")
                    LokiAPI.dropIfNeeded(target, hexEncodedPublicKey: hexEncodedPublicKey)
                default: break
                }
            }
            throw error
        }
    }
}
