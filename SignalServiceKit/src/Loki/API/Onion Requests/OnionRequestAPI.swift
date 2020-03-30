import PromiseKit

// TODO: Test path snodes as well

/// See the "Onion Requests" section of [The Session Whitepaper](https://arxiv.org/pdf/2002.04609.pdf) for more information.
internal enum OnionRequestAPI {
    /// - Note: Exposed for testing purposes.
    internal static let workQueue = DispatchQueue.global() // TODO: We should probably move away from using the global queue for this
    internal static var guardSnodes: Set<LokiAPITarget> = []
    internal static var paths: Set<Path> = []

    private static let httpSession: AFHTTPSessionManager = {
        let result = AFHTTPSessionManager(sessionConfiguration: .ephemeral)
        let securityPolicy = AFSecurityPolicy.default()
        securityPolicy.allowInvalidCertificates = true
        securityPolicy.validatesDomainName = false // TODO: Do we need this?
        result.securityPolicy = securityPolicy
        result.responseSerializer = AFHTTPResponseSerializer()
        result.completionQueue = workQueue
        return result
    }()

    // MARK: Settings
    private static let pathCount: UInt = 3
    /// The number of snodes (including the guard snode) in a path.
    private static let pathSize: UInt = 3
    private static let guardSnodeCount: UInt = 3

    // MARK: Error
    internal enum Error : LocalizedError {
        case insufficientSnodes
        case generic

        var errorDescription: String? {
            switch self {
            case .insufficientSnodes: return "Couldn't find enough snodes to build a path."
            case .generic: return "An error occurred."
            }
        }
    }

    // MARK: Path
    internal typealias Path = [LokiAPITarget]

    // MARK: Private API
    /// Tests the given snode. The returned promise errors out if the snode is faulty; the promise is fulfilled otherwise.
    private static func testSnode(_ snode: LokiAPITarget) -> Promise<Void> {
        print("[Loki] [Onion Request API] Testing snode: \(snode).")
        let hexEncodedPublicKey = getUserHexEncodedPublicKey()
        let parameters: JSON = [ "pubKey" : hexEncodedPublicKey ]
        let timeout: TimeInterval = 10 // Use a shorter timeout for testing
        return LokiAPI.invoke(.getSwarm, on: snode, associatedWith: hexEncodedPublicKey, parameters: parameters, timeout: timeout).map(on: workQueue) { _ in }
    }

    /// Finds `guardSnodeCount` guard snodes to use for path building. The returned promise may error out with `Error.insufficientSnodes`
    /// if not enough (reliable) snodes are available.
    private static func getGuardSnodes() -> Promise<Set<LokiAPITarget>> {
        if !guardSnodes.isEmpty {
            return Promise<Set<LokiAPITarget>> { $0.fulfill(guardSnodes) }
        } else {
            print("[Loki] [Onion Request API] Populating guard snode cache.")
            return LokiAPI.getRandomSnode().then(on: workQueue) { _ -> Promise<Set<LokiAPITarget>> in // Just used to populate the snode pool
                let snodePool = LokiAPI.randomSnodePool
                guard !snodePool.isEmpty else { throw Error.insufficientSnodes }
                var result: Set<LokiAPITarget> = [] // Sync on DispatchQueue.global()
                func getGuardSnode() -> Promise<LokiAPITarget> {
                    // randomElement() uses the system's default random generator, which is cryptographically secure
                    guard let candidate = snodePool.randomElement() else { return Promise<LokiAPITarget> { $0.reject(Error.insufficientSnodes) } }
                    // Loop until a valid guard snode is found
                    return testSnode(candidate).map(on: workQueue) { candidate }.recover(on: workQueue) { _ in getGuardSnode() }
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
        print("[Loki] [Onion Request API] Building onion request paths.")
        return LokiAPI.getRandomSnode().then(on: workQueue) { _ -> Promise<Set<Path>> in // Just used to populate the snode pool
            let snodePool = LokiAPI.randomSnodePool
            return getGuardSnodes().map(on: workQueue) { guardSnodes in
                var unusedSnodes = snodePool.subtracting(guardSnodes)
                let minSnodeCount = guardSnodeCount * pathSize - guardSnodeCount
                guard unusedSnodes.count >= minSnodeCount else { throw Error.insufficientSnodes }
                let result: Set<Path> = Set(guardSnodes.map { guardSnode in
                    // Force unwrapping is safe because of the minSnodeCount check above
                    return [ guardSnode ] + (0..<(pathSize - 1)).map { _ in unusedSnodes.randomElement()! }
                })
                print("[Loki] [Onion Request API] Built new onion request paths: \(result.map { "\($0.description)" }.joined(separator: ", "))")
                return result
            }
        }
    }

    private static func encrypt(_ request: TSRequest, forTargetSnode snode: LokiAPITarget) -> Promise<TSRequest> {
        return Promise<TSRequest> { $0.fulfill(request) }
    }

    private static func encrypt(_ request: TSRequest, forRelayFrom snode1: LokiAPITarget, to snode2: LokiAPITarget) -> Promise<TSRequest> {
        return Promise<TSRequest> { $0.fulfill(request) }
    }

    // MARK: Internal API
    /// Returns an `OnionRequestPath` to be used for onion requests. Builds new paths as needed.
    ///
    /// - Note: Should ideally only ever be invoked from `DispatchQueue.global()`.
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

    /// Sends an onion request to `snode`. Builds paths as needed.
    internal static func send(_ request: TSRequest, to snode: LokiAPITarget) -> Promise<Any> {
        var request = request
        return getPath().then(on: workQueue) { path -> Promise<TSRequest> in
            var path = path
            path.removeFirst() // Drop the guard snode
            return encrypt(request, forTargetSnode: snode).then(on: workQueue) { r -> Promise<TSRequest> in
                request = r
                var rhs = snode
                func encryptForNextLayer() -> Promise<TSRequest> {
                    if path.isEmpty {
                        return Promise<TSRequest> { $0.fulfill(request) }
                    } else {
                        let lhs = path.removeLast()
                        return encrypt(request, forRelayFrom: lhs, to: rhs).then(on: workQueue) { r -> Promise<TSRequest> in
                            request = r
                            rhs = lhs
                            return encryptForNextLayer()
                        }
                    }
                }
                return encryptForNextLayer()
            }
        }.then { request -> Promise<Any> in
            let (promise, seal) = LokiAPI.RawResponsePromise.pending()
            var task: URLSessionDataTask!
            task = httpSession.dataTask(with: request as URLRequest) { response, result, error in
                if let error = error {
                    let nmError = NetworkManagerError.taskError(task: task, underlyingError: error)
                    let nsError = nmError as NSError
                    nsError.isRetryable = false
                    seal.reject(nsError)
                } else if let result = result {
                    seal.fulfill(result)
                } else {
                    seal.reject(Error.generic)
                }
            }
            task.resume()
            return promise
        }
    }
}
