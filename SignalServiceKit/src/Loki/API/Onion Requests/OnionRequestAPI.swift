import CryptoSwift
import PromiseKit

// TODO: Test path snodes as well

/// See the "Onion Requests" section of [The Session Whitepaper](https://arxiv.org/pdf/2002.04609.pdf) for more information.
internal enum OnionRequestAPI {
    private static let urlSession = URLSession(configuration: .ephemeral, delegate: urlSessionDelegate, delegateQueue: nil)
    private static let urlSessionDelegate = URLSessionDelegateImplementation()

    internal static var guardSnodes: Set<LokiAPITarget> = []
    internal static var paths: Set<Path> = []
    /// - Note: Exposed for testing purposes.
    internal static let workQueue = DispatchQueue(label: "OnionRequestAPI.workQueue", qos: .userInitiated)

    // MARK: Settings
    private static let pathCount: UInt = 3
    /// The number of snodes (including the guard snode) in a path.
    private static let pathSize: UInt = 3
    private static let timeout: TimeInterval = 20

    private static var guardSnodeCount: UInt { return pathCount } // One per path

    // MARK: HTTP Verb
    private enum HTTPVerb : String {
        case get = "GET"
        case put = "PUT"
        case post = "POST"
        case delete = "DELETE"
    }

    // MARK: URL Session Delegate Implementation
    private final class URLSessionDelegateImplementation : NSObject, URLSessionDelegate {

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // Snode to snode communication uses self-signed certificates but clients can safely ignore this
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        }
    }

    // MARK: Error
    internal enum Error : LocalizedError {
        case generic
        case httpRequestFailed(statusCode: UInt, json: JSON?)
        case insufficientSnodes
        case invalidJSON
        case missingSnodeVersion
        case randomDataGenerationFailed
        case snodePublicKeySetMissing
        case unsupportedSnodeVersion(String)

        var errorDescription: String? {
            switch self {
            case .generic: return "An error occurred."
            case .httpRequestFailed(let statusCode, _): return "HTTP request failed with status code: \(statusCode)."
            case .insufficientSnodes: return "Couldn't find enough snodes to build a path."
            case .invalidJSON: return "Invalid JSON."
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
    private typealias OnionBuildingResult = (guardSnode: LokiAPITarget, encryptionResult: EncryptionResult, symmetricKey: Data)

    // MARK: Private API
    private static func execute(_ verb: HTTPVerb, _ url: String, parameters: JSON? = nil, timeout: TimeInterval = OnionRequestAPI.timeout) -> Promise<Any> {
        return Promise<Any> { seal in
            let url = URL(string: url)!
            var request = URLRequest(url: url)
            request.httpMethod = verb.rawValue
            if let parameters = parameters {
                do {
                    guard JSONSerialization.isValidJSONObject(parameters) else { return seal.reject(Error.invalidJSON) }
                    request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
                } catch (let error) {
                    return seal.reject(error)
                }
            }
            request.timeoutInterval = timeout
            let task = urlSession.dataTask(with: request) { data, response, error in
                guard let data = data, let response = response as? HTTPURLResponse else {
                    print("[Loki] [Onion Request API] \(verb.rawValue) request to \(url) failed.")
                    return seal.reject(Error.generic)
                }
                if let error = error {
                    print("[Loki] [Onion Request API] \(verb.rawValue) request to \(url) failed due to error: \(error).")
                    return seal.reject(error)
                }
                let statusCode = UInt(response.statusCode)
                guard 200...299 ~= statusCode else {
                    var json: JSON? = nil
                    if let j = try? JSONSerialization.jsonObject(with: data, options: []) as? JSON {
                        json = j
                    } else if let result = String(data: data, encoding: .utf8) {
                        json = [ "result" : result ]
                    }
                    let jsonDescription = json?.prettifiedDescription ?? "no debugging info provided"
                    print("[Loki] [Onion Request API] \(verb.rawValue) request to \(url) failed with status code: \(statusCode) (\(jsonDescription)).")
                    return seal.reject(Error.httpRequestFailed(statusCode: statusCode, json: json))
                }
                var json: JSON! = nil
                if let j = try? JSONSerialization.jsonObject(with: data, options: []) as? JSON {
                    json = j
                } else if let result = String(data: data, encoding: .utf8) {
                    json = [ "result" : result ]
                } else {
                    print("[Loki] [Onion Request API] Couldn't parse JSON returned by \(verb.rawValue) request to \(url).")
                    return seal.reject(Error.invalidJSON)
                }
                seal.fulfill(json!)
            }
            task.resume()
        }
    }

    /// Tests the given snode. The returned promise errors out if the snode is faulty; the promise is fulfilled otherwise.
    private static func testSnode(_ snode: LokiAPITarget) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        let queue = DispatchQueue(label: UUID().uuidString, qos: .userInitiated) // No need to block the work queue for this
        queue.async {
            print("[Loki] [Onion Request API] Testing snode: \(snode).")
            let url = "\(snode.address):\(snode.port)/get_stats/v1"
            let timeout: TimeInterval = 10 // Use a shorter timeout for testing
            execute(.get, url, timeout: timeout).done(on: queue) { rawResponse in
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
                    // Loop until a reliable guard snode is found
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
                    let result = [ guardSnode ] + (0..<(pathSize - 1)).map { _ in unusedSnodes.randomElement()! }
                    print("[Loki] [Onion Request API] Built new onion request path: \(result.prettifiedDescription).")
                    return result
                })
                return result
            }
        }
    }

    /// Returns a `Path` to be used for building an onion request. Builds new paths as needed.
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
    private static func buildOnion(around payload: Data, targetedAt snode: LokiAPITarget) -> Promise<OnionBuildingResult> {
        var guardSnode: LokiAPITarget!
        var encryptionResult: EncryptionResult!
        var symmetricKey: Data!
        return getPath().then(on: workQueue) { path -> Promise<EncryptionResult> in
            guardSnode = path.first!
            return encrypt(payload, forTargetSnode: snode).then(on: workQueue) { r -> Promise<EncryptionResult> in
                encryptionResult = r
                symmetricKey = r.symmetricKey
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
        }.map(on: workQueue) { _ in (guardSnode: guardSnode, encryptionResult: encryptionResult, symmetricKey: symmetricKey) }
    }

    // MARK: Internal API
    /// Sends an onion request to `snode`. Builds new paths as needed.
    internal static func invoke(_ method: LokiAPITarget.Method, on snode: LokiAPITarget, parameters: JSON) -> Promise<Any> {
        let (promise, seal) = Promise<Any>.pending()
        workQueue.async {
            let parameters: JSON = [ "method" : method.rawValue, "params" : parameters ]
            let payload: Data
            do {
                guard JSONSerialization.isValidJSONObject(parameters) else { return seal.reject(Error.invalidJSON) }
                payload = try JSONSerialization.data(withJSONObject: parameters, options: [])
            } catch (let error) {
                return seal.reject(error)
            }
            buildOnion(around: payload, targetedAt: snode).done(on: workQueue) { intermediate in
                let guardSnode = intermediate.guardSnode
                let url = "\(guardSnode.address):\(guardSnode.port)/onion_req"
                let encryptionResult = intermediate.encryptionResult
                let onion = encryptionResult.ciphertext
                let symmetricKey = intermediate.symmetricKey
                let parameters: JSON = [
                    "ciphertext" : onion.base64EncodedString(),
                    "ephemeral_key" : encryptionResult.ephemeralPublicKey.toHexString()
                ]
                execute(.post, url, parameters: parameters).done(on: workQueue) { rawResponse in
                    guard let json = rawResponse as? JSON, let base64EncodedIVAndCiphertext = json["result"] as? String,
                        let ivAndCiphertext = Data(base64Encoded: base64EncodedIVAndCiphertext) else { return seal.reject(Error.invalidJSON) }
                    let iv = ivAndCiphertext[0..<Int(ivSize)]
                    let ciphertext = ivAndCiphertext[Int(ivSize)..<ivAndCiphertext.endIndex]
                    do {
                        let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagLength), mode: .combined)
                        let aes = try AES(key: symmetricKey.bytes, blockMode: gcm, padding: .pkcs7)
                        let result = try aes.decrypt(ciphertext.bytes)
                        seal.fulfill(result)
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
