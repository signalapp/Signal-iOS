// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium
import GRDB
import SessionUtilitiesKit

public final class SnodeAPI {
    private static let sodium = Sodium()
    
    private static var hasLoadedSnodePool: Atomic<Bool> = Atomic(false)
    private static var loadedSwarms: Atomic<Set<String>> = Atomic([])
    private static var getSnodePoolPromise: Atomic<Promise<Set<Snode>>?> = Atomic(nil)
    
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    internal static var snodeFailureCount: Atomic<[Snode: UInt]> = Atomic([:])
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    internal static var snodePool: Atomic<Set<Snode>> = Atomic([])

    /// The offset between the user's clock and the Service Node's clock. Used in cases where the
    /// user's clock is incorrect.
    ///
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    public static var clockOffset: Atomic<Int64> = Atomic(0)
    /// - Note: Should only be accessed from `Threading.workQueue` to avoid race conditions.
    public static var swarmCache: Atomic<[String: Set<Snode>]> = Atomic([:])
    
    // MARK: - Namespaces
    
    public static let defaultNamespace = 0
    public static let closedGroupNamespace = -10
    public static let configNamespace = 5
    
    // MARK: - Hardfork version
    
    public static var hardfork = UserDefaults.standard[.hardfork]
    public static var softfork = UserDefaults.standard[.softfork]

    // MARK: - Settings
    
    private static let maxRetryCount: UInt = 8
    private static let minSwarmSnodeCount = 3
    private static let seedNodePool: Set<String> = Features.useTestnet ? [ "http://public.loki.foundation:38157" ] : [ "https://storage.seed1.loki.network:4433", "https://storage.seed3.loki.network:4433", "https://public.loki.foundation:4433" ]
    private static let snodeFailureThreshold = 3
    private static let targetSwarmSnodeCount = 2
    private static let minSnodePoolCount = 12

    // MARK: Snode Pool Interaction
    
    private static var hasInsufficientSnodes: Bool { snodePool.wrappedValue.count < minSnodePoolCount }
    
    private static func loadSnodePoolIfNeeded() {
        guard !hasLoadedSnodePool.wrappedValue else { return }
        
        Storage.shared.read { db in
            snodePool.mutate { $0 = ((try? Snode.fetchSet(db)) ?? Set()) }
        }
        
        hasLoadedSnodePool.mutate { $0 = true }
    }
    
    private static func setSnodePool(to newValue: Set<Snode>, db: Database? = nil) {
        snodePool.mutate { $0 = newValue }
        
        if let db: Database = db {
            _ = try? Snode.deleteAll(db)
            newValue.forEach { try? $0.save(db) }
        }
        else {
            Storage.shared.write { db in
                _ = try? Snode.deleteAll(db)
                newValue.forEach { try? $0.save(db) }
            }
        }
    }
    
    private static func dropSnodeFromSnodePool(_ snode: Snode) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        var snodePool = SnodeAPI.snodePool.wrappedValue
        snodePool.remove(snode)
        setSnodePool(to: snodePool)
    }
    
    @objc public static func clearSnodePool() {
        snodePool.mutate { $0.removeAll() }
        
        Threading.workQueue.async {
            setSnodePool(to: [])
        }
    }
    
    // MARK: Swarm Interaction
    private static func loadSwarmIfNeeded(for publicKey: String) {
        guard !loadedSwarms.wrappedValue.contains(publicKey) else { return }
        
        let updatedCacheForKey: Set<Snode> = Storage.shared
           .read { db in try Snode.fetchSet(db, publicKey: publicKey) }
           .defaulting(to: [])
        
        swarmCache.mutate { $0[publicKey] = updatedCacheForKey }
        loadedSwarms.mutate { $0.insert(publicKey) }
    }
    
    private static func setSwarm(to newValue: Set<Snode>, for publicKey: String, persist: Bool = true) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        swarmCache.mutate { $0[publicKey] = newValue }
        
        guard persist else { return }
        
        Storage.shared.write { db in
            try? newValue.save(db, key: publicKey)
        }
    }
    
    public static func dropSnodeFromSwarmIfNeeded(_ snode: Snode, publicKey: String) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        let swarmOrNil = swarmCache.wrappedValue[publicKey]
        guard var swarm = swarmOrNil, let index = swarm.firstIndex(of: snode) else { return }
        swarm.remove(at: index)
        setSwarm(to: swarm, for: publicKey)
    }
    
    // MARK: Internal API
    
    internal static func invoke(_ method: SnodeAPIEndpoint, on snode: Snode, associatedWith publicKey: String? = nil, parameters: JSON) -> Promise<Data> {
        if Features.useOnionRequests {
            return OnionRequestAPI
                .sendOnionRequest(
                    to: snode,
                    invoking: method,
                    with: parameters,
                    associatedWith: publicKey
                )
                .map2 { responseData in
                    guard let responseJson: JSON = try? JSONSerialization.jsonObject(with: responseData, options: [ .fragmentsAllowed ]) as? JSON else {
                        throw HTTP.Error.invalidJSON
                    }
                    
                    if let hf = responseJson["hf"] as? [Int] {
                        if hf[1] > softfork {
                            softfork = hf[1]
                            UserDefaults.standard[.softfork] = softfork
                        }
                        
                        if hf[0] > hardfork {
                            hardfork = hf[0]
                            UserDefaults.standard[.hardfork] = hardfork
                            softfork = hf[1]
                            UserDefaults.standard[.softfork] = softfork
                        }
                    }
                    
                    return responseData
                }
        }
        else {
            let url = "\(snode.address):\(snode.port)/storage_rpc/v1"
            return HTTP.execute(.post, url, parameters: parameters)
                .recover2 { error -> Promise<Data> in
                    guard case HTTP.Error.httpRequestFailed(let statusCode, let data) = error else { throw error }
                    throw SnodeAPI.handleError(withStatusCode: statusCode, data: data, forSnode: snode, associatedWith: publicKey) ?? error
                }
        }
    }
    
    private static func getNetworkTime(from snode: Snode) -> Promise<UInt64> {
        return invoke(.getInfo, on: snode, parameters: [:]).map2 { responseData in
            guard let responseJson: JSON = try? JSONSerialization.jsonObject(with: responseData, options: [ .fragmentsAllowed ]) as? JSON else {
                throw HTTP.Error.invalidJSON
            }
            guard let timestamp = responseJson["timestamp"] as? UInt64 else { throw HTTP.Error.invalidJSON }
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
                    .map2 { responseData -> Set<Snode> in
                        guard let snodePool: SnodePoolResponse = try? JSONDecoder().decode(SnodePoolResponse.self, from: responseData) else {
                            throw SnodeAPIError.snodePoolUpdatingFailed
                        }
                        
                        return snodePool.result
                            .serviceNodeStates
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
        var snodePool = SnodeAPI.snodePool.wrappedValue
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
                
                return invoke(.oxenDaemonRPCCall, on: snode, parameters: parameters)
                    .map2 { responseData in
                        guard let snodePool: SnodePoolResponse = try? JSONDecoder().decode(SnodePoolResponse.self, from: responseData) else {
                            throw SnodeAPIError.snodePoolUpdatingFailed
                        }
                        
                        return snodePool.result
                            .serviceNodeStates
                            .compactMap { $0.value }
                            .asSet()
                    }
            }
        }
        
        let promise = when(fulfilled: snodePoolPromises).map2 { results -> Set<Snode> in
            let result: Set<Snode> = results.reduce(Set()) { prev, next in prev.intersection(next) }
            
            // We want the snodes to agree on at least this many snodes
            guard result.count > 24 else { throw SnodeAPIError.inconsistentSnodePools }
            
            // Limit the snode pool size to 256 so that we don't go too long without
            // refreshing it
            return Set(result.prefix(256))
        }
        
        return promise
    }

    // MARK: Public API
    
    public static func hasCachedSnodesInclusingExpired() -> Bool {
        loadSnodePoolIfNeeded()
        
        return !hasInsufficientSnodes
    }
    
    public static func getSnodePool() -> Promise<Set<Snode>> {
        loadSnodePoolIfNeeded()
        let now = Date()
        let hasSnodePoolExpired = given(Storage.shared[.lastSnodePoolRefreshDate]) {
            now.timeIntervalSince($0) > 2 * 60 * 60
        }.defaulting(to: true)
        let snodePool: Set<Snode> = SnodeAPI.snodePool.wrappedValue
        
        guard hasInsufficientSnodes || hasSnodePoolExpired else {
            return Promise.value(snodePool)
        }
        
        if let getSnodePoolPromise = getSnodePoolPromise.wrappedValue { return getSnodePoolPromise }
        
        let promise: Promise<Set<Snode>>
        if snodePool.count < minSnodePoolCount {
            promise = getSnodePoolFromSeedNode()
        }
        else {
            promise = getSnodePoolFromSnode().recover2 { _ in
                getSnodePoolFromSeedNode()
            }
        }
        
        getSnodePoolPromise.mutate { $0 = promise }
        promise.map2 { snodePool -> Set<Snode> in
            guard !snodePool.isEmpty else { throw SnodeAPIError.snodePoolUpdatingFailed }
            
            return snodePool
        }
        
        promise.then2 { snodePool -> Promise<Set<Snode>> in
            let (promise, seal) = Promise<Set<Snode>>.pending()
            
            Storage.shared.writeAsync(
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
            getSnodePoolPromise.mutate { $0 = nil }
        }
        promise.catch2 { _ in
            getSnodePoolPromise.mutate { $0 = nil }
        }
        
        return promise
    }
    
    public static func getSessionID(for onsName: String) -> Promise<String> {
        let validationCount = 3
        let sessionIDByteCount = 33
        // The name must be lowercased
        let onsName = onsName.lowercased()
        // Hash the ONS name using BLAKE2b
        let nameAsData = [UInt8](onsName.data(using: String.Encoding.utf8)!)
        
        guard let nameHash = sodium.genericHash.hash(message: nameAsData) else {
            return Promise(error: SnodeAPIError.hashingFailed)
        }
        
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
                        
                    case .fulfilled(let responseData):
                        guard let responseJson: JSON = try? JSONSerialization.jsonObject(with: responseData, options: [ .fragmentsAllowed ]) as? JSON else {
                            throw HTTP.Error.invalidJSON
                        }
                        guard
                            let intermediate = responseJson["result"] as? JSON,
                            let hexEncodedCiphertext = intermediate["encrypted_value"] as? String
                        else { return seal.reject(HTTP.Error.invalidJSON) }
                        
                        let ciphertext = [UInt8](Data(hex: hexEncodedCiphertext))
                        let isArgon2Based = (intermediate["nonce"] == nil)
                        
                        if isArgon2Based {
                            // Handle old Argon2-based encryption used before HF16
                            let salt = [UInt8](Data(repeating: 0, count: sodium.pwHash.SaltBytes))
                            guard
                                let key = sodium.pwHash.hash(
                                    outputLength: sodium.secretBox.KeyBytes,
                                    passwd: nameAsData,
                                    salt: salt,
                                    opsLimit: sodium.pwHash.OpsLimitModerate,
                                    memLimit: sodium.pwHash.MemLimitModerate,
                                    alg: .Argon2ID13
                                )
                            else { return seal.reject(SnodeAPIError.hashingFailed) }
                            
                            let nonce = [UInt8](Data(repeating: 0, count: sodium.secretBox.NonceBytes))
                            
                            guard let sessionIDAsData = sodium.secretBox.open(authenticatedCipherText: ciphertext, secretKey: key, nonce: nonce) else {
                                return seal.reject(SnodeAPIError.decryptionFailed)
                            }
                            
                            sessionIDs.append(sessionIDAsData.toHexString())
                        }
                        else {
                            guard let hexEncodedNonce = intermediate["nonce"] as? String else {
                                return seal.reject(HTTP.Error.invalidJSON)
                            }
                            
                            let nonce = [UInt8](Data(hex: hexEncodedNonce))
                            
                            // xchacha-based encryption
                            guard let key = sodium.genericHash.hash(message: nameAsData, key: nameHash) else { // key = H(name, key=H(name))
                                return seal.reject(SnodeAPIError.hashingFailed)
                            }
                            guard ciphertext.count >= (sessionIDByteCount + sodium.aead.xchacha20poly1305ietf.ABytes) else { // Should always be equal in practice
                                return seal.reject(SnodeAPIError.decryptionFailed)
                            }
                            guard let sessionIDAsData = sodium.aead.xchacha20poly1305ietf.decrypt(authenticatedCipherText: ciphertext, secretKey: key, nonce: nonce) else {
                                return seal.reject(SnodeAPIError.decryptionFailed)
                            }
                            
                            sessionIDs.append(sessionIDAsData.toHexString())
                        }
                }
            }
            
            guard sessionIDs.count == validationCount && Set(sessionIDs).count == 1 else {
                return seal.reject(SnodeAPIError.validationFailed)
            }
            
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
        
        if let cachedSwarm = swarmCache.wrappedValue[publicKey], cachedSwarm.count >= minSwarmSnodeCount {
            return Promise<Set<Snode>> { $0.fulfill(cachedSwarm) }
        }
        
        SNLog("Getting swarm for: \((publicKey == getUserHexEncodedPublicKey()) ? "self" : publicKey).")
        let parameters: [String: Any] = [
            "pubKey": (Features.useTestnet ? publicKey.removingIdPrefixIfNeeded() : publicKey)
        ]
        
        return getRandomSnode()
            .then2 { snode in
                attempt(maxRetryCount: 4, recoveringOn: Threading.workQueue) {
                    invoke(.getSwarm, on: snode, associatedWith: publicKey, parameters: parameters)
                }
            }
            .map2 { responseData in
                let swarm = parseSnodes(from: responseData)
                
                setSwarm(to: swarm, for: publicKey)
                return swarm
            }
    }

    // MARK: - Retrieve
    
    // Not in use until we can batch delete and store config messages
    public static func getConfigMessages(from snode: Snode, associatedWith publicKey: String) -> Promise<[SnodeReceivedMessage]> {
        let (promise, seal) = Promise<[SnodeReceivedMessage]>.pending()
        
        Threading.workQueue.async {
            getMessagesWithAuthentication(from: snode, associatedWith: publicKey, namespace: configNamespace)
                .done2 {
                    seal.fulfill($0)
                }
                .catch2 {
                    seal.reject($0)
                }
        }
        
        return promise
    }
    
    public static func getMessages(from snode: Snode, associatedWith publicKey: String, authenticated: Bool = true) -> Promise<[SnodeReceivedMessage]> {
        let (promise, seal) = Promise<[SnodeReceivedMessage]>.pending()
        
        Threading.workQueue.async {
            let retrievePromise = (authenticated ?
                getMessagesWithAuthentication(from: snode, associatedWith: publicKey, namespace: defaultNamespace) :
                getMessagesUnauthenticated(from: snode, associatedWith: publicKey)
            )
            
            retrievePromise
                .done2 { seal.fulfill($0) }
                .catch2 { seal.reject($0) }
        }
        
        return promise
    }
    
    public static func getClosedGroupMessagesFromDefaultNamespace(from snode: Snode, associatedWith publicKey: String) -> Promise<[SnodeReceivedMessage]> {
        let (promise, seal) = Promise<[SnodeReceivedMessage]>.pending()
        
        Threading.workQueue.async {
            getMessagesUnauthenticated(from: snode, associatedWith: publicKey, namespace: defaultNamespace)
                .done2 { seal.fulfill($0) }
                .catch2 { seal.reject($0) }
        }
        
        return promise
    }
    
    private static func getMessagesWithAuthentication(from snode: Snode, associatedWith publicKey: String, namespace: Int) -> Promise<[SnodeReceivedMessage]> {
        /// **Note:** All authentication logic is only apply to 1-1 chats, the reason being that we can't currently support it yet for
        /// closed groups. The Storage Server requires an ed25519 key pair, but we don't have that for our closed groups.
        guard let userED25519KeyPair: Box.KeyPair = Storage.shared.read({ db in Identity.fetchUserEd25519KeyPair(db) }) else {
            return Promise(error: SnodeAPIError.noKeyPair)
        }
        
        // Get last message hash
        SnodeReceivedMessageInfo.pruneExpiredMessageHashInfo(for: snode, namespace: namespace, associatedWith: publicKey)
        let lastHash = SnodeReceivedMessageInfo.fetchLastNotExpired(for: snode, namespace: namespace, associatedWith: publicKey)?.hash ?? ""

        // Construct signature
        let timestamp = UInt64(Int64(floor(Date().timeIntervalSince1970 * 1000)) + SnodeAPI.clockOffset.wrappedValue)
        let ed25519PublicKey = userED25519KeyPair.publicKey.toHexString()
        let namespaceVerificationString = (namespace == defaultNamespace ? "" : String(namespace))
        
        guard
            let verificationData = ("retrieve" + namespaceVerificationString + String(timestamp)).data(using: String.Encoding.utf8),
            let signature = sodium.sign.signature(message: Bytes(verificationData), secretKey: userED25519KeyPair.secretKey)
        else { return Promise(error: SnodeAPIError.signingFailed) }
        
        // Make the request
        let parameters: JSON = [
            "pubKey": Features.useTestnet ? publicKey.removingIdPrefixIfNeeded() : publicKey,
            "namespace": namespace,
            "lastHash": lastHash,
            "timestamp": timestamp,
            "pubkey_ed25519": ed25519PublicKey,
            "signature": signature.toBase64()
        ]
        
        return invoke(.getMessages, on: snode, associatedWith: publicKey, parameters: parameters)
            .map { responseData -> [SnodeReceivedMessage] in
                guard
                    let responseJson: JSON = try? JSONSerialization.jsonObject(with: responseData, options: [ .fragmentsAllowed ]) as? JSON,
                    let rawMessages: [JSON] = responseJson["messages"] as? [JSON]
                else {
                    return []
                }
                
                return rawMessages
                    .compactMap { rawMessage -> SnodeReceivedMessage? in
                        SnodeReceivedMessage(
                            snode: snode,
                            publicKey: publicKey,
                            namespace: namespace,
                            rawMessage: rawMessage
                        )
                    }
            }
    }
        
    private static func getMessagesUnauthenticated(
        from snode: Snode,
        associatedWith publicKey: String,
        namespace: Int = closedGroupNamespace
    ) -> Promise<[SnodeReceivedMessage]> {
        // Get last message hash
        SnodeReceivedMessageInfo.pruneExpiredMessageHashInfo(for: snode, namespace: namespace, associatedWith: publicKey)
        let lastHash = SnodeReceivedMessageInfo.fetchLastNotExpired(for: snode, namespace: namespace, associatedWith: publicKey)?.hash ?? ""
        
        // Make the request
        var parameters: JSON = [
            "pubKey": (Features.useTestnet ? publicKey.removingIdPrefixIfNeeded() : publicKey),
            "lastHash": lastHash,
        ]
        
        // Don't include namespace if polling for 0 with no authentication
        if namespace != defaultNamespace {
            parameters["namespace"] = namespace
        }
        
        return invoke(.getMessages, on: snode, associatedWith: publicKey, parameters: parameters)
            .map { responseData -> [SnodeReceivedMessage] in
                guard
                    let responseJson: JSON = try? JSONSerialization.jsonObject(with: responseData, options: [ .fragmentsAllowed ]) as? JSON,
                    let rawMessages: [JSON] = responseJson["messages"] as? [JSON]
                else {
                    return []
                }
                
                return rawMessages
                    .compactMap { rawMessage -> SnodeReceivedMessage? in
                        SnodeReceivedMessage(
                            snode: snode,
                            publicKey: publicKey,
                            namespace: namespace,
                            rawMessage: rawMessage
                        )
                    }
            }
    }
    
    // MARK: Store
    
    public static func sendMessage(_ message: SnodeMessage, isClosedGroupMessage: Bool, isConfigMessage: Bool) -> Promise<Set<Promise<Data>>> {
        return sendMessageUnauthenticated(message, isClosedGroupMessage: isClosedGroupMessage)
    }
    
    // Not in use until we can batch delete and store config messages
    private static func sendMessageWithAuthentication(_ message: SnodeMessage, namespace: Int) -> Promise<Set<Promise<Data>>> {
        guard
            let messageData: Data = try? JSONEncoder().encode(message),
            let messageJson: JSON = try? JSONSerialization.jsonObject(with: messageData, options: [ .fragmentsAllowed ]) as? JSON
        else { return Promise(error: HTTP.Error.invalidJSON) }
        
        guard let userED25519KeyPair: Box.KeyPair = Storage.shared.read({ db in Identity.fetchUserEd25519KeyPair(db) }) else {
            return Promise(error: SnodeAPIError.noKeyPair)
        }
        
        // Construct signature
        let timestamp = UInt64(Int64(floor(Date().timeIntervalSince1970 * 1000)) + SnodeAPI.clockOffset.wrappedValue)
        let ed25519PublicKey = userED25519KeyPair.publicKey.toHexString()
        
        guard
            let verificationData = ("store" + String(namespace) + String(timestamp)).data(using: String.Encoding.utf8),
            let signature = sodium.sign.signature(message: Bytes(verificationData), secretKey: userED25519KeyPair.secretKey)
        else { return Promise(error: SnodeAPIError.signingFailed) }
        
        // Make the request
        let (promise, seal) = Promise<Set<Promise<Data>>>.pending()
        let publicKey = (Features.useTestnet ? message.recipient.removingIdPrefixIfNeeded() : message.recipient)
        
        Threading.workQueue.async {
            getTargetSnodes(for: publicKey)
                .map2 { targetSnodes in
                    var parameters: JSON = messageJson
                    parameters["namespace"] = namespace
                    parameters["sig_timestamp"] = timestamp
                    parameters["pubkey_ed25519"] = ed25519PublicKey
                    parameters["signature"] = signature.toBase64()
                    
                    return Set(targetSnodes.map { targetSnode in
                        attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                            invoke(.sendMessage, on: targetSnode, associatedWith: publicKey, parameters: parameters)
                        }
                    })
                }
                .done2 { seal.fulfill($0) }
                .catch2 { seal.reject($0) }
        }
        
        return promise
    }
    
    private static func sendMessageUnauthenticated(_ message: SnodeMessage, isClosedGroupMessage: Bool) -> Promise<Set<Promise<Data>>> {
        guard
            let messageData: Data = try? JSONEncoder().encode(message),
            let messageJson: JSON = try? JSONSerialization.jsonObject(with: messageData, options: [ .fragmentsAllowed ]) as? JSON
        else { return Promise(error: HTTP.Error.invalidJSON) }
        
        let (promise, seal) = Promise<Set<Promise<Data>>>.pending()
        let publicKey = Features.useTestnet ? message.recipient.removingIdPrefixIfNeeded() : message.recipient
        
        Threading.workQueue.async {
            getTargetSnodes(for: publicKey)
                .map2 { targetSnodes in
                    var rawResponsePromises: Set<Promise<Data>> = Set()
                    var parameters: JSON = messageJson
                    parameters["namespace"] = (isClosedGroupMessage ? closedGroupNamespace : defaultNamespace)
                    
                    for targetSnode in targetSnodes {
                        let rawResponsePromise = attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                            invoke(.sendMessage, on: targetSnode, associatedWith: publicKey, parameters: parameters)
                        }
                        rawResponsePromises.insert(rawResponsePromise)
                    }
                    
                    // Send closed group messages to default namespace as well
                    if hardfork == 19 && softfork == 0 && isClosedGroupMessage {
                        parameters["namespace"] = defaultNamespace
                        for targetSnode in targetSnodes {
                            let rawResponsePromise = attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                                invoke(.sendMessage, on: targetSnode, associatedWith: publicKey, parameters: parameters)
                            }
                            rawResponsePromises.insert(rawResponsePromise)
                        }
                    }
                    
                    return rawResponsePromises
                }
                .done2 { seal.fulfill($0) }
                .catch2 { seal.reject($0) }
        }
        
        return promise
    }
    
    // MARK: Edit
    
    public static func updateExpiry(
        publicKey: String,
        edKeyPair: Box.KeyPair,
        updatedExpiryMs: UInt64,
        serverHashes: [String]
    ) -> Promise<[String: (hashes: [String], expiry: UInt64)]> {
        let publicKey = (Features.useTestnet ? publicKey.removingIdPrefixIfNeeded() : publicKey)
        
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
            getSwarm(for: publicKey)
                .then2 { swarm -> Promise<[String: (hashes: [String], expiry: UInt64)]> in
                    // "expire" || expiry || messages[0] || ... || messages[N]
                    let verificationBytes = SnodeAPIEndpoint.expire.rawValue.bytes
                        .appending(contentsOf: "\(updatedExpiryMs)".data(using: .ascii)?.bytes)
                        .appending(contentsOf: serverHashes.joined().bytes)
                    
                    guard
                        let snode = swarm.randomElement(),
                        let signature = sodium.sign.signature(
                            message: verificationBytes,
                            secretKey: edKeyPair.secretKey
                        )
                    else {
                        throw SnodeAPIError.signingFailed
                    }
                    
                    let parameters: JSON = [
                        "pubkey" : publicKey,
                        "pubkey_ed25519" : edKeyPair.publicKey.toHexString(),
                        "expiry": updatedExpiryMs,
                        "messages": serverHashes,
                        "signature": signature.toBase64()
                    ]
                    
                    return attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                        invoke(.expire, on: snode, associatedWith: publicKey, parameters: parameters)
                            .map2 { responseData -> [String: (hashes: [String], expiry: UInt64)] in
                                guard let responseJson: JSON = try? JSONSerialization.jsonObject(with: responseData, options: [ .fragmentsAllowed ]) as? JSON else {
                                    throw HTTP.Error.invalidJSON
                                }
                                guard let swarm = responseJson["swarm"] as? JSON else { throw HTTP.Error.invalidJSON }
                                
                                var result: [String: (hashes: [String], expiry: UInt64)] = [:]
                                    
                                for (snodePublicKey, rawJSON) in swarm {
                                    guard let json = rawJSON as? JSON else { throw HTTP.Error.invalidJSON }
                                    guard (json["failed"] as? Bool ?? false) == false else {
                                        if let reason = json["reason"] as? String, let statusCode = json["code"] as? String {
                                            SNLog("Couldn't delete data from: \(snodePublicKey) due to error: \(reason) (\(statusCode)).")
                                        }
                                        else {
                                            SNLog("Couldn't delete data from: \(snodePublicKey).")
                                        }
                                        result[snodePublicKey] = ([], 0)
                                        continue
                                    }
                                    
                                    guard
                                        let hashes: [String] = json["updated"] as? [String],
                                        let expiryApplied: UInt64 = json["expiry"] as? UInt64,
                                        let signature: String = json["signature"] as? String
                                    else {
                                        throw HTTP.Error.invalidJSON
                                    }
                                    
                                    // The signature format is ( PUBKEY_HEX || EXPIRY || RMSG[0] || ... || RMSG[N] || UMSG[0] || ... || UMSG[M] )
                                    let verificationBytes = publicKey.bytes
                                        .appending(contentsOf: "\(expiryApplied)".data(using: .ascii)?.bytes)
                                        .appending(contentsOf: serverHashes.joined().bytes)
                                        .appending(contentsOf: hashes.joined().bytes)
                                    let isValid = sodium.sign.verify(
                                        message: verificationBytes,
                                        publicKey: Bytes(Data(hex: snodePublicKey)),
                                        signature: Bytes(Data(base64Encoded: signature)!)
                                    )
                                    
                                    // Ensure the signature is valid
                                    guard isValid else {
                                        throw SnodeAPIError.signatureVerificationFailed
                                    }
                                    
                                    result[snodePublicKey] = (hashes, expiryApplied)
                                }
                                
                                return result
                            }
                    }
                }
        }
    }
    
    // MARK: Delete
    
    public static func deleteMessage(publicKey: String, serverHashes: [String]) -> Promise<[String: Bool]> {
        guard let userED25519KeyPair = Identity.fetchUserEd25519KeyPair() else {
            return Promise(error: SnodeAPIError.noKeyPair)
        }
        
        let publicKey = (Features.useTestnet ? publicKey.removingIdPrefixIfNeeded() : publicKey)
        let userX25519PublicKey: String = getUserHexEncodedPublicKey()
        
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
            getSwarm(for: publicKey)
                .then2 { swarm -> Promise<[String: Bool]> in
                    // "delete" || messages...
                    let verificationBytes = SnodeAPIEndpoint.deleteMessage.rawValue.bytes
                        .appending(contentsOf: serverHashes.joined().bytes)
                    
                    guard
                        let snode = swarm.randomElement(),
                        let signature = sodium.sign.signature(
                            message: verificationBytes,
                            secretKey: userED25519KeyPair.secretKey
                        )
                    else {
                        throw SnodeAPIError.signingFailed
                    }
                    
                    let parameters: JSON = [
                        "pubkey" : userX25519PublicKey,
                        "pubkey_ed25519" : userED25519KeyPair.publicKey.toHexString(),
                        "messages": serverHashes,
                        "signature": signature.toBase64()
                    ]
                    
                    return attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                        invoke(.deleteMessage, on: snode, associatedWith: publicKey, parameters: parameters)
                            .map2 { responseData -> [String: Bool] in
                                guard let responseJson: JSON = try? JSONSerialization.jsonObject(with: responseData, options: [ .fragmentsAllowed ]) as? JSON else {
                                    throw HTTP.Error.invalidJSON
                                }
                                guard let swarm = responseJson["swarm"] as? JSON else { throw HTTP.Error.invalidJSON }
                                
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
                                        let verificationBytes = userX25519PublicKey.bytes
                                            .appending(contentsOf: serverHashes.joined().bytes)
                                            .appending(contentsOf: hashes.joined().bytes)
                                        let isValid = sodium.sign.verify(
                                            message: verificationBytes,
                                            publicKey: Bytes(Data(hex: snodePublicKey)),
                                            signature: Bytes(Data(base64Encoded: signature)!)
                                        )
                                        
                                        result[snodePublicKey] = isValid
                                    }
                                    else {
                                        if let reason = json["reason"] as? String, let statusCode = json["code"] as? String {
                                            SNLog("Couldn't delete data from: \(snodePublicKey) due to error: \(reason) (\(statusCode)).")
                                        }
                                        else {
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
            return Promise(error: SnodeAPIError.noKeyPair)
        }
        
        let userX25519PublicKey: String = getUserHexEncodedPublicKey()
        
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
            getSwarm(for: userX25519PublicKey)
                .then2 { swarm -> Promise<[String:Bool]> in
                    let snode = swarm.randomElement()!
                    
                    return attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                        getNetworkTime(from: snode).then2 { timestamp -> Promise<[String: Bool]> in
                            let verificationData = (SnodeAPIEndpoint.clearAllData.rawValue + String(timestamp)).data(using: String.Encoding.utf8)!
                            
                            guard let signature = sodium.sign.signature(message: Bytes(verificationData), secretKey: userED25519KeyPair.secretKey) else {
                                throw SnodeAPIError.signingFailed
                            }
                            
                            let parameters: JSON = [
                                "pubkey": userX25519PublicKey,
                                "pubkey_ed25519": userED25519KeyPair.publicKey.toHexString(),
                                "timestamp": timestamp,
                                "signature": signature.toBase64()
                            ]
                            
                            return attempt(maxRetryCount: maxRetryCount, recoveringOn: Threading.workQueue) {
                                invoke(.clearAllData, on: snode, parameters: parameters)
                                    .map2 { responseData -> [String: Bool] in
                                        guard let responseJson: JSON = try? JSONSerialization.jsonObject(with: responseData, options: [ .fragmentsAllowed ]) as? JSON else {
                                            throw HTTP.Error.invalidJSON
                                        }
                                        guard let swarm = responseJson["swarm"] as? JSON else { throw HTTP.Error.invalidJSON }
                                    
                                        var result: [String: Bool] = [:]
                                        
                                        for (snodePublicKey, rawJSON) in swarm {
                                            guard let json = rawJSON as? JSON else { throw HTTP.Error.invalidJSON }
                                            
                                            let isFailed = json["failed"] as? Bool ?? false
                                            
                                            if !isFailed {
                                                guard
                                                    let hashes = json["deleted"] as? [String],
                                                    let signature = json["signature"] as? String
                                                else { throw HTTP.Error.invalidJSON }
                                                
                                                // The signature format is ( PUBKEY_HEX || TIMESTAMP || DELETEDHASH[0] || ... || DELETEDHASH[N] )
                                                let verificationData = [
                                                    userX25519PublicKey,
                                                    String(timestamp),
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
        }
    }
    
    // MARK: Parsing
    
    // The parsing utilities below use a best attempt approach to parsing; they warn for parsing failures but don't throw exceptions.

    private static func parseSnodes(from responseData: Data) -> Set<Snode> {
        guard let responseJson: JSON = try? JSONSerialization.jsonObject(with: responseData, options: [ .fragmentsAllowed ]) as? JSON else {
            SNLog("Failed to parse snodes from response data.")
            return []
        }
        guard let rawSnodes = responseJson["snodes"] as? [JSON] else {
            SNLog("Failed to parse snodes from: \(responseJson).")
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

    // MARK: Error Handling
    
    /// - Note: Should only be invoked from `Threading.workQueue` to avoid race conditions.
    @discardableResult
    internal static func handleError(withStatusCode statusCode: UInt, data: Data?, forSnode snode: Snode, associatedWith publicKey: String? = nil) -> Error? {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(Threading.workQueue))
        #endif
        func handleBadSnode() {
            let oldFailureCount = (SnodeAPI.snodeFailureCount.wrappedValue[snode] ?? 0)
            let newFailureCount = oldFailureCount + 1
            SnodeAPI.snodeFailureCount.mutate { $0[snode] = newFailureCount }
            SNLog("Couldn't reach snode at: \(snode); setting failure count to \(newFailureCount).")
            if newFailureCount >= SnodeAPI.snodeFailureThreshold {
                SNLog("Failure threshold reached for: \(snode); dropping it.")
                if let publicKey = publicKey {
                    SnodeAPI.dropSnodeFromSwarmIfNeeded(snode, publicKey: publicKey)
                }
                SnodeAPI.dropSnodeFromSnodePool(snode)
                SNLog("Snode pool count: \(snodePool.wrappedValue.count).")
                SnodeAPI.snodeFailureCount.mutate { $0[snode] = 0 }
            }
        }
        
        switch statusCode {
            case 500, 502, 503:
                // The snode is unreachable
                handleBadSnode()
                
            case 404:
                // May caused by invalid open groups
                SNLog("Can't reach the server.")
                
            case 406:
                SNLog("The user's clock is out of sync with the service node network.")
                return SnodeAPIError.clockOutOfSync
                
            case 421:
                // The snode isn't associated with the given public key anymore
                if let publicKey = publicKey {
                    func invalidateSwarm() {
                        SNLog("Invalidating swarm for: \(publicKey).")
                        SnodeAPI.dropSnodeFromSwarmIfNeeded(snode, publicKey: publicKey)
                    }
                    
                    if let data: Data = data {
                        let snodes = parseSnodes(from: data)
                        
                        if !snodes.isEmpty {
                            setSwarm(to: snodes, for: publicKey)
                        }
                        else {
                            invalidateSwarm()
                        }
                    }
                    else {
                        invalidateSwarm()
                    }
                }
                else {
                    SNLog("Got a 421 without an associated public key.")
                }
                
            default:
                handleBadSnode()
                SNLog("Unhandled response code: \(statusCode).")
        }
        
        return nil
    }
}
