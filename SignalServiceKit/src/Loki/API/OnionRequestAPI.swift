import PromiseKit

internal enum OnionRequestAPI {
    private static let workQueue = DispatchQueue.global() // TODO: We should probably move away from using the global queue for this

    internal static var guardSnodes: Set<LokiAPITarget> = []
    internal static var paths: Set<Path> = []

    // MARK: Settings
    private static let pathCount: UInt = 3
    /// The number of snodes (including the guard snode) in a path.
    private static let pathSize: UInt = 3
    private static let guardSnodeCount: UInt = 3

    // MARK: Error
    internal enum Error : LocalizedError {
        case insufficientSnodes

        var errorDescription: String? {
            switch self {
            case .insufficientSnodes: return "Couldn't find enough snodes to build a path."
            }
        }
    }

    // MARK: Path
    internal typealias Path = OnionRequestPath

    // MARK: Private API
    /// Tests the given guard snode candidate. The returned promise errors out if the snode is faulty; the promise is fulfilled otherwise.
    private static func testGuardSnodeCandidate(_ candidate: LokiAPITarget) -> Promise<Void> {
        print("[Loki] Testing candidate guard snode: \(candidate).")
        let hexEncodedPublicKey = getUserHexEncodedPublicKey()
        let parameters: JSON = [ "pubKey" : hexEncodedPublicKey ]
        let timeout: TimeInterval = 10 // Use a shorter timeout for testing
        return LokiAPI.invoke(.getSwarm, on: candidate, associatedWith: hexEncodedPublicKey, parameters: parameters, timeout: timeout).map(on: workQueue) { _ in }
    }

    /// Finds `guardSnodeCount` reliable guard snodes to use for path building. The returned promise may error out with `Error.insufficientSnodes`
    /// if not enough (reliable) snodes are available.
    private static func getGuardSnodes() -> Promise<Set<LokiAPITarget>> {
        if !guardSnodes.isEmpty {
            return Promise<Set<LokiAPITarget>> { $0.fulfill(guardSnodes) }
        } else {
            print("[Loki] Populating guard snode cache.")
            return LokiAPI.getRandomSnode().then(on: workQueue) { _ -> Promise<Set<LokiAPITarget>> in // Just used to populate the snode pool
                let snodePool = LokiAPI.randomSnodePool
                guard !snodePool.isEmpty else { throw Error.insufficientSnodes }
                var result: Set<LokiAPITarget> = [] // Sync on DispatchQueue.global()
                // Loops until a valid guard snode is found
                func getGuardSnode() -> Promise<LokiAPITarget> {
                    // randomElement() uses the system's default random generator, which is cryptographically secure
                    guard let candidate = snodePool.randomElement() else { return Promise<LokiAPITarget> { $0.reject(Error.insufficientSnodes) } }
                    return testGuardSnodeCandidate(candidate).map(on: workQueue) { candidate }.recover(on: workQueue) { _ in getGuardSnode() }
                }
                func getAndStoreGuardSnode() -> Promise<LokiAPITarget> {
                    return getGuardSnode().then(on: workQueue) { guardSnode -> Promise<LokiAPITarget> in
                        if !result.contains(guardSnode) {
                            result.insert(guardSnode)
                            return Promise { $0.fulfill(guardSnode) }
                        } else {
                            return getAndStoreGuardSnode()
                        }
                    }
                }
                let promises = (0..<guardSnodeCount).map { _ in getAndStoreGuardSnode() }
                return when(fulfilled: promises).map(on: workQueue) { guardSnodes in
                    let guardSnodesAsSet = Set(guardSnodes)
                    OnionRequestAPI.guardSnodes = guardSnodesAsSet
                    return guardSnodesAsSet
                }
            }
        }
    }

    /// Builds and returns `pathCount` paths. The returned promise may error out with `Error.insufficientSnodes`
    /// if not enough (reliable) snodes are available.
    private static func buildPaths() -> Promise<Set<Path>> {
        print("[Loki] Building onion request paths.")
        return LokiAPI.getRandomSnode().then(on: workQueue) { _ -> Promise<Set<Path>> in // Just used to populate the snode pool
            let snodePool = LokiAPI.randomSnodePool
            return getGuardSnodes().map(on: workQueue) { guardSnodes in
                var unusedSnodes = snodePool.subtracting(guardSnodes)
                let minSnodeCount = guardSnodeCount * pathSize - guardSnodeCount
                guard unusedSnodes.count >= minSnodeCount else { throw Error.insufficientSnodes }
                let result = Set(guardSnodes.map { guardSnode -> Path in
                    // The force unwraps are safe because of the minSnodeCount check above
                    let snode1 = unusedSnodes.randomElement()!
                    let snode2 = unusedSnodes.randomElement()!
                    return Path(guardSnode: guardSnode, snode1: snode1, snode2: snode2)
                })
                print("[Loki] Built new onion request paths: \(result.map { "\($0.description)" }.joined(separator: ", "))")
                return result
            }
        }
    }

    // MARK: Internal API
    /// Returns an `OnionRequestPath` to be used for onion requests. Builds new paths if needed.
    internal static func getPath() -> Promise<Path> {
        // randomElement() uses the system's default random generator, which is cryptographically secure
        if paths.count >= pathCount {
            return Promise<Path> { $0.fulfill(paths.randomElement()!) }
        } else {
            return buildPaths().map(on: workQueue) { paths in
                let path = paths.randomElement()!
                OnionRequestAPI.paths = paths
                return path
            }
        }
    }
}
