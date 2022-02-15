import Foundation
import CryptoSwift
import PromiseKit
import SessionUtilitiesKit

public protocol OnionRequestAPIType {
    static func sendOnionRequest(to snode: Snode, invoking method: Snode.Method, with parameters: JSON, using version: OnionRequestAPI.Version, associatedWith publicKey: String?) -> Promise<Data>
    static func sendOnionRequest(_ request: URLRequest, to server: String, using version: OnionRequestAPI.Version, with x25519PublicKey: String) -> Promise<(OnionRequestResponseInfoType, Data?)>
}

public extension OnionRequestAPIType {
    static func sendOnionRequest(to snode: Snode, invoking method: Snode.Method, with parameters: JSON, using version: OnionRequestAPI.Version = .v3) -> Promise<Data> {
        return sendOnionRequest(to: snode, invoking: method, with: parameters, using: version, associatedWith: nil)
    }
    
    static func sendOnionRequest(_ request: URLRequest, to server: String, with x25519PublicKey: String) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        sendOnionRequest(request, to: server, using: .v4, with: x25519PublicKey)
    }
}

/// See the "Onion Requests" section of [The Session Whitepaper](https://arxiv.org/pdf/2002.04609.pdf) for more information.
public enum OnionRequestAPI: OnionRequestAPIType {
    private static var buildPathsPromise: Promise<[Path]>? = nil
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    private static var pathFailureCount: [Path:UInt] = [:]
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    private static var snodeFailureCount: [Snode:UInt] = [:]
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    public static var guardSnodes: Set<Snode> = []
    public static var paths: [Path] = [] // Not a set to ensure we consistently show the same path to the user

    // MARK: Settings
    public static let maxRequestSize = 10_000_000 // 10 MB
    /// The number of snodes (including the guard snode) in a path.
    private static let pathSize: UInt = 3
    /// The number of times a path can fail before it's replaced.
    private static let pathFailureThreshold: UInt = 3
    /// The number of times a snode can fail before it's replaced.
    private static let snodeFailureThreshold: UInt = 3
    /// The number of paths to maintain.
    public static let targetPathCount: UInt = 2

    /// The number of guard snodes required to maintain `targetPathCount` paths.
    private static var targetGuardSnodeCount: UInt { return targetPathCount } // One per path


    // MARK: Path
    public typealias Path = [Snode]

    // MARK: Onion Building Result
    private typealias OnionBuildingResult = (guardSnode: Snode, finalEncryptionResult: AESGCM.EncryptionResult, destinationSymmetricKey: Data)

    // MARK: Private API
    /// Tests the given snode. The returned promise errors out if the snode is faulty; the promise is fulfilled otherwise.
    private static func testSnode(_ snode: Snode) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        DispatchQueue.global(qos: .userInitiated).async {
            let url = "\(snode.address):\(snode.port)/get_stats/v1"
            let timeout: TimeInterval = 3 // Use a shorter timeout for testing
            HTTP.execute(.get, url, timeout: timeout).done2 { json in
                guard let version = json["version"] as? String else { return seal.reject(Error.missingSnodeVersion) }
                if version >= "2.0.7" {
                    seal.fulfill(())
                } else {
                    SNLog("Unsupported snode version: \(version).")
                    seal.reject(Error.unsupportedSnodeVersion(version))
                }
            }.catch2 { error in
                seal.reject(error)
            }
        }
        return promise
    }

    /// Finds `targetGuardSnodeCount` guard snodes to use for path building. The returned promise errors out with `Error.insufficientSnodes`
    /// if not enough (reliable) snodes are available.
    private static func getGuardSnodes(reusing reusableGuardSnodes: [Snode]) -> Promise<Set<Snode>> {
        if guardSnodes.count >= targetGuardSnodeCount {
            return Promise<Set<Snode>> { $0.fulfill(guardSnodes) }
        } else {
            SNLog("Populating guard snode cache.")
            var unusedSnodes = SnodeAPI.snodePool.subtracting(reusableGuardSnodes) // Sync on LokiAPI.workQueue
            let reusableGuardSnodeCount = UInt(reusableGuardSnodes.count)
            guard unusedSnodes.count >= (targetGuardSnodeCount - reusableGuardSnodeCount) else { return Promise(error: Error.insufficientSnodes) }
            func getGuardSnode() -> Promise<Snode> {
                // randomElement() uses the system's default random generator, which is cryptographically secure
                guard let candidate = unusedSnodes.randomElement() else { return Promise<Snode> { $0.reject(Error.insufficientSnodes) } }
                unusedSnodes.remove(candidate) // All used snodes should be unique
                SNLog("Testing guard snode: \(candidate).")
                // Loop until a reliable guard snode is found
                return testSnode(candidate).map2 { candidate }.recover(on: DispatchQueue.main) { _ in
                    withDelay(0.1, completionQueue: Threading.workQueue) { getGuardSnode() }
                }
            }
            let promises = (0..<(targetGuardSnodeCount - reusableGuardSnodeCount)).map { _ in getGuardSnode() }
            return when(fulfilled: promises).map2 { guardSnodes in
                let guardSnodesAsSet = Set(guardSnodes + reusableGuardSnodes)
                OnionRequestAPI.guardSnodes = guardSnodesAsSet
                return guardSnodesAsSet
            }
        }
    }

    /// Builds and returns `targetPathCount` paths. The returned promise errors out with `Error.insufficientSnodes`
    /// if not enough (reliable) snodes are available.
    @discardableResult
    private static func buildPaths(reusing reusablePaths: [Path]) -> Promise<[Path]> {
        if let existingBuildPathsPromise = buildPathsPromise { return existingBuildPathsPromise }
        SNLog("Building onion request paths.")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .buildingPaths, object: nil)
        }
        let reusableGuardSnodes = reusablePaths.map { $0[0] }
        let promise: Promise<[Path]> = getGuardSnodes(reusing: reusableGuardSnodes).map2 { guardSnodes -> [Path] in
            var unusedSnodes = SnodeAPI.snodePool.subtracting(guardSnodes).subtracting(reusablePaths.flatMap { $0 })
            let reusableGuardSnodeCount = UInt(reusableGuardSnodes.count)
            let pathSnodeCount = (targetGuardSnodeCount - reusableGuardSnodeCount) * pathSize - (targetGuardSnodeCount - reusableGuardSnodeCount)
            guard unusedSnodes.count >= pathSnodeCount else { throw Error.insufficientSnodes }
            // Don't test path snodes as this would reveal the user's IP to them
            return guardSnodes.subtracting(reusableGuardSnodes).map { guardSnode in
                let result = [ guardSnode ] + (0..<(pathSize - 1)).map { _ in
                    // randomElement() uses the system's default random generator, which is cryptographically secure
                    let pathSnode = unusedSnodes.randomElement()! // Safe because of the pathSnodeCount check above
                    unusedSnodes.remove(pathSnode) // All used snodes should be unique
                    return pathSnode
                }
                SNLog("Built new onion request path: \(result.prettifiedDescription).")
                return result
            }
        }.map2 { paths in
            OnionRequestAPI.paths = paths + reusablePaths
            SNSnodeKitConfiguration.shared.storage.writeSync { transaction in
                SNLog("Persisting onion request paths to database.")
                SNSnodeKitConfiguration.shared.storage.setOnionRequestPaths(to: paths, using: transaction)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pathsBuilt, object: nil)
            }
            return paths
        }
        promise.done2 { _ in buildPathsPromise = nil }
        promise.catch2 { _ in buildPathsPromise = nil }
        buildPathsPromise = promise
        return promise
    }

    /// Returns a `Path` to be used for building an onion request. Builds new paths as needed.
    private static func getPath(excluding snode: Snode?) -> Promise<Path> {
        guard pathSize >= 1 else { preconditionFailure("Can't build path of size zero.") }
        var paths = OnionRequestAPI.paths
        if paths.isEmpty {
            paths = SNSnodeKitConfiguration.shared.storage.getOnionRequestPaths()
            OnionRequestAPI.paths = paths
            if !paths.isEmpty {
                guardSnodes.formUnion([ paths[0][0] ])
                if paths.count >= 2 {
                    guardSnodes.formUnion([ paths[1][0] ])
                }
            }
        }
        // randomElement() uses the system's default random generator, which is cryptographically secure
        if paths.count >= targetPathCount {
            if let snode = snode {
                return Promise { $0.fulfill(paths.filter { !$0.contains(snode) }.randomElement()!) }
            } else {
                return Promise { $0.fulfill(paths.randomElement()!) }
            }
        } else if !paths.isEmpty {
            if let snode = snode {
                if let path = paths.first(where: { !$0.contains(snode) }) {
                    buildPaths(reusing: paths) // Re-build paths in the background
                    return Promise { $0.fulfill(path) }
                } else {
                    return buildPaths(reusing: paths).map2 { paths in
                        return paths.filter { !$0.contains(snode) }.randomElement()!
                    }
                }
            } else {
                buildPaths(reusing: paths) // Re-build paths in the background
                return Promise { $0.fulfill(paths.randomElement()!) }
            }
        } else {
            return buildPaths(reusing: []).map2 { paths in
                if let snode = snode {
                    return paths.filter { !$0.contains(snode) }.randomElement()!
                } else {
                    return paths.randomElement()!
                }
            }
        }
    }

    private static func dropGuardSnode(_ snode: Snode) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        guardSnodes = guardSnodes.filter { $0 != snode }
    }

    private static func drop(_ snode: Snode) throws {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        // We repair the path here because we can do it sync. In the case where we drop a whole
        // path we leave the re-building up to getPath(excluding:) because re-building the path
        // in that case is async.
        OnionRequestAPI.snodeFailureCount[snode] = 0
        var oldPaths = paths
        guard let pathIndex = oldPaths.firstIndex(where: { $0.contains(snode) }) else { return }
        var path = oldPaths[pathIndex]
        guard let snodeIndex = path.firstIndex(of: snode) else { return }
        path.remove(at: snodeIndex)
        let unusedSnodes = SnodeAPI.snodePool.subtracting(oldPaths.flatMap { $0 })
        guard !unusedSnodes.isEmpty else { throw Error.insufficientSnodes }
        // randomElement() uses the system's default random generator, which is cryptographically secure
        path.append(unusedSnodes.randomElement()!)
        // Don't test the new snode as this would reveal the user's IP
        oldPaths.remove(at: pathIndex)
        let newPaths = oldPaths + [ path ]
        paths = newPaths
        SNSnodeKitConfiguration.shared.storage.writeSync { transaction in
            SNLog("Persisting onion request paths to database.")
            SNSnodeKitConfiguration.shared.storage.setOnionRequestPaths(to: newPaths, using: transaction)
        }
    }

    private static func drop(_ path: Path) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        OnionRequestAPI.pathFailureCount[path] = 0
        var paths = OnionRequestAPI.paths
        guard let pathIndex = paths.firstIndex(of: path) else { return }
        paths.remove(at: pathIndex)
        OnionRequestAPI.paths = paths
        SNSnodeKitConfiguration.shared.storage.writeSync { transaction in
            if !paths.isEmpty {
                SNLog("Persisting onion request paths to database.")
                SNSnodeKitConfiguration.shared.storage.setOnionRequestPaths(to: paths, using: transaction)
            } else {
                SNLog("Clearing onion request paths.")
                SNSnodeKitConfiguration.shared.storage.setOnionRequestPaths(to: [], using: transaction)
            }
        }
    }

    /// Builds an onion around `payload` and returns the result.
    private static func buildOnion(around payload: String, targetedAt destination: Destination) -> Promise<OnionBuildingResult> {
        var guardSnode: Snode!
        var targetSnodeSymmetricKey: Data! // Needed by invoke(_:on:with:) to decrypt the response sent back by the destination
        var encryptionResult: AESGCM.EncryptionResult!
        var snodeToExclude: Snode?
        if case .snode(let snode) = destination { snodeToExclude = snode }
        return getPath(excluding: snodeToExclude).then2 { path -> Promise<AESGCM.EncryptionResult> in
            guardSnode = path.first!
            // Encrypt in reverse order, i.e. the destination first
            return encrypt(payload, for: destination).then2 { r -> Promise<AESGCM.EncryptionResult> in
                targetSnodeSymmetricKey = r.symmetricKey
                // Recursively encrypt the layers of the onion (again in reverse order)
                encryptionResult = r
                var path = path
                var rhs = destination
                func addLayer() -> Promise<AESGCM.EncryptionResult> {
                    if path.isEmpty {
                        return Promise<AESGCM.EncryptionResult> { $0.fulfill(encryptionResult) }
                    } else {
                        let lhs = Destination.snode(path.removeLast())
                        return OnionRequestAPI.encryptHop(from: lhs, to: rhs, using: encryptionResult).then2 { r -> Promise<AESGCM.EncryptionResult> in
                            encryptionResult = r
                            rhs = lhs
                            return addLayer()
                        }
                    }
                }
                return addLayer()
            }
        }.map2 { _ in (guardSnode, encryptionResult, targetSnodeSymmetricKey) }
    }

    // MARK: - Public API
    
    /// Sends an onion request to `snode`. Builds new paths as needed.
    public static func sendOnionRequest(to snode: Snode, invoking method: Snode.Method, with parameters: JSON, using version: Version = .v3, associatedWith publicKey: String? = nil) -> Promise<Data> {
        let payloadJson: JSON = [ "method": method.rawValue, "params": parameters ]
        
        guard let jsonData: Data = try? JSONSerialization.data(withJSONObject: payloadJson, options: []), let payload: String = String(data: jsonData, encoding: .utf8) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        return sendOnionRequest(with: payload, to: Destination.snode(snode), version: version)
            .map { _, maybeData in
                guard let data: Data = maybeData else { throw HTTP.Error.invalidResponse }
                
                return data
            }
            .recover2 { error -> Promise<Data> in
                guard case OnionRequestAPI.Error.httpRequestFailedAtDestination(let statusCode, let json, _) = error else {
                    throw error
                }
                
                throw SnodeAPI.handleError(withStatusCode: statusCode, json: json, forSnode: snode, associatedWith: publicKey) ?? error
            }
    }

    /// Sends an onion request to `server`. Builds new paths as needed.
    public static func sendOnionRequest(_ request: URLRequest, to server: String, using version: Version = .v4, with x25519PublicKey: String) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        guard version != .v4 || server == "https://chat.lokinet.dev" else {  // TODO: Remove this
            return sendOnionRequest(request, to: server, using: .v3, with: x25519PublicKey)
        }
        guard let url = request.url, let host = request.url?.host else { return Promise(error: Error.invalidURL) }
        
        let scheme: String? = url.scheme
        let port: UInt16? = url.port.map { UInt16($0) }
        
        guard let payload: String = generatePayload(for: request, with: version) else {
            return Promise(error: Error.invalidRequestInfo)
        }
        
        let destination = Destination.server(host: host, target: version.rawValue, x25519PublicKey: x25519PublicKey, scheme: scheme, port: port)
        let promise = sendOnionRequest(with: payload, to: destination, version: version)
        promise.catch2 { error in
            SNLog("Couldn't reach server: \(url) due to error: \(error).")
        }
        return promise
    }

    public static func sendOnionRequest(with payload: String, to destination: Destination, version: Version) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        let (promise, seal) = Promise<(OnionRequestResponseInfoType, Data?)>.pending()
        var guardSnode: Snode?
        Threading.workQueue.async { // Avoid race conditions on `guardSnodes` and `paths`
            buildOnion(around: payload, targetedAt: destination).done2 { intermediate in
                guardSnode = intermediate.guardSnode
                let url = "\(guardSnode!.address):\(guardSnode!.port)/onion_req/v2"
                let finalEncryptionResult = intermediate.finalEncryptionResult
                let onion = finalEncryptionResult.ciphertext
                if case Destination.server = destination, Double(onion.count) > 0.75 * Double(maxRequestSize) {
                    SNLog("Approaching request size limit: ~\(onion.count) bytes.")
                }
                let parameters: JSON = [
                    "ephemeral_key" : finalEncryptionResult.ephemeralPublicKey.toHexString()
                ]
                let body: Data
                do {
                    body = try encode(ciphertext: onion, json: parameters)
                } catch {
                    return seal.reject(error)
                }
                let destinationSymmetricKey = intermediate.destinationSymmetricKey
                
                HTTP.updatedExecute(.post, url, body: body)
                    .done2 { responseData in
                        handleResponse(
                            responseData: responseData,
                            destinationSymmetricKey: destinationSymmetricKey,
                            version: version,
                            destination: destination,
                            seal: seal
                        )
                    }
                    .catch2 { error in
                        seal.reject(error)
                    }
            }.catch2 { error in
                seal.reject(error)
            }
        }
        
        promise.catch2 { error in // Must be invoked on Threading.workQueue
            guard case HTTP.Error.httpRequestFailed(let statusCode, let json) = error, let guardSnode = guardSnode else {
                return
            }
            
            let path = paths.first { $0.contains(guardSnode) }
            
            func handleUnspecificError() {
                guard let path = path else { return }
                
                var pathFailureCount = OnionRequestAPI.pathFailureCount[path] ?? 0
                pathFailureCount += 1
                
                if pathFailureCount >= pathFailureThreshold {
                    dropGuardSnode(guardSnode)
                    path.forEach { snode in
                        SnodeAPI.handleError(withStatusCode: statusCode, json: json, forSnode: snode) // Intentionally don't throw
                    }
                    
                    drop(path)
                }
                else {
                    OnionRequestAPI.pathFailureCount[path] = pathFailureCount
                }
            }
            
            let prefix = "Next node not found: "
            
            if let message = json?["result"] as? String, message.hasPrefix(prefix) {
                let ed25519PublicKey = message[message.index(message.startIndex, offsetBy: prefix.count)..<message.endIndex]
                
                if let path = path, let snode = path.first(where: { $0.publicKeySet.ed25519Key == ed25519PublicKey }) {
                    var snodeFailureCount = OnionRequestAPI.snodeFailureCount[snode] ?? 0
                    snodeFailureCount += 1
                    
                    if snodeFailureCount >= snodeFailureThreshold {
                        SnodeAPI.handleError(withStatusCode: statusCode, json: json, forSnode: snode) // Intentionally don't throw
                        do {
                            try drop(snode)
                        }
                        catch {
                            handleUnspecificError()
                        }
                    }
                    else {
                        OnionRequestAPI.snodeFailureCount[snode] = snodeFailureCount
                    }
                } else {
                    // Do nothing
                }
            }
            else if let message = json?["result"] as? String, message == "Loki Server error" {
                // Do nothing
            }
            else if case .server(let host, _, _, _, _) = destination, host == "116.203.70.33" && statusCode == 0 {
                // FIXME: Temporary thing to kick out nodes that can't talk to the V2 OGS yet
                handleUnspecificError()
            }
            else if statusCode == 0 { // Timeout
                // Do nothing
            }
            else {
                handleUnspecificError()
            }
        }
        
        return promise
    }
    
    // MARK: - Version Handling
    
    private static func generatePayload(for request: URLRequest, with version: Version) -> String? {
        guard let url = request.url else { return nil }
        
        switch version {
            // V2 and V3 Onion Requests have the same structure
            case .v2, .v3:
                var rawHeaders = request.allHTTPHeaderFields ?? [:]
                rawHeaders.removeValue(forKey: "User-Agent")
                var headers: JSON = rawHeaders.mapValues { value in
                    switch value.lowercased() {
                        case "true": return true
                        case "false": return false
                        default: return value
                    }
                }
                
                var endpoint = url.path.removingPrefix("/")
                if let query = url.query { endpoint += "?\(query)" }
                let bodyAsString: String
                
                if let body: Data = request.httpBody {
                    headers["Content-Type"] = "application/json"    // Assume data is JSON
                    bodyAsString = (String(data: body, encoding: .utf8) ?? "null")
                }
                else if let inputStream: InputStream = request.httpBodyStream, let body: Data = try? Data(from: inputStream) {
                    headers["Content-Type"] = request.allHTTPHeaderFields!["Content-Type"]
                    bodyAsString = "{ \"fileUpload\" : \"\(String(data: body.base64EncodedData(), encoding: .utf8) ?? "null")\" }"
                }
                else {
                    bodyAsString = "null"
                }
                
                let payload: JSON = [
                    "body" : bodyAsString,
                    "endpoint" : endpoint,
                    "method" : request.httpMethod!,
                    "headers" : headers
                ]
                
                guard let jsonData: Data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return nil }
                
                return String(data: jsonData, encoding: .utf8)
                
            // V4 Onion Requests have a very different structure
            case .v4:
                // Note: We need to remove the leading forward slash unless we are explicitly hitting a legacy
                // endpoint (in which case we need it to ensure the request signing works correctly
                // TODO: Confirm the 'removingPrefix' isn't going to break the request signing on non-legacy endpoints
                let endpoint: String = url.path
                    .appending(url.query.map { value in "?\(value)" })
                
                let requestInfo: RequestInfo = RequestInfo(
                    method: (request.httpMethod ?? "GET"),   // Default (if nil) is 'GET'
                    endpoint: endpoint,
                    headers: (request.allHTTPHeaderFields ?? [:])
                        .setting(
                            "Content-Type",
                            // TODO: Determine what 'Content-Type' 'httpBodyStream' should have???.
                            (request.httpBody == nil && request.httpBodyStream == nil ? nil :
                                ((request.allHTTPHeaderFields ?? [:])["Content-Type"] ?? "application/json")    // Default to JSON if not defined
                            )
                        )
                        .removingValue(forKey: "User-Agent")
                )
                
                guard let requestInfoData: Data = try? JSONEncoder().encode(requestInfo), let requestInfoString: String = String(data: requestInfoData, encoding: .ascii) else {
                    return nil
                }
                
                if let body: Data = request.httpBody {
                    guard let bodyString: String = String(data: body, encoding: .ascii) else {
                        return nil
                    }
                    
                    return "l\(requestInfoString.count):\(requestInfoString)\(bodyString.count):\(bodyString)e"
                }
                else if let inputStream: InputStream = request.httpBodyStream, let body: Data = try? Data(from: inputStream), let bodyString: String = String(data: body, encoding: .ascii) {
                    // TODO: Handle this properly
        //            headers["Content-Type"] = request.allHTTPHeaderFields!["Content-Type"]
        //            bodyAsString = "{ \"fileUpload\" : \"\(String(data: body.base64EncodedData(), encoding: .utf8) ?? "null")\" }"
                    return "l\(requestInfoString.count):\(requestInfoString)\(bodyString.count):\(bodyString)e"
                }
                else {
                    return "l\(requestInfoString.count):\(requestInfoString)e"
                }
        }
    }
    
    private static func handleResponse(
        responseData: Data,
        destinationSymmetricKey: Data,
        version: Version,
        destination: Destination,
        seal: Resolver<(OnionRequestResponseInfoType, Data?)>
    ) {
        switch version {
            // V2 and V3 Onion Requests have the same structure for responses
            case .v2, .v3:
                let json: JSON
                
                if let processedJson = try? JSONSerialization.jsonObject(with: responseData, options: [ .fragmentsAllowed ]) as? JSON {
                    json = processedJson
                }
                else if let result: String = String(data: responseData, encoding: .utf8) {
                    json = [ "result": result ]
                }
                else {
                    return seal.reject(HTTP.Error.invalidJSON)
                }
                
                guard let base64EncodedIVAndCiphertext = json["result"] as? String, let ivAndCiphertext = Data(base64Encoded: base64EncodedIVAndCiphertext), ivAndCiphertext.count >= AESGCM.ivSize else {
                    return seal.reject(HTTP.Error.invalidJSON)
                }
                
                do {
                    let data = try AESGCM.decrypt(ivAndCiphertext, with: destinationSymmetricKey)
                    
                    guard let json = try JSONSerialization.jsonObject(with: data, options: [ .fragmentsAllowed ]) as? JSON, let statusCode = json["status_code"] as? Int ?? json["status"] as? Int else {
                        return seal.reject(HTTP.Error.invalidJSON)
                    }
                    
                    if statusCode == 406 { // Clock out of sync
                        SNLog("The user's clock is out of sync with the service node network.")
                        return seal.reject(SnodeAPI.Error.clockOutOfSync)
                    }
                    
                    if let bodyAsString = json["body"] as? String {
                        guard let bodyAsData = bodyAsString.data(using: .utf8), let body = try JSONSerialization.jsonObject(with: bodyAsData, options: [ .fragmentsAllowed ]) as? JSON else {
                            return seal.reject(HTTP.Error.invalidJSON)
                        }
                        
                        if let timestamp = body["t"] as? Int64 {
                            let offset = timestamp - Int64(NSDate.millisecondTimestamp())
                            SnodeAPI.clockOffset = offset
                        }
                        
                        guard 200...299 ~= statusCode else {
                            return seal.reject(Error.httpRequestFailedAtDestination(statusCode: UInt(statusCode), json: body, destination: destination))
                        }
                        
                        return seal.fulfill((OnionRequestAPI.ResponseInfo(code: statusCode, headers: [:]), bodyAsData))
                    }
                    
                    guard 200...299 ~= statusCode else {
                        return seal.reject(Error.httpRequestFailedAtDestination(statusCode: UInt(statusCode), json: json, destination: destination))
                    }
                    
                    return seal.fulfill((OnionRequestAPI.ResponseInfo(code: statusCode, headers: [:]), data))
                    
                }
                catch {
                    return seal.reject(error)
                }
            
            // V4 Onion Requests have a very different structure for responses
            case .v4:
                guard responseData.count >= AESGCM.ivSize else { return seal.reject(HTTP.Error.invalidResponse) }
                
                do {
                    let data: Data = try AESGCM.decrypt(responseData, with: destinationSymmetricKey)
                    
                    // The data will be in the form of `l123:jsone` or `l123:json456:bodye` so we need to break the data into
                    // parts to properly process it
                    guard let responseString: String = String(data: data, encoding: .ascii), responseString.starts(with: "l") else {
                        return seal.reject(HTTP.Error.invalidResponse)
                    }
                    
                    let stringParts: [String.SubSequence] = responseString.split(separator: ":")
                    
                    guard stringParts.count > 1, let infoLength: Int = Int(stringParts[0].suffix(from: stringParts[0].index(stringParts[0].startIndex, offsetBy: 1))) else {
                        return seal.reject(HTTP.Error.invalidResponse)
                    }
                    
                    let infoStringStartIndex: String.Index = responseString.index(responseString.startIndex, offsetBy: "l\(infoLength):".count)
                    let infoStringEndIndex: String.Index = responseString.index(infoStringStartIndex, offsetBy: infoLength)
                    let infoString: String = String(responseString[infoStringStartIndex..<infoStringEndIndex])

                    guard let infoStringData: Data = infoString.data(using: .utf8), let responseInfo: ResponseInfo = try? JSONDecoder().decode(ResponseInfo.self, from: infoStringData) else {
                        return seal.reject(HTTP.Error.invalidResponse)
                    }

                    // Custom handle a clock out of sync error
                    guard responseInfo.code != 406 else {
                        SNLog("The user's clock is out of sync with the service node network.")
                        return seal.reject(SnodeAPI.Error.clockOutOfSync)
                    }
                    
                    // Handle error status codes
                    guard 200...299 ~= responseInfo.code else {
                        return seal.reject(
                            Error.httpRequestFailedAtDestination(
                                statusCode: UInt(responseInfo.code),
                                json: [:],  // TODO: Remove the 'json' value??
                                destination: destination
                            )
                        )
                    }
                    
                    // If there is no data in the response then just return the ResponseInfo
                    guard responseString.count > "l\(infoLength)\(infoString)e".count else {
                        return seal.fulfill((responseInfo, nil))
                    }
                    
                    // TODO: Is this going to be done anymore...???
//                            if let timestamp = body["t"] as? Int64 {
//                                let offset = timestamp - Int64(NSDate.millisecondTimestamp())
//                                SnodeAPI.clockOffset = offset
//                            }
                    
                    // Extract the response data as well
                    let dataString: String = String(responseString.suffix(from: infoStringEndIndex))
                    let dataStringParts: [String.SubSequence] = dataString.split(separator: ":")
                    
                    guard dataStringParts.count > 1, let finalDataLength: Int = Int(dataStringParts[0]) else {
                        return seal.reject(HTTP.Error.invalidResponse)
                    }
                    
                    let finalDataStringStartIndex: String.Index = responseString.index(infoStringEndIndex, offsetBy: "\(finalDataLength):".count)
                    let finalDataStringEndIndex: String.Index = responseString.index(finalDataStringStartIndex, offsetBy: finalDataLength)
                    let finalDataString: String = String(responseString[finalDataStringStartIndex..<finalDataStringEndIndex])
                    
                    guard let finalData: Data = finalDataString.data(using: .ascii) else {
                        return seal.reject(HTTP.Error.invalidResponse)
                    }
                    
                    return seal.fulfill((responseInfo, finalData))
                }
                catch {
                    return seal.reject(error)
                }
        }
    }
}
