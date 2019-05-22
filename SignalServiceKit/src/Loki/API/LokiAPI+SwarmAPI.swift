import PromiseKit

extension LokiAPI {
    
    // MARK: Settings
    private static let targetSnodeCount = 2
    private static let defaultSnodePort: UInt16 = 8080
    
    // MARK: Caching
    private static var swarmCache: [String:[Target]] = [:]
    
    // MARK: Internal API
    private static func getRandomSnode() -> Promise<Target> {
        return Promise<Target> { seal in
            seal.fulfill(Target(address: "http://13.238.53.205", port: 8080)) // TODO: For debugging purposes
        }
    }
    
    private static func getSwarm(for hexEncodedPublicKey: String) -> Promise<[Target]> {
        if let cachedSwarm = swarmCache[hexEncodedPublicKey], cachedSwarm.count >= targetSnodeCount {
            return Promise<[Target]> { $0.fulfill(cachedSwarm) }
        } else {
            let parameters: [String:Any] = [ "pubKey" : hexEncodedPublicKey ]
            return getRandomSnode().then { invoke(.getSwarm, on: $0, with: parameters) }.map { parseTargets(from: $0) }.get { swarmCache[hexEncodedPublicKey] = $0 }
        }
    }
    
    internal static func getTargetSnodes(for hexEncodedPublicKey: String) -> Promise<[Target]> {
        // shuffled() uses the system's default random generator, which is cryptographically secure
        return getSwarm(for: hexEncodedPublicKey).map { Array($0.shuffled().prefix(targetSnodeCount)) }
    }
    
    // MARK: Parsing
    private static func parseTargets(from rawResponse: Any) -> [Target] {
        // TODO: For debugging purposes
        // ========
        let target = Target(address: "http://13.238.53.205", port: defaultSnodePort)
        return Array(repeating: target, count: 3)
        // ========
//        guard let json = rawResponse as? JSON, let addresses = json["snodes"] as? [String] else {
//            Logger.warn("[Loki] Failed to parse targets from: \(rawResponse).")
//            return []
//        }
//        return addresses.map { Target(address: $0, port: defaultSnodePort) }
    }
}
