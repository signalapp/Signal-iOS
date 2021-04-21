import PromiseKit
import SessionUtilitiesKit
import Sodium

@objc(SNSnodeAPI)
public final class SnodeAPI : NSObject {
    private static var hasLoadedSnodePool = false
    private static var loadedSwarms: Set<String> = []
    private static var getSnodePoolPromise: Promise<Set<Snode>>?
    
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    internal static var snodeFailureCount: [Snode:UInt] = [:]
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    internal static var snodePool: Set<Snode> = []

    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    public static var swarmCache: [String:Set<Snode>] = [:]

    // MARK: Settings
    private static let maxRetryCount: UInt = 8
    private static let minSwarmSnodeCount = 3
    private static let seedNodePool: Set<String> = useTestnet ? [ "http://public.loki.foundation:38157" ] : [ "https://storage.seed1.loki.network:4433", "https://storage.seed3.loki.network:4433", "https://public.loki.foundation:4433" ]
    private static let snodeFailureThreshold = 3
    private static let targetSwarmSnodeCount = 2
    private static let minSnodePoolCount = 12

    /// - Note: Changing this on the fly is not recommended.
    internal static var useOnionRequests = true
    internal static let useTestnet = false
    
    // MARK: Error
    public enum Error : LocalizedError {
        case generic
        case clockOutOfSync
        case snodePoolUpdatingFailed
        case inconsistentSnodePools
        // ONS
        case decryptionFailed
        case hashingFailed
        case validationFailed

        public var errorDescription: String? {
            switch self {
            case .generic: return "An error occurred."
            case .clockOutOfSync: return "Your clock is out of sync with the Service Node network. Please check that your device's clock is set to automatic time."
            case .snodePoolUpdatingFailed: return "Failed to update the Service Node pool."
            case .inconsistentSnodePools: return "Received inconsistent Service Node pool information from the Service Node network."
            // ONS
            case .decryptionFailed: return "Couldn't decrypt ONS name."
            case .hashingFailed: return "Couldn't compute ONS name hash."
            case .validationFailed: return "ONS name validation failed."
            }
        }
    }

    // MARK: Type Aliases
    public typealias MessageListPromise = Promise<[JSON]>
    public typealias RawResponse = Any
    public typealias RawResponsePromise = Promise<RawResponse>
    
    // MARK: Snode Pool Interaction
    private static func loadSnodePoolIfNeeded() {
        guard !hasLoadedSnodePool else { return }
        snodePool = SNSnodeKitConfiguration.shared.storage.getSnodePool()
        hasLoadedSnodePool = true
    }
    
    private static func setSnodePool(to newValue: Set<Snode>, using transaction: Any? = nil) {
        snodePool = newValue
        let storage = SNSnodeKitConfiguration.shared.storage
        if let transaction = transaction {
            storage.setSnodePool(to: newValue, using: transaction)
        } else {
            storage.writeSync { transaction in
                storage.setSnodePool(to: newValue, using: transaction)
            }
        }
    }
    
    private static func dropSnodeFromSnodePool(_ snode: Snode) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        var snodePool = SnodeAPI.snodePool
        snodePool.remove(snode)
        setSnodePool(to: snodePool)
    }
    
    @objc public static func clearSnodePool() {
        snodePool.removeAll()
        Threading.workQueue.async {
            setSnodePool(to: [])
        }
    }
    
    // MARK: Swarm Interaction
    private static func loadSwarmIfNeeded(for publicKey: String) {
        guard !loadedSwarms.contains(publicKey) else { return }
        swarmCache[publicKey] = SNSnodeKitConfiguration.shared.storage.getSwarm(for: publicKey)
        loadedSwarms.insert(publicKey)
    }
    
    private static func setSwarm(to newValue: Set<Snode>, for publicKey: String, persist: Bool = true) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        swarmCache[publicKey] = newValue
        guard persist else { return }
        SNSnodeKitConfiguration.shared.storage.writeSync { transaction in
            SNSnodeKitConfiguration.shared.storage.setSwarm(to: newValue, for: publicKey, using: transaction)
        }
    }
    
    public static func dropSnodeFromSwarmIfNeeded(_ snode: Snode, publicKey: String) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        let swarmOrNil = swarmCache[publicKey]
        guard var swarm = swarmOrNil, let index = swarm.firstIndex(of: snode) else { return }
        swarm.remove(at: index)
        setSwarm(to: swarm, for: publicKey)
    }
    
    // MARK: Internal API
    internal static func invoke(_ method: Snode.Method, on snode: Snode, associatedWith publicKey: String? = nil, parameters: JSON) -> RawResponsePromise {
        if useOnionRequests {
            return OnionRequestAPI.sendOnionRequest(to: snode, invoking: method, with: parameters, associatedWith: publicKey).map2 { $0 as Any }
        } else {
            let url = "\(snode.address):\(snode.port)/storage_rpc/v1"
            return HTTP.execute(.post, url, parameters: parameters).map2 { $0 as Any }.recover2 { error -> Promise<Any> in
                guard case HTTP.Error.httpRequestFailed(let statusCode, let json) = error else { throw error }
                throw SnodeAPI.handleError(withStatusCode: statusCode, json: json, forSnode: snode, associatedWith: publicKey) ?? error
            }
        }
    }
    
    internal static func getRandomSnode() -> Promise<Snode> {
        // randomElement() uses the system's default random generator, which is cryptographically secure
        return getSnodePool().map2 { $0.randomElement()! }
    }
    
    private static func getSnodePool() -> Promise<Set<Snode>> {
        loadSnodePoolIfNeeded()
        let now = Date()
        let hasSnodePoolExpired = given(Storage.shared.getLastSnodePoolRefreshDate()) { now.timeIntervalSince($0) > 2 * 60 * 60 } ?? true
        let snodePool = SnodeAPI.snodePool
        let hasInsufficientSnodes = (snodePool.count < minSnodePoolCount)
        if hasInsufficientSnodes || hasSnodePoolExpired {
            if let getSnodePoolPromise = getSnodePoolPromise { return getSnodePoolPromise }
            let promise: Promise<Set<Snode>>
            if snodePool.count < minSnodePoolCount {
                promise = getSnodePoolFromSeedNode()
            } else {
                promise = getSnodePoolFromSnode().recover2 { _ in
                    getSnodePoolFromSeedNode()
                }
            }
            getSnodePoolPromise = promise
            promise.map2 { snodePool -> Set<Snode> in
                if snodePool.isEmpty {
                    throw Error.snodePoolUpdatingFailed
                } else {
                    return snodePool
                }
            }
            promise.then2 { snodePool -> Promise<Set<Snode>> in
                let (promise, seal) = Promise<Set<Snode>>.pending()
                SNSnodeKitConfiguration.shared.storage.write(with: { transaction in
                    Storage.shared.setLastSnodePoolRefreshDate(to: now, using: transaction)
                    setSnodePool(to: snodePool, using: transaction)
                }, completion: {
                    seal.fulfill(snodePool)
                })
                return promise
            }
            promise.done2 { _ in
                getSnodePoolPromise = nil
            }
            promise.catch2 { _ in
                getSnodePoolPromise = nil
            }
            return promise
        } else {
            return Promise.value(snodePool)
        }
    }
    
    private static func getSnodePoolFromSeedNode() -> Promise<Set<Snode>> {
        let target = seedNodePool.randomElement()!
        let url = "\(target)/json_rpc"
        let parameters: JSON = [
            "method" : "get_n_service_nodes",
            "params" : [
                "active_only" : true,
                "limit" : 256,
                "fields" : [
                    "public_ip" : true, "storage_port" : true, "pubkey_ed25519" : true, "pubkey_x25519" : true
                ]
            ]
        ]
        SNLog("Populating snode pool using seed node: \(target).")
        let (promise, seal) = Promise<Set<Snode>>.pending()
        Threading.workQueue.async {
            attempt(maxRetryCount: 4, recoveringOn: Threading.workQueue) {
                HTTP.execute(.post, url, parameters: parameters, useSeedNodeURLSession: true).map2 { json -> Set<Snode> in
                    guard let intermediate = json["result"] as? JSON, let rawSnodes = intermediate["service_node_states"] as? [JSON] else { throw Error.snodePoolUpdatingFailed }
                    return Set(rawSnodes.compactMap { rawSnode in
                        guard let address = rawSnode["public_ip"] as? String, let port = rawSnode["storage_port"] as? Int,
                            let ed25519PublicKey = rawSnode["pubkey_ed25519"] as? String, let x25519PublicKey = rawSnode["pubkey_x25519"] as? String, address != "0.0.0.0" else {
                            SNLog("Failed to parse snode from: \(rawSnode).")
                            return nil
                        }
                        return Snode(address: "https://\(address)", port: UInt16(port), publicKeySet: Snode.KeySet(ed25519Key: ed25519PublicKey, x25519Key: x25519PublicKey))
                    })
                }
            }.done2 { snodePool in
                SNLog("Got snode pool from seed node: \(target).")
                seal.fulfill(snodePool)
            }.catch2 { error in
                SNLog("Failed to contact seed node at: \(target).")
                seal.reject(error)
            }
        }
        return promise
    }
    
    private static func getSnodePoolFromSnode() -> Promise<Set<Snode>> {
        var snodePool = SnodeAPI.snodePool
        var snodes: Set<Snode> = []
        (0..<3).forEach { _ in
            let snode = snodePool.randomElement()!
            snodePool.remove(snode)
            snodes.insert(snode)
        }
        let snodePoolPromises: [Promise<Set<Snode>>] = snodes.map { snode in
            return attempt(maxRetryCount: 4, recoveringOn: Threading.workQueue) {
                let parameters: JSON = [
                    "endpoint" : "get_service_nodes",
                    "params" : [
                        "limit" : 256,
                        "active_only" : true,
                        "fields" : [
                            "public_ip" : true, "storage_port" : true, "pubkey_ed25519" : true, "pubkey_x25519" : true
                        ]
                    ]
                ]
                let promise: Promise<Set<Snode>> = invoke(.getAllSnodes, on: snode, parameters: parameters).map2 { rawResponse in
                    guard let json = rawResponse as? JSON, let intermediate = json["result"] as? JSON,
                        let rawSnodes = intermediate["service_node_states"] as? [JSON] else {
                        throw Error.snodePoolUpdatingFailed
                    }
                    return Set(rawSnodes.compactMap { rawSnode in
                        guard let address = rawSnode["public_ip"] as? String, let port = rawSnode["storage_port"] as? Int,
                            let ed25519PublicKey = rawSnode["pubkey_ed25519"] as? String, let x25519PublicKey = rawSnode["pubkey_x25519"] as? String, address != "0.0.0.0" else {
                            SNLog("Failed to parse snode from: \(rawSnode).")
                            return nil
                        }
                        return Snode(address: "https://\(address)", port: UInt16(port), publicKeySet: Snode.KeySet(ed25519Key: ed25519PublicKey, x25519Key: x25519PublicKey))
                    })
                }
                return promise
            }
        }
        let promise = when(fulfilled: snodePoolPromises).map2 { results -> Set<Snode> in
            var result: Set<Snode> = results[0]
            results.forEach { result = result.union($0) }
            if result.count > 24 { // We want the snodes to agree on at least this many snodes
                return result
            } else {
                throw Error.inconsistentSnodePools
            }
        }
        return promise
    }

    // MARK: Public API
    public static func getSessionID(for onsName: String) -> Promise<String> {
        let sodium = Sodium()
        let validationCount = 3
        let sessionIDByteCount = 33
        // The name must be lowercased
        let onsName = onsName.lowercased()
        // Hash the ONS name using BLAKE2b
        let nameAsData = [UInt8](onsName.data(using: String.Encoding.utf8)!)
        guard let nameHash = sodium.genericHash.hash(message: nameAsData),
            let base64EncodedNameHash = nameHash.toBase64() else { return Promise(error: Error.hashingFailed) }
        // Ask 3 different snodes for the Session ID associated with the given name hash
        let parameters: [String:Any] = [ "name_hash" : base64EncodedNameHash ]
        let promises = (0..<validationCount).map { _ in
            return getRandomSnode().then2 { snode in
                attempt(maxRetryCount: 4, recoveringOn: Threading.workQueue) {
                    invoke(.getSessionIDForONSName, on: snode, parameters: parameters)
                }
            }
        }
        let (promise, seal) = Promise<String>.pending()
        when(resolved: promises).done2 { results in
            var sessionIDs: [String] = []
            for result in results {
                switch result {
                case .rejected(let error): return seal.reject(error)
                case .fulfilled(let rawResponse):
                    guard let json = rawResponse as? JSON, let x0 = json["result"] as? JSON,
                        let x1 = x0["entries"] as? [JSON], let x2 = x1.first,
                        let hexEncodedEncryptedBlob = x2["encrypted_value"] as? String else { return seal.reject(HTTP.Error.invalidJSON) }
                    let encryptedBlob = [UInt8](Data(hex: hexEncodedEncryptedBlob))
                    let isArgon2Based = (encryptedBlob.count == sessionIDByteCount + sodium.secretBox.MacBytes)
                    if isArgon2Based {
                        // Handle old Argon2-based encryption used before HF16
                        let salt = [UInt8](Data(repeating: 0, count: sodium.pwHash.SaltBytes))
                        guard let key = sodium.pwHash.hash(outputLength: sodium.secretBox.KeyBytes, passwd: nameAsData, salt: salt,
                            opsLimit: sodium.pwHash.OpsLimitModerate, memLimit: sodium.pwHash.MemLimitModerate, alg: .Argon2ID13) else { return seal.reject(Error.hashingFailed) }
                        let nonce = [UInt8](Data(repeating: 0, count: sodium.secretBox.NonceBytes))
                        guard let sessionIDAsData = sodium.secretBox.open(authenticatedCipherText: encryptedBlob, secretKey: key, nonce: nonce) else {
                            return seal.reject(Error.decryptionFailed)
                        }
                        sessionIDs.append(sessionIDAsData.toHexString())
                    } else {
                        // BLAKE2b-based encryption
                        guard let key = sodium.genericHash.hash(message: nameAsData, key: nameHash) else { // key = H(name, key=H(name))
                            return seal.reject(Error.hashingFailed)
                        }
                        let nonceSize = sodium.aead.xchacha20poly1305ietf.NonceBytes
                        guard encryptedBlob.count >= (sessionIDByteCount + sodium.aead.xchacha20poly1305ietf.ABytes + nonceSize) else { // Should always be equal in practice
                            return seal.reject(Error.decryptionFailed)
                        }
                        let nonce = [UInt8](encryptedBlob[(encryptedBlob.endIndex - nonceSize) ..< encryptedBlob.endIndex])
                        let ciphertext = [UInt8](encryptedBlob[0 ..< (encryptedBlob.endIndex - nonceSize)])
                        guard let sessionIDAsData = sodium.aead.xchacha20poly1305ietf.decrypt(authenticatedCipherText: ciphertext, secretKey: key, nonce: nonce) else {
                            return seal.reject(Error.decryptionFailed)
                        }
                        sessionIDs.append(sessionIDAsData.toHexString())
                    }
                }
            }
            guard sessionIDs.count == validationCount && Set(sessionIDs).count == 1 else { return seal.reject(Error.validationFailed) }
            seal.fulfill(sessionIDs.first!)
        }
        return promise
    }
    
    public static func getTargetSnodes(for publicKey: String) -> Promise<[Snode]> {
        // shuffled() uses the system's default random generator, which is cryptographically secure
        return getSwarm(for: publicKey).map2 { Array($0.shuffled().prefix(targetSwarmSnodeCount)) }
    }

    public static func getSwarm(for publicKey: String) -> Promise<Set<Snode>> {
        loadSwarmIfNeeded(for: publicKey)
        if let cachedSwarm = swarmCache[publicKey], cachedSwarm.count >= minSwarmSnodeCount {
            return Promise<Set<Snode>> { $0.fulfill(cachedSwarm) }
        } else {
            SNLog("Getting swarm for: \((publicKey == SNSnodeKitConfiguration.shared.storage.getUserPublicKey()) ? "self" : publicKey).")
            let parameters: [String:Any] = [ "pubKey" : useTestnet ? publicKey.removing05PrefixIfNeeded() : publicKey ]
            return getRandomSnode().then2 { snode in
                attempt(maxRetryCount: 4, recoveringOn: Threading.workQueue) {
                    invoke(.getSwarm, on: snode, associatedWith: publicKey, parameters: parameters)
                }
            }.map2 { rawSnodes in
                let swarm = parseSnodes(from: rawSnodes)
                setSwarm(to: swarm, for: publicKey)
                return swarm
            }
        }
    }
    
    public static func getRawMessages(from snode: Snode, associatedWith publicKey: String) -> RawResponsePromise {
        let (promise, seal) = RawResponsePromise.pending()
        let storage = SNSnodeKitConfiguration.shared.storage
        Threading.workQueue.async {
            storage.writeSync { transaction in
                storage.pruneLastMessageHashInfoIfExpired(for: snode, associatedWith: publicKey, using: transaction)
            }
            let lastHash = storage.getLastMessageHash(for: snode, associatedWith: publicKey) ?? ""
            let parameters = [ "pubKey" : useTestnet ? publicKey.removing05PrefixIfNeeded() : publicKey, "lastHash" : lastHash ]
            invoke(.getMessages, on: snode, associatedWith: publicKey, parameters: parameters).done2 { seal.fulfill($0) }.catch2 { seal.reject($0) }
        }
        return promise
    }

    public static func getMessages(for publicKey: String) -> Promise<Set<MessageListPromise>> {
        let (promise, seal) = Promise<Set<MessageListPromise>>.pending()
        let storage = SNSnodeKitConfiguration.shared.storage
        Threading.workQueue.async {
            attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                getTargetSnodes(for: publicKey).mapValues2 { targetSnode in
                    storage.writeSync { transaction in
                        storage.pruneLastMessageHashInfoIfExpired(for: targetSnode, associatedWith: publicKey, using: transaction)
                    }
                    let lastHash = storage.getLastMessageHash(for: targetSnode, associatedWith: publicKey) ?? ""
                    let parameters = [ "pubKey" : useTestnet ? publicKey.removing05PrefixIfNeeded() : publicKey, "lastHash" : lastHash ]
                    return invoke(.getMessages, on: targetSnode, associatedWith: publicKey, parameters: parameters).map2 { rawResponse in
                        parseRawMessagesResponse(rawResponse, from: targetSnode, associatedWith: publicKey)
                    }
                }.map2 { Set($0) }
            }.done2 { seal.fulfill($0) }.catch2 { seal.reject($0) }
        }
        return promise
    }

    public static func sendMessage(_ message: SnodeMessage) -> Promise<Set<RawResponsePromise>> {
        let (promise, seal) = Promise<Set<RawResponsePromise>>.pending()
        let publicKey = useTestnet ? message.recipient.removing05PrefixIfNeeded() : message.recipient
        Threading.workQueue.async {
            getTargetSnodes(for: publicKey).map2 { targetSnodes in
                let parameters = message.toJSON()
                return Set(targetSnodes.map { targetSnode in
                    attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                        invoke(.sendMessage, on: targetSnode, associatedWith: publicKey, parameters: parameters)
                    }
                })
            }.done2 { seal.fulfill($0) }.catch2 { seal.reject($0) }
        }
        return promise
    }
    
    // MARK: Parsing
    
    // The parsing utilities below use a best attempt approach to parsing; they warn for parsing failures but don't throw exceptions.

    private static func parseSnodes(from rawResponse: Any) -> Set<Snode> {
        guard let json = rawResponse as? JSON, let rawSnodes = json["snodes"] as? [JSON] else {
            SNLog("Failed to parse snodes from: \(rawResponse).")
            return []
        }
        return Set(rawSnodes.compactMap { rawSnode in
            guard let address = rawSnode["ip"] as? String, let portAsString = rawSnode["port"] as? String, let port = UInt16(portAsString),
                let ed25519PublicKey = rawSnode["pubkey_ed25519"] as? String, let x25519PublicKey = rawSnode["pubkey_x25519"] as? String, address != "0.0.0.0" else {
                SNLog("Failed to parse snode from: \(rawSnode).")
                return nil
            }
            return Snode(address: "https://\(address)", port: port, publicKeySet: Snode.KeySet(ed25519Key: ed25519PublicKey, x25519Key: x25519PublicKey))
        })
    }

    public static func parseRawMessagesResponse(_ rawResponse: Any, from snode: Snode, associatedWith publicKey: String) -> [JSON] {
        guard let json = rawResponse as? JSON, let rawMessages = json["messages"] as? [JSON] else { return [] }
        updateLastMessageHashValueIfPossible(for: snode, associatedWith: publicKey, from: rawMessages)
        return removeDuplicates(from: rawMessages, associatedWith: publicKey)
    }
    
    private static func updateLastMessageHashValueIfPossible(for snode: Snode, associatedWith publicKey: String, from rawMessages: [JSON]) {
        if let lastMessage = rawMessages.last, let lastHash = lastMessage["hash"] as? String, let expirationDate = lastMessage["expiration"] as? UInt64 {
            SNSnodeKitConfiguration.shared.storage.writeSync { transaction in
                SNSnodeKitConfiguration.shared.storage.setLastMessageHashInfo(for: snode, associatedWith: publicKey,
                    to: [ "hash" : lastHash, "expirationDate" : NSNumber(value: expirationDate) ], using: transaction)
            }
        } else if (!rawMessages.isEmpty) {
            SNLog("Failed to update last message hash value from: \(rawMessages).")
        }
    }
    
    private static func removeDuplicates(from rawMessages: [JSON], associatedWith publicKey: String) -> [JSON] {
        var receivedMessages = SNSnodeKitConfiguration.shared.storage.getReceivedMessages(for: publicKey)
        let result = rawMessages.filter { rawMessage in
            guard let hash = rawMessage["hash"] as? String else {
                SNLog("Missing hash value for message: \(rawMessage).")
                return false
            }
            let isDuplicate = receivedMessages.contains(hash)
            receivedMessages.insert(hash)
            return !isDuplicate
        }
        SNSnodeKitConfiguration.shared.storage.writeSync { transaction in
            SNSnodeKitConfiguration.shared.storage.setReceivedMessages(to: receivedMessages, for: publicKey, using: transaction)
        }
        return result
    }

    // MARK: Error Handling
    /// - Note: Should only be invoked from `Threading.workQueue` to avoid race conditions.
    @discardableResult
    internal static func handleError(withStatusCode statusCode: UInt, json: JSON?, forSnode snode: Snode, associatedWith publicKey: String? = nil) -> Error? {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        func handleBadSnode() {
            let oldFailureCount = SnodeAPI.snodeFailureCount[snode] ?? 0
            let newFailureCount = oldFailureCount + 1
            SnodeAPI.snodeFailureCount[snode] = newFailureCount
            SNLog("Couldn't reach snode at: \(snode); setting failure count to \(newFailureCount).")
            if newFailureCount >= SnodeAPI.snodeFailureThreshold {
                SNLog("Failure threshold reached for: \(snode); dropping it.")
                if let publicKey = publicKey {
                    SnodeAPI.dropSnodeFromSwarmIfNeeded(snode, publicKey: publicKey)
                }
                SnodeAPI.dropSnodeFromSnodePool(snode)
                SNLog("Snode pool count: \(snodePool.count).")
                SnodeAPI.snodeFailureCount[snode] = 0
            }
        }
        switch statusCode {
        case 500, 502, 503:
            // The snode is unreachable
            handleBadSnode()
        case 406:
            SNLog("The user's clock is out of sync with the service node network.")
            return Error.clockOutOfSync
        case 421:
            // The snode isn't associated with the given public key anymore
            if let publicKey = publicKey {
                func invalidateSwarm() {
                    SNLog("Invalidating swarm for: \(publicKey).")
                    SnodeAPI.dropSnodeFromSwarmIfNeeded(snode, publicKey: publicKey)
                }
                if let json = json {
                    let snodes = parseSnodes(from: json)
                    if !snodes.isEmpty {
                        setSwarm(to: snodes, for: publicKey)
                    } else {
                        invalidateSwarm()
                    }
                } else {
                    invalidateSwarm()
                }
            } else {
                SNLog("Got a 421 without an associated public key.")
            }
        default:
            handleBadSnode()
            SNLog("Unhandled response code: \(statusCode).")
        }
        return nil
    }
}
