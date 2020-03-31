import PromiseKit

// TODO: Test path snodes as well

/// See the "Onion Requests" section of [The Session Whitepaper](https://arxiv.org/pdf/2002.04609.pdf) for more information.
internal enum OnionRequestAPI {
    private static let urlSessionDelegate = URLSessionDelegateImplementation()
    private static let urlSession = URLSession(configuration: .ephemeral, delegate: urlSessionDelegate, delegateQueue: nil)

    /// - Note: Exposed for testing purposes.
    internal static let workQueue = DispatchQueue.global() // TODO: We should probably move away from using the global queue for this
    internal static var guardSnodes: Set<LokiAPITarget> = []
    internal static var paths: Set<Path> = []

    // MARK: Settings
    private static let pathCount: UInt = 3
    /// The number of snodes (including the guard snode) in a path.
    private static let pathSize: UInt = 3
    private static let guardSnodeCount: UInt = 3

    // MARK: URL Session Delegate Implementation
    private final class URLSessionDelegateImplementation : NSObject, URLSessionDelegate {

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // Snode to snode communication uses self-signed certificates but clients can safely ignore this
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        }
    }

    // MARK: Error
    internal enum Error : LocalizedError {
        case insufficientSnodes
        case snodePublicKeySetMissing
        case randomDataGenerationFailed
        case generic

        var errorDescription: String? {
            switch self {
            case .insufficientSnodes: return "Couldn't find enough snodes to build a path."
            case .snodePublicKeySetMissing: return "Missing snode public key set."
            case .randomDataGenerationFailed: return "Couldn't generate random data."
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

    /// Finds `guardSnodeCount` guard snodes to use for path building. The returned promise errors out with `Error.insufficientSnodes`
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

    /// Builds and returns `pathCount` paths. The returned promise errors out with `Error.insufficientSnodes`
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
                    // randomElement() uses the system's default random generator, which is cryptographically secure
                    return [ guardSnode ] + (0..<(pathSize - 1)).map { _ in unusedSnodes.randomElement()! }
                })
                print("[Loki] [Onion Request API] Built new onion request paths: \(result.map { "\($0.description)" }.joined(separator: ", "))")
                return result
            }
        }
    }

    /// Returns a `Path` to be used for onion requests. Builds paths as needed.
    ///
    /// - Note: Should ideally only ever be invoked from `DispatchQueue.global()`.
    private static func getPath() -> Promise<Path> {
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

    /// Builds an onion around `payload` and returns the result.
    private static func buildOnion(around payload: Data, targetedAt snode: LokiAPITarget) -> Promise<(guardSnode: LokiAPITarget, onion: Data)> {
        var guardSnode: LokiAPITarget!
        return getPath().then(on: workQueue) { path -> Promise<EncryptionResult> in
            guardSnode = path.first!
            return encrypt(payload, forTargetSnode: snode).then(on: workQueue) { r -> Promise<EncryptionResult> in
                var path = path
                var encryptionResult = r
                var rhs = snode
                func addLayer() -> Promise<EncryptionResult> {
                    if path.isEmpty {
                        return Promise<EncryptionResult> { $0.fulfill(encryptionResult) }
                    } else {
                        let lhs = path.removeLast()
                        return OnionRequestAPI.encryptHop(from: lhs, to: rhs, using: encryptionResult).then(on: workQueue) { e -> Promise<EncryptionResult> in
                            encryptionResult = e
                            rhs = lhs
                            return addLayer()
                        }
                    }
                }
                return addLayer()
            }
        }.map { (guardSnode: guardSnode, onion: $0.ciphertext) }
    }

    // MARK: Internal API
    /// Sends an onion request to `snode`. Builds paths as needed.
    internal static func send(_ request: URLRequest, to snode: LokiAPITarget) -> Promise<Any> {
        return buildOnion(around: request.httpBody!, targetedAt: snode).then(on: workQueue) { intermediate -> Promise<Any> in
            let guardSnode = intermediate.guardSnode
            let onion = intermediate.onion
            let (promise, seal) = Promise<Any>.pending()
            let task = urlSession.dataTask(with: request) { response, result, error in
                if let error = error {
                    seal.reject(error)
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
