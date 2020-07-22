import CryptoSwift
import PromiseKit

/// See the "Onion Requests" section of [The Session Whitepaper](https://arxiv.org/pdf/2002.04609.pdf) for more information.
public enum OnionRequestAPI {
    public static var guardSnodes: Set<Snode> = []
    public static var paths: [Path] = [] // Not a set to ensure we consistently show the same path to the user

    private static var snodePool: Set<Snode> {
        let unreliableSnodes = Set(SnodeAPI.snodeFailureCount.keys)
        return SnodeAPI.snodePool.subtracting(unreliableSnodes)
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

        internal var errorDescription: String? {
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
    public typealias Path = [Snode]

    // MARK: Onion Building Result
    private typealias OnionBuildingResult = (guardSnode: Snode, finalEncryptionResult: EncryptionResult, targetSnodeSymmetricKey: Data)

    // MARK: Private API
    /// Tests the given snode. The returned promise errors out if the snode is faulty; the promise is fulfilled otherwise.
    private static func testSnode(_ snode: Snode) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        DispatchQueue.global(qos: .userInitiated).async {
            let url = "\(snode.address):\(snode.port)/get_stats/v1"
            let timeout: TimeInterval = 3 // Use a shorter timeout for testing
            HTTP.execute(.get, url, timeout: timeout).done2 { rawResponse in
                guard let json = rawResponse as? JSON, let version = json["version"] as? String else { return seal.reject(Error.missingSnodeVersion) }
                if version >= "2.0.0" {
                    seal.fulfill(())
                } else {
                    print("[Loki] [Onion Request API] Unsupported snode version: \(version).")
                    seal.reject(Error.unsupportedSnodeVersion(version))
                }
            }.catch2 { error in
                seal.reject(error)
            }
        }
        return promise
    }

    /// Finds `guardSnodeCount` guard snodes to use for path building. The returned promise errors out with `Error.insufficientSnodes`
    /// if not enough (reliable) snodes are available.
    private static func getGuardSnodes() -> Promise<Set<Snode>> {
        if guardSnodes.count >= guardSnodeCount {
            return Promise<Set<Snode>> { $0.fulfill(guardSnodes) }
        } else {
            print("[Loki] [Onion Request API] Populating guard snode cache.")
            return SnodeAPI.getRandomSnode().then2 { _ -> Promise<Set<Snode>> in // Just used to populate the snode pool
                var unusedSnodes = snodePool // Sync on LokiAPI.workQueue
                guard unusedSnodes.count >= guardSnodeCount else { throw Error.insufficientSnodes }
                func getGuardSnode() -> Promise<Snode> {
                    // randomElement() uses the system's default random generator, which is cryptographically secure
                    guard let candidate = unusedSnodes.randomElement() else { return Promise<Snode> { $0.reject(Error.insufficientSnodes) } }
                    unusedSnodes.remove(candidate) // All used snodes should be unique
                    print("[Loki] [Onion Request API] Testing guard snode: \(candidate).")
                    // Loop until a reliable guard snode is found
                    return testSnode(candidate).map2 { candidate }.recover(on: DispatchQueue.main) { _ in
                        withDelay(0.25, completionQueue: SnodeAPI.workQueue) { getGuardSnode() }
                    }
                }
                let promises = (0..<guardSnodeCount).map { _ in getGuardSnode() }
                return when(fulfilled: promises).map2 { guardSnodes in
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
        return SnodeAPI.getRandomSnode().then2 { _ -> Promise<[Path]> in // Just used to populate the snode pool
            return getGuardSnodes().map2 { guardSnodes -> [Path] in
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
            }.map2 { paths in
                OnionRequestAPI.paths = paths
                try! Storage.writeSync { transaction in
                    print("[Loki] Persisting onion request paths to database.")
                    OWSPrimaryStorage.shared().setOnionRequestPaths(paths, in: transaction)
                }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .pathsBuilt, object: nil)
                }
                return paths
            }
        }
    }

    /// Returns a `Path` to be used for building an onion request. Builds new paths as needed.
    ///
    /// - Note: Exposed for testing purposes.
    internal static func getPath(excluding snode: Snode?) -> Promise<Path> {
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
                if let snode = snode {
                    seal.fulfill(paths.filter { !$0.contains(snode) }.randomElement()!)
                } else {
                    seal.fulfill(paths.randomElement()!)
                }
            }
        } else {
            return buildPaths().map2 { paths in
                if let snode = snode {
                    return paths.filter { !$0.contains(snode) }.randomElement()!
                } else {
                    return paths.randomElement()!
                }
            }
        }
    }

    private static func dropAllPaths() {
        paths.removeAll()
        try! Storage.writeSync { transaction in
            OWSPrimaryStorage.shared().clearOnionRequestPaths(in: transaction)
        }
    }

    private static func dropGuardSnode(_ snode: Snode) {
        guardSnodes = guardSnodes.filter { $0 != snode }
    }

    /// Builds an onion around `payload` and returns the result.
    private static func buildOnion(around payload: JSON, targetedAt snode: Snode?, to destination: JSON = [:], using x25519Key: String? = nil) -> Promise<OnionBuildingResult> {
        var guardSnode: Snode!
        var targetSnodeSymmetricKey: Data! // Needed by invoke(_:on:with:) to decrypt the response sent back by the target snode
        var encryptionResult: EncryptionResult!
        return getPath(excluding: snode).then2 { path -> Promise<EncryptionResult> in
            guardSnode = path.first!
            // Encrypt in reverse order, i.e. the target snode first
            var dest = destination
            var x25519PublicKey = x25519Key
            if let snode = snode {
                dest = [ "destination": snode.publicKeySet!.ed25519Key ]
                x25519PublicKey = snode.publicKeySet?.x25519Key
            }
            return encrypt(payload, using: x25519PublicKey, to: dest).then2 { r -> Promise<EncryptionResult> in
                targetSnodeSymmetricKey = r.symmetricKey
                // Recursively encrypt the layers of the onion (again in reverse order)
                encryptionResult = r
                var path = path
                var destination = dest
                func addLayer() -> Promise<EncryptionResult> {
                    if path.isEmpty {
                        return Promise<EncryptionResult> { $0.fulfill(encryptionResult) }
                    } else {
                        let lhs = path.removeLast()
                        let x25519Key = lhs.publicKeySet?.x25519Key
                        return OnionRequestAPI.encryptHop(with: x25519Key, to: destination, using: encryptionResult).then2 { r -> Promise<EncryptionResult> in
                            encryptionResult = r
                            destination = [ "destination": lhs.publicKeySet!.ed25519Key ]
                            return addLayer()
                        }
                    }
                }
                return addLayer()
            }
        }.map2 { _ in (guardSnode, encryptionResult, targetSnodeSymmetricKey) }
    }

    // MARK: Internal API
    internal static func getCanonicalHeaders(for request: NSURLRequest) -> [String:Any] {
        guard let headers = request.allHTTPHeaderFields else { return [:] }
        return headers.mapValues { value in
            switch value.lowercased() {
            case "true": return true
            case "false": return false
            default: return value
            }
        }
    }
    
    /// Sends an onion request to `snode`. Builds new paths as needed.
    internal static func sendOnionRequestSnodeDest(invoking method: Snode.Method, on snode: Snode, with parameters: JSON, associatedWith publicKey: String) -> Promise<JSON> {
        let payload: JSON = [ "method" : method.rawValue, "params" : parameters ]
        let promise = sendOnionRequest(on: snode, with: payload, to: [:], using: nil, associatedWith: publicKey)
        promise.recover2 { error -> Promise<JSON> in
            guard case OnionRequestAPI.Error.httpRequestFailedAtTargetSnode(let statusCode, let json) = error else { throw error }
            throw SnodeAPI.handleError(withStatusCode: statusCode, json: json, forSnode: snode, associatedWith: publicKey) ?? error
        }
        return promise
    }
    
    /// Sends an onion request to `file server`. Builds new paths as needed.
    internal static func sendOnionRequestLsrpcDest(_ request: NSURLRequest, server: String, using x25519Key: String, noJSON: Bool = false) -> Promise<JSON> {
        var headers = getCanonicalHeaders(for: request)
        let urlAsString = request.url!.absoluteString
        let serverURLEndIndex = urlAsString.range(of: server)!.upperBound
        var endpoint = ""
        if server.count < urlAsString.count {
            let endpointStartIndex = urlAsString.index(after: serverURLEndIndex)
            endpoint = String(urlAsString[endpointStartIndex..<urlAsString.endIndex])
        }
        let parametersAsString: String
        if let tsRequest = request as? TSRequest {
            headers["Content-Type"] = "application/json"
            let parametersAsData = try! JSONSerialization.data(withJSONObject: tsRequest.parameters, options: [ .fragmentsAllowed ])
            parametersAsString = !tsRequest.parameters.isEmpty ? String(bytes: parametersAsData, encoding: .utf8)! : "null"
        } else {
            headers["Content-Type"] = request.allHTTPHeaderFields!["Content-Type"]
            if let parametersAsInputStream = request.httpBodyStream, let parametersAsData = try? Data(from: parametersAsInputStream) {
                parametersAsString = "{ \"fileUpload\" : \"\(String(data: parametersAsData.base64EncodedData(), encoding: .utf8) ?? "null")\" }"
            } else {
                parametersAsString = "null"
            }
        }
        let payload: JSON = [
            "body" : parametersAsString,
            "endpoint": endpoint,
            "method" : request.httpMethod,
            "headers" : headers
        ]
        let destination: JSON = [ "host"    : request.url?.host,
                                  "target"  : "/loki/v1/lsrpc",
                                  "method"  : "POST"]
        let promise = sendOnionRequest(on: nil, with: payload, to: destination, using: x25519Key, associatedWith: getUserHexEncodedPublicKey(), noJSON: noJSON)
        promise.recover2{ error -> Promise<JSON> in
            // TODO: File Server API handle Error
            throw error
        }
        return promise
    }
    
    internal static func sendOnionRequest(on snode: Snode?, with payload: JSON, to destination: JSON, using x25519Key: String?, associatedWith publicKey: String, noJSON: Bool = false) -> Promise<JSON> {
        let (promise, seal) = Promise<JSON>.pending()
        var guardSnode: Snode!
        DispatchQueue.global(qos: .userInitiated).async {
            buildOnion(around: payload, targetedAt: snode, to: destination, using: x25519Key).done2 { intermediate in
                guardSnode = intermediate.guardSnode
                let url = "\(guardSnode.address):\(guardSnode.port)/onion_req"
                let finalEncryptionResult = intermediate.finalEncryptionResult
                let onion = finalEncryptionResult.ciphertext
                let parameters: JSON = [
                    "ciphertext" : onion.base64EncodedString(),
                    "ephemeral_key" : finalEncryptionResult.ephemeralPublicKey.toHexString()
                ]
                let targetSnodeSymmetricKey = intermediate.targetSnodeSymmetricKey
                HTTP.execute(.post, url, parameters: parameters).done2 { rawResponse in
                    guard let json = rawResponse as? JSON, let base64EncodedIVAndCiphertext = json["result"] as? String,
                        let ivAndCiphertext = Data(base64Encoded: base64EncodedIVAndCiphertext) else { return seal.reject(HTTP.Error.invalidJSON) }
                    let iv = ivAndCiphertext[0..<Int(ivSize)]
                    let ciphertext = ivAndCiphertext[Int(ivSize)...]
                    do {
                        let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagSize), mode: .combined)
                        let aes = try AES(key: targetSnodeSymmetricKey.bytes, blockMode: gcm, padding: .noPadding)
                        let data = Data(try aes.decrypt(ciphertext.bytes))
                        guard let json = try JSONSerialization.jsonObject(with: data, options: [ .fragmentsAllowed ]) as? JSON,
                            let bodyAsString = json["body"] as? String, let statusCode = json["status"] as? Int else { return seal.reject(HTTP.Error.invalidJSON) }
                        if statusCode == 406 { // Clock out of sync
                            print("[Loki] The user's clock is out of sync with the service node network.")
                            seal.reject(SnodeAPI.SnodeAPIError.clockOutOfSync)
                        } else {
                            
                            if noJSON {
                                let body = ["body": bodyAsString]
                                guard 200...299 ~= statusCode else { return seal.reject(Error.httpRequestFailedAtTargetSnode(statusCode: UInt(statusCode), json: body)) }
                                seal.fulfill(body)
                                
                            } else {
                                guard let bodyAsData = bodyAsString.data(using: .utf8),
                                let body = try JSONSerialization.jsonObject(with: bodyAsData, options: [ .fragmentsAllowed ]) as? JSON else { return seal.reject(HTTP.Error.invalidJSON) }
                                guard 200...299 ~= statusCode else { return seal.reject(Error.httpRequestFailedAtTargetSnode(statusCode: UInt(statusCode), json: body)) }
                                seal.fulfill(body)
                            }
                        }
                    } catch (let error) {
                        seal.reject(error)
                    }
                }.catch2 { error in
                    seal.reject(error)
                }
            }.catch2 { error in
                seal.reject(error)
            }
        }
        promise.catch2 { error in // Must be invoked on LokiAPI.workQueue
            guard case HTTP.Error.httpRequestFailed(_, _) = error else { return }
            dropAllPaths() // A snode in the path is bad; retry with a different path
            dropGuardSnode(guardSnode)
        }
        return promise
    }
}
