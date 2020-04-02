import CryptoSwift
import PromiseKit

/// See the "Onion Requests" section of [The Session Whitepaper](https://arxiv.org/pdf/2002.04609.pdf) for more information.
internal enum OnionRequestAPI {
    /// - Note: Exposed for testing purposes.
    internal static let workQueue = DispatchQueue(label: "OnionRequestAPI.workQueue", qos: .userInitiated)
    /// - Note: Must only be modified from `workQueue`.
    internal static var guardSnodes: Set<LokiAPITarget> = []
    /// - Note: Must only be modified from `workQueue`.
    internal static var paths: Set<Path> = []

    private static var snodePool: Set<LokiAPITarget> {
        let unreliableSnodes = Set(LokiAPI.failureCount.keys)
        return LokiAPI.randomSnodePool.subtracting(unreliableSnodes)
    }

    // MARK: Settings
    private static let pathCount: UInt = 2
    /// The number of snodes (including the guard snode) in a path.
    private static let pathSize: UInt = 3

    private static var guardSnodeCount: UInt { return pathCount } // One per path

    // MARK: Error
    internal enum Error : LocalizedError {
        case insufficientSnodes
        case missingSnodeVersion
        case randomDataGenerationFailed
        case snodePublicKeySetMissing
        case unsupportedSnodeVersion(String)

        var errorDescription: String? {
            switch self {
            case .insufficientSnodes: return "Couldn't find enough snodes to build a path."
            case .missingSnodeVersion: return "Missing snode version."
            case .randomDataGenerationFailed: return "Couldn't generate random data."
            case .snodePublicKeySetMissing: return "Missing snode public key set."
            case .unsupportedSnodeVersion(let version): return "Unsupported snode version: \(version)."
            }
        }
    }

    // MARK: Path
    internal typealias Path = [LokiAPITarget]

    // MARK: Onion Building Result
    private typealias OnionBuildingResult = (guardSnode: LokiAPITarget, finalEncryptionResult: EncryptionResult, targetSnodeSymmetricKey: Data)

    // MARK: Private API
    /// Tests the given snode. The returned promise errors out if the snode is faulty; the promise is fulfilled otherwise.
    private static func testSnode(_ snode: LokiAPITarget) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        let queue = DispatchQueue(label: UUID().uuidString, qos: .userInitiated) // No need to block the work queue for this
        queue.async {
            let url = "\(snode.address):\(snode.port)/get_stats/v1"
            let timeout: TimeInterval = 6 // Use a shorter timeout for testing
            HTTP.execute(.get, url, timeout: timeout).done(on: queue) { rawResponse in
                guard let json = rawResponse as? JSON, let version = json["version"] as? String else { return seal.reject(Error.missingSnodeVersion) }
                if version >= "2.0.0" {
                    seal.fulfill(())
                } else {
                    print("[Loki] [Onion Request API] Unsupported snode version: \(version).")
                    seal.reject(Error.unsupportedSnodeVersion(version))
                }
            }.catch(on: queue) { error in
                seal.reject(error)
            }
        }
        return promise
    }

    /// Finds `guardSnodeCount` guard snodes to use for path building. The returned promise errors out with `Error.insufficientSnodes`
    /// if not enough (reliable) snodes are available.
    private static func getGuardSnodes() -> Promise<Set<LokiAPITarget>> {
        if guardSnodes.count >= guardSnodeCount {
            return Promise<Set<LokiAPITarget>> { $0.fulfill(guardSnodes) }
        } else {
            print("[Loki] [Onion Request API] Populating guard snode cache.")
            return LokiAPI.getRandomSnode().then(on: workQueue) { _ -> Promise<Set<LokiAPITarget>> in // Just used to populate the snode pool
                var unusedSnodes = snodePool // Sync on workQueue
                guard unusedSnodes.count >= guardSnodeCount else { throw Error.insufficientSnodes }
                func getGuardSnode() -> Promise<LokiAPITarget> {
                    // randomElement() uses the system's default random generator, which is cryptographically secure
                    guard let candidate = unusedSnodes.randomElement() else { return Promise<LokiAPITarget> { $0.reject(Error.insufficientSnodes) } }
                    unusedSnodes.remove(candidate) // All used snodes should be unique
                    print("[Loki] [Onion Request API] Testing guard snode: \(candidate).")
                    // Loop until a reliable guard snode is found
                    return testSnode(candidate).map(on: workQueue) { candidate }.recover(on: workQueue) { _ in getGuardSnode() }
                }
                let promises = (0..<guardSnodeCount).map { _ in getGuardSnode() }
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
            return getGuardSnodes().map(on: workQueue) { guardSnodes in
                var unusedSnodes = snodePool.subtracting(guardSnodes)
                let pathSnodeCount = guardSnodeCount * pathSize - guardSnodeCount
                guard unusedSnodes.count >= pathSnodeCount else { throw Error.insufficientSnodes }
                // Don't test path snodes as this would reveal the user's IP to them
                return Set(guardSnodes.map { guardSnode in
                    let result = [ guardSnode ] + (0..<(pathSize - 1)).map { _ in
                        // randomElement() uses the system's default random generator, which is cryptographically secure
                        let pathSnode = unusedSnodes.randomElement()! // Safe because of the minSnodeCount check above
                        unusedSnodes.remove(pathSnode) // All used snodes should be unique
                        return pathSnode
                    }
                    print("[Loki] [Onion Request API] Built new onion request path: \(result.prettifiedDescription).")
                    return result
                })
            }
        }
    }

    /// Returns a `Path` to be used for building an onion request. Builds new paths as needed.
    ///
    /// - Note: Exposed for testing purposes.
    internal static func getPath(excluding snode: LokiAPITarget) -> Promise<Path> {
        guard pathSize >= 1 else { preconditionFailure("Can't build path of size zero.") }
        // randomElement() uses the system's default random generator, which is cryptographically secure
        if paths.count >= pathCount {
            return Promise<Path> { seal in
                seal.fulfill(paths.filter { !$0.contains(snode) }.randomElement()!)
            }
        } else {
            return buildPaths().map(on: workQueue) { paths in
                let path = paths.filter { !$0.contains(snode) }.randomElement()!
                OnionRequestAPI.paths = paths
                return path
            }
        }
    }

    private static func dropPath(containing snode: LokiAPITarget) {
        paths = paths.filter { !$0.contains(snode) }
    }

    /// Builds an onion around `payload` and returns the result.
    private static func buildOnion(around payload: JSON, targetedAt snode: LokiAPITarget) -> Promise<OnionBuildingResult> {
        var guardSnode: LokiAPITarget!
        var targetSnodeSymmetricKey: Data! // Needed by invoke(_:on:with:) to decrypt the response sent back by the target snode
        var encryptionResult: EncryptionResult!
        return getPath(excluding: snode).then(on: workQueue) { path -> Promise<EncryptionResult> in
            guardSnode = path.first!
            // Encrypt in reverse order, i.e. the target snode first
            return encrypt(payload, forTargetSnode: snode).then(on: workQueue) { r -> Promise<EncryptionResult> in
                targetSnodeSymmetricKey = r.symmetricKey
                // Recursively encrypt the layers of the onion (again in reverse order)
                encryptionResult = r
                var path = path
                var rhs = snode
                func addLayer() -> Promise<EncryptionResult> {
                    if path.isEmpty {
                        return Promise<EncryptionResult> { $0.fulfill(encryptionResult) }
                    } else {
                        let lhs = path.removeLast()
                        return OnionRequestAPI.encryptHop(from: lhs, to: rhs, using: encryptionResult).then(on: workQueue) { r -> Promise<EncryptionResult> in
                            encryptionResult = r
                            rhs = lhs
                            return addLayer()
                        }
                    }
                }
                return addLayer()
            }
        }.map(on: workQueue) { _ in (guardSnode, encryptionResult, targetSnodeSymmetricKey) }
    }

    // MARK: Internal API
    /// Sends an onion request to `snode`. Builds new paths as needed.
    internal static func invoke(_ method: LokiAPITarget.Method, on snode: LokiAPITarget, with parameters: JSON) -> Promise<Any> {
        let (promise, seal) = Promise<Any>.pending()
        workQueue.async {
            let payload: JSON = [ "method" : method.rawValue, "params" : parameters ]
            buildOnion(around: payload, targetedAt: snode).done(on: workQueue) { intermediate in
                let guardSnode = intermediate.guardSnode
                let url = "\(guardSnode.address):\(guardSnode.port)/onion_req"
                let finalEncryptionResult = intermediate.finalEncryptionResult
                let onion = finalEncryptionResult.ciphertext
                let parameters: JSON = [
                    "ciphertext" : onion.base64EncodedString(),
                    "ephemeral_key" : finalEncryptionResult.ephemeralPublicKey.toHexString()
                ]
                let targetSnodeSymmetricKey = intermediate.targetSnodeSymmetricKey
                HTTP.execute(.post, url, parameters: parameters).done(on: workQueue) { rawResponse in
                    guard let json = rawResponse as? JSON, let base64EncodedIVAndCiphertext = json["result"] as? String,
                        let ivAndCiphertext = Data(base64Encoded: base64EncodedIVAndCiphertext) else { return seal.reject(HTTP.Error.invalidJSON) }
                    let iv = ivAndCiphertext[0..<Int(ivSize)]
                    let ciphertext = ivAndCiphertext[Int(ivSize)...]
                    do {
                        let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagSize), mode: .combined)
                        let aes = try AES(key: targetSnodeSymmetricKey.bytes, blockMode: gcm, padding: .pkcs7)
                        let result = try aes.decrypt(ciphertext.bytes)
                        seal.fulfill(Data(bytes: result))
                    } catch (let error) {
                        seal.reject(error)
                    }
                }.catch(on: workQueue) { error in
                    seal.reject(error)
                }
            }.catch(on: workQueue) { error in
                seal.reject(error)
            }
        }
        return promise
    }
}
