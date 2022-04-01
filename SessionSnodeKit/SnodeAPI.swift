import PromiseKit
import Sodium
import GRDB
import SessionUtilitiesKit

@objc(SNSnodeAPI)
public final class SnodeAPI : NSObject {
    private static let sodium = Sodium()
    
    private static var hasLoadedSnodePool = false
    private static var loadedSwarms: Set<String> = []
    private static var getSnodePoolPromise: Promise<Set<Snode>>?
    
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    internal static var snodeFailureCount: [Snode: UInt] = [:]
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    internal static var snodePool: Set<Snode> = []

    /// The offset between the user's clock and the Service Node's clock. Used in cases where the
    /// user's clock is incorrect.
    ///
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    public static var clockOffset: Int64 = 0
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    public static var swarmCache: [String: Set<Snode>] = [:]

    // MARK: Settings
    private static let maxRetryCount: UInt = 8
    private static let minSwarmSnodeCount = 3
    private static let seedNodePool: Set<String> = Features.useTestnet ? [ "http://public.loki.foundation:38157" ] : [ "https://storage.seed1.loki.network:4433", "https://storage.seed3.loki.network:4433", "https://public.loki.foundation:4433" ]
    private static let snodeFailureThreshold = 3
    private static let targetSwarmSnodeCount = 2
    private static let minSnodePoolCount = 12

    // MARK: Type Aliases
    public typealias MessageListPromise = Promise<[JSON]>
    public typealias RawResponse = Any
    public typealias RawResponsePromise = Promise<RawResponse>
    
    // MARK: Snode Pool Interaction
    private static func loadSnodePoolIfNeeded() {
        guard !hasLoadedSnodePool else { return }
        
        GRDBStorage.shared.read { db in
            snodePool = ((try? Snode.fetchSet(db)) ?? Set())
        }
        
        hasLoadedSnodePool = true
    }
    
    private static func setSnodePool(to newValue: Set<Snode>, db: Database? = nil) {
        snodePool = newValue
        
        if let db: Database = db {
            _ = try? Snode.deleteAll(db)
            newValue.forEach { try? $0.save(db) }
        }
        else {
            GRDBStorage.shared.write { db in
                _ = try? Snode.deleteAll(db)
                newValue.forEach { try? $0.save(db) }
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
        
        GRDBStorage.shared.read { db in
            swarmCache[publicKey] = ((try? Snode.fetchSet(db, publicKey: publicKey)) ?? [])
        }
        
        loadedSwarms.insert(publicKey)
    }
    
    private static func setSwarm(to newValue: Set<Snode>, for publicKey: String, persist: Bool = true) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        swarmCache[publicKey] = newValue
        guard persist else { return }
        
        GRDBStorage.shared.write { db in
            try? newValue.save(db, key: publicKey)
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
    internal static func invoke(_ method: Endpoint, on snode: Snode, associatedWith publicKey: String? = nil, parameters: JSON) -> RawResponsePromise {
        if Features.useOnionRequests {
            return OnionRequestAPI.sendOnionRequest(to: snode, invoking: method, with: parameters, associatedWith: publicKey).map2 { $0 as Any }
        }
        else {
            let url = "\(snode.address):\(snode.port)/storage_rpc/v1"
            return HTTP.execute(.post, url, parameters: parameters).map2 { $0 as Any }.recover2 { error -> Promise<Any> in
                guard case HTTP.Error.httpRequestFailed(let statusCode, let json) = error else { throw error }
                
                throw SnodeAPI.handleError(withStatusCode: statusCode, json: json, forSnode: snode, associatedWith: publicKey) ?? error
            }
        }
    }
    
    private static func getNetworkTime(from snode: Snode) -> Promise<UInt64> {
        return invoke(.getInfo, on: snode, parameters: [:]).map2 { rawResponse in
            guard let json = rawResponse as? JSON,
                let timestamp = json["timestamp"] as? UInt64 else { throw HTTP.Error.invalidJSON }
            return timestamp
        }
    }
    
    internal static func getRandomSnode() -> Promise<Snode> {
        // randomElement() uses the system's default random generator, which is cryptographically secure
        return getSnodePool().map2 { $0.randomElement()! }
    }
    
    private static func getSnodePoolFromSeedNode() -> Promise<Set<Snode>> {
        let target = seedNodePool.randomElement()!
        let url = "\(target)/json_rpc"
        let parameters: JSON = [
            "method": "get_n_service_nodes",
            "params": [
                "active_only": true,
                "limit": 256,
                "fields": [
                    "public_ip": true,
                    "storage_port": true,
                    "pubkey_ed25519": true,
                    "pubkey_x25519": true
                ]
            ]
        ]
        SNLog("Populating snode pool using seed node: \(target).")
        let (promise, seal) = Promise<Set<Snode>>.pending()
        
        Threading.workQueue.async {
            attempt(maxRetryCount: 4, recoveringOn: Threading.workQueue) {
                HTTP.execute(.post, url, parameters: parameters, useSeedNodeURLSession: true)
                    .map2 { json -> Set<Snode> in
                        guard
                            let intermediate = json["result"] as? JSON,
                            let rawSnodes = intermediate["service_node_states"] as? [JSON],
                            let snodeData: Data = try? JSONSerialization.data(withJSONObject: rawSnodes, options: [])
                        else {
                            throw Error.snodePoolUpdatingFailed
                        }
                        
                        return ((try? JSONDecoder().decode([Failable<Snode>].self, from: snodeData)) ?? [])
                            .compactMap { $0.value }
                            .asSet()
                    }
            }
            .done2 { snodePool in
                SNLog("Got snode pool from seed node: \(target).")
                seal.fulfill(snodePool)
            }
            .catch2 { error in
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
            guard let snode = snodePool.randomElement() else { return }
            
            snodePool.remove(snode)
            snodes.insert(snode)
        }
        
        let snodePoolPromises: [Promise<Set<Snode>>] = snodes.map { snode in
            return attempt(maxRetryCount: 4, recoveringOn: Threading.workQueue) {
                // Don't specify a limit in the request. Service nodes return a shuffled
                // list of nodes so if we specify a limit the 3 responses we get might have
                // very little overlap.
                let parameters: JSON = [
                    "endpoint": "get_service_nodes",
                    "params": [
                        "active_only": true,
                        "fields": [
                            "public_ip": true,
                            "storage_port": true,
                            "pubkey_ed25519": true,
                            "pubkey_x25519": true
                        ]
                    ]
                ]
                return invoke(.oxenDaemonRPCCall, on: snode, parameters: parameters).map2 { rawResponse in
                    guard
                        let json = rawResponse as? JSON,
                        let intermediate = json["result"] as? JSON,
                        let rawSnodes = intermediate["service_node_states"] as? [JSON],
                        let snodeData: Data = try? JSONSerialization.data(withJSONObject: rawSnodes, options: [])
                    else {
                        throw Error.snodePoolUpdatingFailed
                    }
                    
                    return ((try? JSONDecoder().decode([Failable<Snode>].self, from: snodeData)) ?? [])
                        .compactMap { $0.value }
                        .asSet()
                }
            }
        }
        
        let promise = when(fulfilled: snodePoolPromises).map2 { results -> Set<Snode> in
            let result: Set<Snode> = results.reduce(Set()) { prev, next in prev.intersection(next) }
            
            // We want the snodes to agree on at least this many snodes
            guard result.count > 24 else { throw Error.inconsistentSnodePools }
            
            // Limit the snode pool size to 256 so that we don't go too long without
            // refreshing it
            return Set(result.prefix(256))
        }
        
        return promise
    }

    // MARK: Public API
    
    @objc(getSnodePool)
    public static func objc_getSnodePool() -> AnyPromise {
        AnyPromise.from(getSnodePool())
    }
    
    public static func getSnodePool() -> Promise<Set<Snode>> {
        loadSnodePoolIfNeeded()
        let now = Date()
        let hasSnodePoolExpired = given(GRDBStorage.shared[.lastSnodePoolRefreshDate]) { now.timeIntervalSince($0) > 2 * 60 * 60 } ?? true
        let snodePool = SnodeAPI.snodePool
        let hasInsufficientSnodes = (snodePool.count < minSnodePoolCount)
        
        if hasInsufficientSnodes || hasSnodePoolExpired {
            if let getSnodePoolPromise = getSnodePoolPromise { return getSnodePoolPromise }
            
            let promise: Promise<Set<Snode>>
            if snodePool.count < minSnodePoolCount {
                promise = getSnodePoolFromSeedNode()
            }
            else {
                promise = getSnodePoolFromSnode().recover2 { _ in
                    getSnodePoolFromSeedNode()
                }
            }
            
            getSnodePoolPromise = promise
            promise.map2 { snodePool -> Set<Snode> in
                guard !snodePool.isEmpty else { throw Error.snodePoolUpdatingFailed }
                
                return snodePool
            }
            
            promise.then2 { snodePool -> Promise<Set<Snode>> in
                let (promise, seal) = Promise<Set<Snode>>.pending()
                
                GRDBStorage.shared.writeAsync(
                    updates: { db in
                        db[.lastSnodePoolRefreshDate] = now
                        setSnodePool(to: snodePool, db: db)
                    },
                    completion: { _, _ in
                        seal.fulfill(snodePool)
                    }
                )
                
                return promise
            }
            promise.done2 { _ in
                getSnodePoolPromise = nil
            }
            promise.catch2 { _ in
                getSnodePoolPromise = nil
            }
            
            return promise
        }
        
        return Promise.value(snodePool)
    }
    
    public static func getSessionID(for onsName: String) -> Promise<String> {
        let validationCount = 3
        let sessionIDByteCount = 33
        // The name must be lowercased
        let onsName = onsName.lowercased()
        // Hash the ONS name using BLAKE2b
        let nameAsData = [UInt8](onsName.data(using: String.Encoding.utf8)!)
        guard let nameHash = sodium.genericHash.hash(message: nameAsData) else { return Promise(error: Error.hashingFailed) }
        
        // Ask 3 different snodes for the Session ID associated with the given name hash
        let base64EncodedNameHash = nameHash.toBase64()
        let parameters: [String:Any] = [
            "endpoint" : "ons_resolve",
            "params" : [
                "type" : 0, // type 0 means Session
                "name_hash" : base64EncodedNameHash
            ]
        ]
        let promises = (0..<validationCount).map { _ in
            return getRandomSnode().then2 { snode in
                attempt(maxRetryCount: 4, recoveringOn: Threading.workQueue) {
                    invoke(.oxenDaemonRPCCall, on: snode, parameters: parameters)
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
                    guard let json = rawResponse as? JSON, let intermediate = json["result"] as? JSON,
                        let hexEncodedCiphertext = intermediate["encrypted_value"] as? String else { return seal.reject(HTTP.Error.invalidJSON) }
                    let ciphertext = [UInt8](Data(hex: hexEncodedCiphertext))
                    let isArgon2Based = (intermediate["nonce"] == nil)
                    if isArgon2Based {
                        // Handle old Argon2-based encryption used before HF16
                        let salt = [UInt8](Data(repeating: 0, count: sodium.pwHash.SaltBytes))
                        guard let key = sodium.pwHash.hash(outputLength: sodium.secretBox.KeyBytes, passwd: nameAsData, salt: salt,
                            opsLimit: sodium.pwHash.OpsLimitModerate, memLimit: sodium.pwHash.MemLimitModerate, alg: .Argon2ID13) else { return seal.reject(Error.hashingFailed) }
                        let nonce = [UInt8](Data(repeating: 0, count: sodium.secretBox.NonceBytes))
                        guard let sessionIDAsData = sodium.secretBox.open(authenticatedCipherText: ciphertext, secretKey: key, nonce: nonce) else {
                            return seal.reject(Error.decryptionFailed)
                        }
                        sessionIDs.append(sessionIDAsData.toHexString())
                    } else {
                        guard let hexEncodedNonce = intermediate["nonce"] as? String else { return seal.reject(HTTP.Error.invalidJSON) }
                        let nonce = [UInt8](Data(hex: hexEncodedNonce))
                        // xchacha-based encryption
                        guard let key = sodium.genericHash.hash(message: nameAsData, key: nameHash) else { // key = H(name, key=H(name))
                            return seal.reject(Error.hashingFailed)
                        }
                        guard ciphertext.count >= (sessionIDByteCount + sodium.aead.xchacha20poly1305ietf.ABytes) else { // Should always be equal in practice
                            return seal.reject(Error.decryptionFailed)
                        }
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
        }
        
        SNLog("Getting swarm for: \((publicKey == getUserHexEncodedPublicKey()) ? "self" : publicKey).")
        let parameters: [String: Any] = [
            "pubKey": Features.useTestnet ? publicKey.removing05PrefixIfNeeded() : publicKey
        ]
        
        return getRandomSnode()
            .then2 { snode in
                attempt(maxRetryCount: 4, recoveringOn: Threading.workQueue) {
                    invoke(.getSwarm, on: snode, associatedWith: publicKey, parameters: parameters)
                }
            }
            .map2 { rawSnodes in
                let swarm = parseSnodes(from: rawSnodes)
                setSwarm(to: swarm, for: publicKey)
                return swarm
            }
    }
    
    public static func getRawMessages(from snode: Snode, associatedWith publicKey: String) -> RawResponsePromise {
        let (promise, seal) = RawResponsePromise.pending()
        Threading.workQueue.async {
            getMessagesInternal(from: snode, associatedWith: publicKey)
                .done2 { seal.fulfill($0) }
                .catch2 { seal.reject($0) }
        }
        return promise
    }

    private static func getMessagesInternal(from snode: Snode, associatedWith publicKey: String) -> RawResponsePromise {
        // NOTE: All authentication logic is currently commented out, the reason being that we can't currently support
        // it yet for closed groups. The Storage Server requires an ed25519 key pair, but we don't have that for our
        // closed groups.
        
//        guard let userED25519KeyPair = storage.getUserED25519KeyPair() else { return Promise(error: Error.noKeyPair) }
        // Get last message hash
        SnodeReceivedMessageInfo.pruneLastMessageHashInfoIfExpired(for: snode, associatedWith: publicKey)
        let lastHash = SnodeReceivedMessageInfo.fetchLastNotExpired(for: snode, associatedWith: publicKey)?.hash ?? ""
        // Construct signature
//        let timestamp = UInt64(Int64(NSDate.millisecondTimestamp()) + SnodeAPI.clockOffset)
//        let ed25519PublicKey = userED25519KeyPair.publicKey.toHexString()
//        let verificationData = ("retrieve" + String(timestamp)).data(using: String.Encoding.utf8)!
//        let signature = sodium.sign.signature(message: Bytes(verificationData), secretKey: userED25519KeyPair.secretKey)!
        // Make the request
        let parameters: JSON = [
            "pubKey" : Features.useTestnet ? publicKey.removing05PrefixIfNeeded() : publicKey,
            "lastHash" : lastHash,
//            "timestamp" : timestamp,
//            "pubkey_ed25519" : ed25519PublicKey,
//            "signature" : signature.toBase64()!
        ]
        return invoke(.getMessages, on: snode, associatedWith: publicKey, parameters: parameters)
    }

    public static func sendMessage(_ message: SnodeMessage) -> Promise<Set<RawResponsePromise>> {
        let (promise, seal) = Promise<Set<RawResponsePromise>>.pending()
        let publicKey = (Features.useTestnet ?
            message.recipient.removing05PrefixIfNeeded() :
            message.recipient
        )
        
        Threading.workQueue.async {
            getTargetSnodes(for: publicKey)
                .map2 { targetSnodes in
                    let parameters = message.toJSON()
                    
                    return targetSnodes
                        .map { targetSnode in
                            attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                                invoke(.sendMessage, on: targetSnode, associatedWith: publicKey, parameters: parameters)
                            }
                        }
                        .asSet()
                }
                .done2 { seal.fulfill($0) }
                .catch2 { seal.reject($0) }
        }
        
        return promise
    }
    
    @objc(deleteMessageForPublickKey:serverHashes:)
    public static func objc_deleteMessage(publicKey: String, serverHashes: [String]) -> AnyPromise {
        AnyPromise.from(deleteMessage(publicKey: publicKey, serverHashes: serverHashes))
    }
    
    public static func deleteMessage(publicKey: String, serverHashes: [String]) -> Promise<[String: Bool]> {
        guard let userED25519KeyPair = Identity.fetchUserEd25519KeyPair() else {
            return Promise(error: Error.noKeyPair)
        }
        
        let publicKey = (Features.useTestnet ? publicKey.removing05PrefixIfNeeded() : publicKey)
        let userX25519PublicKey: String = getUserHexEncodedPublicKey()
        
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
            getSwarm(for: publicKey)
                .then2 { swarm -> Promise<[String: Bool]> in
                    guard
                        let snode = swarm.randomElement(),
                        let verificationData = (Endpoint.deleteMessage.rawValue + serverHashes.joined()).data(using: String.Encoding.utf8),
                        let signature = sodium.sign.signature(message: Bytes(verificationData), secretKey: userED25519KeyPair.secretKey)
                    else {
                        throw Error.signingFailed
                    }
                    
                    let parameters: JSON = [
                        "pubkey" : userX25519PublicKey,
                        "pubkey_ed25519" : userED25519KeyPair.publicKey.toHexString(),
                        "messages": serverHashes,
                        "signature": signature.toBase64()
                    ]
                    
                    return attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                        invoke(.deleteMessage, on: snode, associatedWith: publicKey, parameters: parameters)
                            .map2 { rawResponse -> [String: Bool] in
                            guard let json = rawResponse as? JSON, let swarm = json["swarm"] as? JSON else {
                                throw HTTP.Error.invalidJSON
                            }
                                
                            var result: [String: Bool] = [:]
                                
                            for (snodePublicKey, rawJSON) in swarm {
                                guard let json = rawJSON as? JSON else { throw HTTP.Error.invalidJSON }
                                
                                let isFailed = (json["failed"] as? Bool ?? false)
                                
                                if !isFailed {
                                    guard
                                        let hashes = json["deleted"] as? [String],
                                        let signature = json["signature"] as? String
                                    else {
                                        throw HTTP.Error.invalidJSON
                                    }
                                    
                                    // The signature format is ( PUBKEY_HEX || RMSG[0] || ... || RMSG[N] || DMSG[0] || ... || DMSG[M] )
                                    let verificationData = [
                                        userX25519PublicKey,
                                        serverHashes.joined(),
                                        hashes.joined()
                                    ]
                                    .joined()
                                    .data(using: String.Encoding.utf8)!
                                    let isValid = sodium.sign.verify(
                                        message: Bytes(verificationData),
                                        publicKey: Bytes(Data(hex: snodePublicKey)),
                                        signature: Bytes(Data(base64Encoded: signature)!)
                                    )
                                    result[snodePublicKey] = isValid
                                }
                                else {
                                    if let reason = json["reason"] as? String, let statusCode = json["code"] as? String {
                                        SNLog("Couldn't delete data from: \(snodePublicKey) due to error: \(reason) (\(statusCode)).")
                                    } else {
                                        SNLog("Couldn't delete data from: \(snodePublicKey).")
                                    }
                                    result[snodePublicKey] = false
                                }
                            }
                                
                            return result
                        }
                    }
                }
        }
    }
    
    /// Clears all the user's data from their swarm. Returns a dictionary of snode public key to deletion confirmation.
    public static func clearAllData() -> Promise<[String:Bool]> {
        guard let userED25519KeyPair = Identity.fetchUserEd25519KeyPair() else {
            return Promise(error: Error.noKeyPair)
        }
        
        let userX25519PublicKey: String = getUserHexEncodedPublicKey()
        
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
            getSwarm(for: userX25519PublicKey).then2 { swarm -> Promise<[String:Bool]> in
                let snode = swarm.randomElement()!
                return attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                    getNetworkTime(from: snode).then2 { timestamp -> Promise<[String:Bool]> in
                        let verificationData = (Endpoint.clearAllData.rawValue + String(timestamp)).data(using: String.Encoding.utf8)!
                        guard let signature = sodium.sign.signature(message: Bytes(verificationData), secretKey: userED25519KeyPair.secretKey) else {
                            throw Error.signingFailed
                        }
                        
                        let parameters: JSON = [
                            "pubkey": userX25519PublicKey,
                            "pubkey_ed25519": userED25519KeyPair.publicKey.toHexString(),
                            "timestamp": timestamp,
                            "signature": signature.toBase64()
                        ]
                        
                        return attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                            invoke(.clearAllData, on: snode, parameters: parameters).map2 { rawResponse -> [String: Bool] in
                                guard
                                    let json = rawResponse as? JSON,
                                    let swarm = json["swarm"] as? JSON
                                else { throw HTTP.Error.invalidJSON }
                                
                                var result: [String: Bool] = [:]
                                
                                for (snodePublicKey, rawJSON) in swarm {
                                    guard let json = rawJSON as? JSON else { throw HTTP.Error.invalidJSON }
                                    
                                    let isFailed = json["failed"] as? Bool ?? false
                                    if !isFailed {
                                        guard let hashes = json["deleted"] as? [String], let signature = json["signature"] as? String else { throw HTTP.Error.invalidJSON }
                                        // The signature format is ( PUBKEY_HEX || TIMESTAMP || DELETEDHASH[0] || ... || DELETEDHASH[N] )
                                        let verificationData = (userX25519PublicKey + String(timestamp) + hashes.joined(separator: "")).data(using: String.Encoding.utf8)!
                                        let isValid = sodium.sign.verify(message: Bytes(verificationData), publicKey: Bytes(Data(hex: snodePublicKey)), signature: Bytes(Data(base64Encoded: signature)!))
                                        result[snodePublicKey] = isValid
                                    } else {
                                        if let reason = json["reason"] as? String, let statusCode = json["code"] as? String {
                                            SNLog("Couldn't delete data from: \(snodePublicKey) due to error: \(reason) (\(statusCode)).")
                                        } else {
                                            SNLog("Couldn't delete data from: \(snodePublicKey).")
                                        }
                                        result[snodePublicKey] = false
                                    }
                                }
                                
                                return result
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: Parsing
    
    // The parsing utilities below use a best attempt approach to parsing; they warn for parsing failures but don't throw exceptions.

    private static func parseSnodes(from rawResponse: Any) -> Set<Snode> {
        guard let json = rawResponse as? JSON, let rawSnodes = json["snodes"] as? [JSON] else {
            SNLog("Failed to parse snodes from: \(rawResponse).")
            return []
        }
        
        guard let snodeData: Data = try? JSONSerialization.data(withJSONObject: rawSnodes, options: []) else {
            return []
        }
        
        // FIXME: Hopefully at some point this different Snode structure will be deprecated and can be removed
        if
            let swarmSnodes: [SwarmSnode] = try? JSONDecoder().decode([Failable<SwarmSnode>].self, from: snodeData).compactMap({ $0.value }),
            !swarmSnodes.isEmpty
        {
            return swarmSnodes.map { $0.toSnode() }.asSet()
        }
        
        return ((try? JSONDecoder().decode([Failable<Snode>].self, from: snodeData)) ?? [])
            .compactMap { $0.value }
            .asSet()
    }

    public static func parseRawMessagesResponse(_ rawResponse: Any, from snode: Snode, associatedWith publicKey: String) -> [SnodeReceivedMessage] {
        guard let json = rawResponse as? JSON, let rawMessages = json["messages"] as? [JSON] else {
            return []
        }

        return removeDuplicates(from: rawMessages, associatedWith: publicKey)
            .compactMap { rawMessage -> SnodeReceivedMessage? in
                return SnodeReceivedMessage(
                    snode: snode,
                    publicKey: publicKey,
                    rawMessage: rawMessage
                )
            }
    }
    
    private static func removeDuplicates(from rawMessages: [JSON], associatedWith publicKey: String) -> [JSON] {
        var oldReceivedMessages: [SnodeReceivedMessageInfo] = []
        
        GRDBStorage.shared.read { db in
            oldReceivedMessages = oldReceivedMessages.appending(
                contentsOf: try? SnodeReceivedMessageInfo
                    .filter(SnodeReceivedMessageInfo.Columns.key.like("%\(publicKey)"))
                    .fetchAll(db)
            )
        }
        
        let oldMessageHashes: Set<String> = oldReceivedMessages.map { $0.hash }.asSet()
        
        return rawMessages
            .compactMap { rawMessage -> JSON? in
                guard let hash: String = rawMessage["hash"] as? String else {
                    SNLog("Missing hash value for message: \(rawMessage).")
                    return nil
                }
                guard !oldMessageHashes.contains(hash) else { return nil }
                
                return rawMessage
            }
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
