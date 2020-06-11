import CryptoSwift
import PromiseKit

/// See the "Onion Requests" section of [The Session Whitepaper](https://arxiv.org/pdf/2002.04609.pdf) for more information.
public enum OnionRequestAPI {
    /// - Note: Must only be modified from `LokiAPI.workQueue`.
    public static var guardSnodes: Set<LokiAPITarget> = []
    /// - Note: Must only be modified from `LokiAPI.workQueue`.
    public static var paths: [Path] = [] // Not a set to ensure we consistently show the same path to the user

    private static var snodePool: Set<LokiAPITarget> {
        let unreliableSnodes = Set(LokiAPI.snodeFailureCount.keys)
        return LokiAPI.snodePool.subtracting(unreliableSnodes)
    }

    // MARK: Settings
    /// The number of snodes (including the guard snode) in a path.
    private static let pathSize: UInt = 3
    public static let pathCount: UInt = 2

    private static var guardSnodeCount: UInt { return pathCount } // One per path

    // MARK: Error
    internal enum Error : LocalizedError {
        case httpRequestFailedAtTargetSnode(statusCode: UInt, json: JSON)
        case insufficientSnodes
        case missingSnodeVersion
        case randomDataGenerationFailed
        case snodePublicKeySetMissing
        case unsupportedSnodeVersion(String)

        var errorDescription: String? {
            switch self {
            case .httpRequestFailedAtTargetSnode(let statusCode): return "HTTP request failed at target snode with status code: \(statusCode)."
            case .insufficientSnodes: return "Couldn't find enough snodes to build a path."
            case .missingSnodeVersion: return "Missing snode version."
            case .randomDataGenerationFailed: return "Couldn't generate random data."
            case .snodePublicKeySetMissing: return "Missing snode public key set."
            case .unsupportedSnodeVersion(let version): return "Unsupported snode version: \(version)."
            }
        }
    }

    // MARK: Path
    public typealias Path = [LokiAPITarget]

    // MARK: Onion Building Result
    private typealias OnionBuildingResult = (guardSnode: LokiAPITarget, finalEncryptionResult: EncryptionResult, targetSnodeSymmetricKey: Data)

    // MARK: Private API
    /// Tests the given snode. The returned promise errors out if the snode is faulty; the promise is fulfilled otherwise.
    private static func testSnode(_ snode: LokiAPITarget) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        let queue = DispatchQueue.global() // No need to block the work queue for this
        queue.async {
            let url = "\(snode.address):\(snode.port)/get_stats/v1"
            let timeout: TimeInterval = 3 // Use a shorter timeout for testing
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
            return LokiAPI.getRandomSnode().then(on: LokiAPI.workQueue) { _ -> Promise<Set<LokiAPITarget>> in // Just used to populate the snode pool
                var unusedSnodes = snodePool // Sync on LokiAPI.workQueue
                guard unusedSnodes.count >= guardSnodeCount else { throw Error.insufficientSnodes }
                func getGuardSnode() -> Promise<LokiAPITarget> {
                    // randomElement() uses the system's default random generator, which is cryptographically secure
                    guard let candidate = unusedSnodes.randomElement() else { return Promise<LokiAPITarget> { $0.reject(Error.insufficientSnodes) } }
                    unusedSnodes.remove(candidate) // All used snodes should be unique
                    print("[Loki] [Onion Request API] Testing guard snode: \(candidate).")
                    // Loop until a reliable guard snode is found
                    return testSnode(candidate).map(on: LokiAPI.workQueue) { candidate }.recover(on: LokiAPI.workQueue) { _ in getGuardSnode() }
                }
                let promises = (0..<guardSnodeCount).map { _ in getGuardSnode() }
                return when(fulfilled: promises).map(on: LokiAPI.workQueue) { guardSnodes in
                    let guardSnodesAsSet = Set(guardSnodes)
                    OnionRequestAPI.guardSnodes = guardSnodesAsSet
                    return guardSnodesAsSet
                }
            }
        }
    }

    /// Builds and returns `pathCount` paths. The returned promise errors out with `Error.insufficientSnodes`
    /// if not enough (reliable) snodes are available.
    private static func buildPaths() -> Promise<[Path]> {
        print("[Loki] [Onion Request API] Building onion request paths.")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .buildingPaths, object: nil)
        }
        return LokiAPI.getRandomSnode().then(on: LokiAPI.workQueue) { _ -> Promise<[Path]> in // Just used to populate the snode pool
            return getGuardSnodes().map(on: LokiAPI.workQueue) { guardSnodes -> [Path] in
                var unusedSnodes = snodePool.subtracting(guardSnodes)
                let pathSnodeCount = guardSnodeCount * pathSize - guardSnodeCount
                guard unusedSnodes.count >= pathSnodeCount else { throw Error.insufficientSnodes }
                // Don't test path snodes as this would reveal the user's IP to them
                return guardSnodes.map { guardSnode in
                    let result = [ guardSnode ] + (0..<(pathSize - 1)).map { _ in
                        // randomElement() uses the system's default random generator, which is cryptographically secure
                        let pathSnode = unusedSnodes.randomElement()! // Safe because of the pathSnodeCount check above
                        unusedSnodes.remove(pathSnode) // All used snodes should be unique
                        return pathSnode
                    }
                    print("[Loki] [Onion Request API] Built new onion request path: \(result.prettifiedDescription).")
                    return result
                }
            }.map(on: LokiAPI.workQueue) { paths in
                OnionRequestAPI.paths = paths
                // Dispatch async on the main queue to avoid nested write transactions
                DispatchQueue.main.async {
                    let storage = OWSPrimaryStorage.shared()
                    storage.dbReadWriteConnection.readWrite { transaction in
                        print("[Loki] Persisting onion request paths to database.")
                        storage.setOnionRequestPaths(paths, in: transaction)
                    }
                    NotificationCenter.default.post(name: .pathsBuilt, object: nil)
                }
                return paths
            }
        }
    }

    /// Returns a `Path` to be used for building an onion request. Builds new paths as needed.
    ///
    /// - Note: Exposed for testing purposes.
    internal static func getPath(excluding snode: LokiAPITarget) -> Promise<Path> {
        guard pathSize >= 1 else { preconditionFailure("Can't build path of size zero.") }
        if paths.count < pathCount {
            let storage = OWSPrimaryStorage.shared()
            storage.dbReadConnection.read { transaction in
                paths = storage.getOnionRequestPaths(in: transaction)
                if paths.count >= pathCount {
                    guardSnodes.formUnion([ paths[0][0], paths[1][0] ])
                }
            }
        }
        // randomElement() uses the system's default random generator, which is cryptographically secure
        if paths.count >= pathCount {
            return Promise<Path> { seal in
                seal.fulfill(paths.filter { !$0.contains(snode) }.randomElement()!)
            }
        } else {
            return buildPaths().map(on: LokiAPI.workQueue) { paths in
                return paths.filter { !$0.contains(snode) }.randomElement()!
            }
        }
    }

    private static func dropAllPaths() {
        paths.removeAll()
        // Dispatch async on the main queue to avoid nested write transactions
        DispatchQueue.main.async {
            let storage = OWSPrimaryStorage.shared()
            storage.dbReadWriteConnection.readWrite { transaction in
                storage.clearOnionRequestPaths(in: transaction)
            }
        }
    }

    private static func dropGuardSnode(_ snode: LokiAPITarget) {
        guardSnodes = guardSnodes.filter { $0 != snode }
    }

    /// Builds an onion around `payload` and returns the result.
    private static func buildOnion(around payload: JSON, targetedAt snode: LokiAPITarget) -> Promise<OnionBuildingResult> {
        var guardSnode: LokiAPITarget!
        var targetSnodeSymmetricKey: Data! // Needed by invoke(_:on:with:) to decrypt the response sent back by the target snode
        var encryptionResult: EncryptionResult!
        return getPath(excluding: snode).then(on: LokiAPI.workQueue) { path -> Promise<EncryptionResult> in
            guardSnode = path.first!
            // Encrypt in reverse order, i.e. the target snode first
            return encrypt(payload, forTargetSnode: snode).then(on: LokiAPI.workQueue) { r -> Promise<EncryptionResult> in
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
                        return OnionRequestAPI.encryptHop(from: lhs, to: rhs, using: encryptionResult).then(on: LokiAPI.workQueue) { r -> Promise<EncryptionResult> in
                            encryptionResult = r
                            rhs = lhs
                            return addLayer()
                        }
                    }
                }
                return addLayer()
            }
        }.map(on: LokiAPI.workQueue) { _ in (guardSnode, encryptionResult, targetSnodeSymmetricKey) }
    }

    // MARK: Internal API
    /// Sends an onion request to `snode`. Builds new paths as needed.
    internal static func sendOnionRequest(invoking method: LokiAPITarget.Method, on snode: LokiAPITarget, with parameters: JSON, associatedWith hexEncodedPublicKey: String) -> Promise<JSON> {
        let (promise, seal) = Promise<JSON>.pending()
        var guardSnode: LokiAPITarget!
        LokiAPI.workQueue.async {
            let payload: JSON = [ "method" : method.rawValue, "params" : parameters ]
            buildOnion(around: payload, targetedAt: snode).done(on: LokiAPI.workQueue) { intermediate in
                guardSnode = intermediate.guardSnode
                let url = "\(guardSnode.address):\(guardSnode.port)/onion_req"
                let finalEncryptionResult = intermediate.finalEncryptionResult
                let onion = finalEncryptionResult.ciphertext
                let parameters: JSON = [
                    "ciphertext" : onion.base64EncodedString(),
                    "ephemeral_key" : finalEncryptionResult.ephemeralPublicKey.toHexString()
                ]
                let targetSnodeSymmetricKey = intermediate.targetSnodeSymmetricKey
                HTTP.execute(.post, url, parameters: parameters).done(on: LokiAPI.workQueue) { rawResponse in
                    guard let json = rawResponse as? JSON, let base64EncodedIVAndCiphertext = json["result"] as? String,
                        let ivAndCiphertext = Data(base64Encoded: base64EncodedIVAndCiphertext) else { return seal.reject(HTTP.Error.invalidJSON) }
                    let iv = ivAndCiphertext[0..<Int(ivSize)]
                    let ciphertext = ivAndCiphertext[Int(ivSize)...]
                    do {
                        let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagSize), mode: .combined)
                        let aes = try AES(key: targetSnodeSymmetricKey.bytes, blockMode: gcm, padding: .noPadding)
                        let data = Data(try aes.decrypt(ciphertext.bytes))
                        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? JSON,
                            let bodyAsString = json["body"] as? String, let bodyAsData = bodyAsString.data(using: .utf8),
                            let body = try JSONSerialization.jsonObject(with: bodyAsData, options: []) as? JSON,
                            let statusCode = json["status"] as? Int else { return seal.reject(HTTP.Error.invalidJSON) }
                        guard 200...299 ~= statusCode else { return seal.reject(Error.httpRequestFailedAtTargetSnode(statusCode: UInt(statusCode), json: body)) }
                        seal.fulfill(body)
                    } catch (let error) {
                        seal.reject(error)
                    }
                }.catch(on: LokiAPI.workQueue) { error in
                    seal.reject(error)
                }
            }.catch(on: LokiAPI.workQueue) { error in
                seal.reject(error)
            }
        }
        promise.catch(on: LokiAPI.workQueue) { error in // Must be invoked on LokiAPI.workQueue
            guard case HTTP.Error.httpRequestFailed(_, _) = error else { return }
            dropAllPaths() // A snode in the path is bad; retry with a different path
            dropGuardSnode(guardSnode)
        }
        promise.handlingErrorsIfNeeded(forTargetSnode: snode, associatedWith: hexEncodedPublicKey)
        return promise
    }
}

// MARK: Target Snode Error Handling
private extension Promise where T == JSON {

    func handlingErrorsIfNeeded(forTargetSnode snode: LokiAPITarget, associatedWith hexEncodedPublicKey: String) -> Promise<JSON> {
        return recover(on: LokiAPI.errorHandlingQueue) { error -> Promise<JSON> in // Must be invoked on LokiAPI.errorHandlingQueue
            // The code below is very similar to that in LokiAPI.handlingSnodeErrorsIfNeeded(for:associatedWith:), but unfortunately slightly
            // different due to the fact that OnionRequestAPI uses the newer HTTP API, whereas LokiAPI still uses TSNetworkManager
            guard case OnionRequestAPI.Error.httpRequestFailedAtTargetSnode(let statusCode, let json) = error else { throw error }
            switch statusCode {
            case 0, 400, 500, 503:
                // The snode is unreachable
                let oldFailureCount = LokiAPI.snodeFailureCount[snode] ?? 0
                let newFailureCount = oldFailureCount + 1
                LokiAPI.snodeFailureCount[snode] = newFailureCount
                print("[Loki] Couldn't reach snode at: \(snode); setting failure count to \(newFailureCount).")
                if newFailureCount >= LokiAPI.snodeFailureThreshold {
                    print("[Loki] Failure threshold reached for: \(snode); dropping it.")
                    LokiAPI.dropSnodeFromSwarmIfNeeded(snode, hexEncodedPublicKey: hexEncodedPublicKey)
                    LokiAPI.dropSnodeFromSnodePool(snode)
                    LokiAPI.snodeFailureCount[snode] = 0
                }
            case 406:
                print("[Loki] The user's clock is out of sync with the service node network.")
                throw LokiAPI.LokiAPIError.clockOutOfSync
            case 421:
                // The snode isn't associated with the given public key anymore
                print("[Loki] Invalidating swarm for: \(hexEncodedPublicKey).")
                LokiAPI.dropSnodeFromSwarmIfNeeded(snode, hexEncodedPublicKey: hexEncodedPublicKey)
            case 432:
                // The proof of work difficulty is too low
                if let powDifficulty = json["difficulty"] as? Int {
                    print("[Loki] Setting proof of work difficulty to \(powDifficulty).")
                    LokiAPI.powDifficulty = UInt(powDifficulty)
                } else {
                    print("[Loki] Failed to update proof of work difficulty.")
                }
                break
            default: break
            }
            throw error
        }
    }
}
