import PromiseKit
import SessionSnodeKit
import Sodium
import Curve25519Kit

@objc(SNOpenGroupAPIV2)
public final class OpenGroupAPIV2: NSObject {
    
    // MARK: - Settings
    
    public static let defaultServer = "http://116.203.70.33"
    public static let defaultServerPublicKey = "a03c383cf63c3c4efe67acc52112a6dd734b3a946b9545f488aaa93da7991238"
    
    // MARK: - Cache
    
    private static var authTokenPromises: Atomic<[String: Promise<String>]> = Atomic([:])
    private static var hasPerformedInitialPoll: [String: Bool] = [:]
    private static var hasUpdatedLastOpenDate = false
    public static let workQueue = DispatchQueue(label: "OpenGroupAPIV2.workQueue", qos: .userInitiated) // It's important that this is a serial queue
    public static var moderators: [String: [String: Set<String>]] = [:] // Server URL to room ID to set of moderator IDs
    public static var defaultRoomsPromise: Promise<[RoomInfo]>?
    public static var groupImagePromises: [String: Promise<Data>] = [:]

    private static let timeSinceLastOpen: TimeInterval = {
        guard let lastOpen = UserDefaults.standard[.lastOpen] else { return .greatestFiniteMagnitude }
        
        return Date().timeIntervalSince(lastOpen)
    }()

    // MARK: - Convenience
    
    private static func send(_ request: Request) -> Promise<Data> {
        guard let url: URL = request.url else { return Promise(error: Error.invalidURL) }
        
        var urlRequest: URLRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.verb.rawValue
        urlRequest.allHTTPHeaderFields = request.headers
            .setting(.room, request.room)   // TODO: Is this needed anymore? Add at the request level?
            .toHTTPHeaders()
        urlRequest.httpBody = request.body
        
        if request.useOnionRouting {
            guard let publicKey = SNMessagingKitConfiguration.shared.storage.getOpenGroupPublicKey(for: request.server) else {
                return Promise(error: Error.noPublicKey)
            }
            
            if request.isAuthRequired {
                // Determine if we should be using legacy auth for this endpoint
                // TODO: Might need to store this at an OpenGroup level (so all requests can use the appropriate method)
                if request.endpoint.useLegacyAuth {
                    // Because legacy auth happens on a per-room basis, we need to have a room to
                    // make an authenticated request
                    guard let room = request.room else {
                        return OnionRequestAPI.sendOnionRequest(urlRequest, to: request.server, using: publicKey)
                    }
                    
                    return getAuthToken(for: room, on: request.server)
                        .then(on: OpenGroupAPIV2.workQueue) { authToken -> Promise<Data> in
                            urlRequest.setValue(authToken, forHTTPHeaderField: Header.authorization.rawValue)
                            
                            let promise = OnionRequestAPI.sendOnionRequest(urlRequest, to: request.server, using: publicKey)
                            promise.catch(on: OpenGroupAPIV2.workQueue) { error in
                                // A 401 means that we didn't provide a (valid) auth token for a route
                                // that required one. We use this as an indication that the token we're
                                // using has expired. Note that a 403 has a different meaning; it means
                                // that we provided a valid token but it doesn't have a high enough
                                // permission level for the route in question.
                                if case OnionRequestAPI.Error.httpRequestFailedAtDestination(let statusCode, _, _) = error, statusCode == 401 {
                                    let storage = SNMessagingKitConfiguration.shared.storage
                                    
                                    storage.writeSync { transaction in
                                        storage.removeAuthToken(for: room, on: request.server, using: transaction)
                                    }
                                }
                            }
                            
                            return promise
                        }
                }
                
                // Attempt to sign the request with the new auth
                guard let signedRequest: URLRequest = sign(urlRequest, with: publicKey) else {
                    return Promise(error: Error.signingFailed)
                }
                
                // TODO: 'removeAuthToken' as a migration??? (would previously do this when getting a `401`)
                return OnionRequestAPI.sendOnionRequest(signedRequest, to: request.server, using: publicKey)
            }
            
            return OnionRequestAPI.sendOnionRequest(urlRequest, to: request.server, using: publicKey)
        }
        
        preconditionFailure("It's currently not allowed to send non onion routed requests.")
    }
    
    public static func compactPoll(_ server: String) -> Promise<CompactPollResponse> {
        let storage: SessionMessagingKitStorageProtocol = SNMessagingKitConfiguration.shared.storage
        let rooms: [String] = storage.getAllV2OpenGroups().values
            .filter { $0.server == server }
            .map { $0.room }
        let useMessageLimit = (hasPerformedInitialPoll[server] != true && timeSinceLastOpen > OpenGroupPollerV2.maxInactivityPeriod)
        
        hasPerformedInitialPoll[server] = true
        
        if !hasUpdatedLastOpenDate {
            UserDefaults.standard[.lastOpen] = Date()
            hasUpdatedLastOpenDate = true
        }
        
        let requestBody: CompactPollBody = CompactPollBody(
            requests: rooms
                .map { roomId -> CompactPollBody.Room in
                    CompactPollBody.Room(
                        id: roomId,
                        fromMessageServerId: (useMessageLimit ? nil :
                            storage.getLastMessageServerID(for: roomId, on: server)
                        ),
                        fromDeletionServerId: (useMessageLimit ? nil :
                            storage.getLastDeletionServerID(for: roomId, on: server)
                        ),
                        legacyAuthToken: nil
                    )
                }
        )
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
    
        let request = Request(
            verb: .post,
            room: nil,
            server: server,
            endpoint: .legacyCompactPoll(legacyAuth: false),
            body: body,
            isAuthRequired: true
        )
        
        return send(request)
            .then(on: OpenGroupAPIV2.workQueue) { data -> Promise<CompactPollResponse> in
                let response: CompactPollResponse = try data.decoded(as: CompactPollResponse.self, customError: Error.parsingFailed)
                
                return when(
                    fulfilled: response.results
                        .map { (result: CompactPollResponse.Result) in
                            process(messages: result.messages, for: result.room, on: server)
                                .then(on: OpenGroupAPIV2.workQueue) { _ in
                                    process(deletions: result.deletions, for: result.room, on: server)
                                }
                        }
                ).then(on: OpenGroupAPIV2.workQueue) { _ in Promise.value(response) }
        }
    }
    
    public static func legacyCompactPoll(_ server: String) -> Promise<CompactPollResponse> {
        let storage: SessionMessagingKitStorageProtocol = SNMessagingKitConfiguration.shared.storage
        let rooms: [String] = storage.getAllV2OpenGroups().values
            .filter { $0.server == server }
            .map { $0.room }
        var getAuthTokenPromises: [String: Promise<String>] = [:]
        let useMessageLimit = (hasPerformedInitialPoll[server] != true && timeSinceLastOpen > OpenGroupPollerV2.maxInactivityPeriod)

        hasPerformedInitialPoll[server] = true
        
        if !hasUpdatedLastOpenDate {
            UserDefaults.standard[.lastOpen] = Date()
            hasUpdatedLastOpenDate = true
        }
        
        for room in rooms {
            getAuthTokenPromises[room] = getAuthToken(for: room, on: server)
        }
        
        let requestBody: CompactPollBody = CompactPollBody(
            requests: rooms
                .map { roomId -> CompactPollBody.Room in
                    CompactPollBody.Room(
                        id: roomId,
                        fromMessageServerId: (useMessageLimit ? nil :
                            storage.getLastMessageServerID(for: roomId, on: server)
                        ),
                        fromDeletionServerId: (useMessageLimit ? nil :
                            storage.getLastDeletionServerID(for: roomId, on: server)
                        ),
                        legacyAuthToken: nil
                    )
                }
        )
        
        return when(fulfilled: [Promise<String>](getAuthTokenPromises.values))
            .then(on: OpenGroupAPIV2.workQueue) { _ -> Promise<CompactPollResponse> in
                let requestBodyWithAuthTokens: CompactPollBody = CompactPollBody(
                    requests: requestBody.requests.compactMap { oldRoom -> CompactPollBody.Room? in
                        guard let authToken: String = getAuthTokenPromises[oldRoom.id]?.value else { return nil }
                        
                        return CompactPollBody.Room(
                            id: oldRoom.id,
                            fromMessageServerId: oldRoom.fromMessageServerId,
                            fromDeletionServerId: oldRoom.fromDeletionServerId,
                            legacyAuthToken: authToken
                        )
                    }
                )
                
                guard let body: Data = try? JSONEncoder().encode(requestBodyWithAuthTokens) else {
                    return Promise(error: HTTP.Error.invalidJSON)
                }
            
                let request = Request(
                    verb: .post,
                    room: nil,
                    server: server,
                    endpoint: .legacyCompactPoll(legacyAuth: true),
                    body: body,
                    isAuthRequired: false
                )
        
                return send(request)
                    .then(on: OpenGroupAPIV2.workQueue) { data -> Promise<CompactPollResponse> in
                        let response: CompactPollResponse = try data.decoded(as: CompactPollResponse.self, customError: Error.parsingFailed)

                        return when(
                            fulfilled: response.results
                                .compactMap { (result: CompactPollResponse.Result) -> Promise<[Deletion]>? in
                                    // A 401 means that we didn't provide a (valid) auth token for a route that
                                    // required one. We use this as an indication that the token we're using has
                                    // expired. Note that a 403 has a different meaning; it means that we provided
                                    // a valid token but it doesn't have a high enough permission level for the
                                    // route in question.
                                    guard result.statusCode != 401 else {
                                        storage.writeSync { transaction in
                                            storage.removeAuthToken(for: result.room, on: server, using: transaction)
                                        }
                                        
                                        return nil
                                    }
                                    
                                    return process(messages: result.messages, for: result.room, on: server)
                                        .then(on: OpenGroupAPIV2.workQueue) { _ ->  Promise<[Deletion]> in
                                            process(deletions: result.deletions, for: result.room, on: server)
                                        }
                                }
                        ).then(on: OpenGroupAPIV2.workQueue) { _ in Promise.value(response) }
                    }
            }
    }
    
    // MARK: - Authentication
    
    // TODO: Turn 'Sodium' and 'NonceGenerator16Byte' into protocols for unit testing
    static func sign(
        _ request: URLRequest,
        with publicKey: String,
        sodium: Sodium = Sodium(),
        nonceGenerator: NonceGenerator16Byte = NonceGenerator16Byte()
    ) -> URLRequest? {
        guard let path: String = request.url?.path else { return nil }
        
        var updatedRequest: URLRequest = request
        let method: String = (request.httpMethod ?? "GET")
        let timestamp: Int = Int(floor(Date().timeIntervalSince1970))
        let nonce: Data = Data(nonceGenerator.nonce())
        
        guard let publicKeyData: Data = publicKey.dataFromHex() else { return nil }
        guard let userKeyPair: ECKeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else {
            return nil
        }
//        guard let blindedKeyPair: ECKeyPair = try? userKeyPair.convert(to: .blinded, with: publicKey) else {
//            return nil
//        }
        // TODO: Change this back once you figure out why it's busted
        let blindedKeyPair: ECKeyPair = userKeyPair
        
        // Generate the sharedSecret by "aB || A || B" where
        // a, A are the users private and public keys respectively,
        // B is the SOGS public key
        let maybeSharedSecret: Data? = sodium.sharedSecret(blindedKeyPair.privateKey.bytes, publicKeyData.bytes)?
            .appending(blindedKeyPair.publicKey)
            .appending(publicKeyData.bytes)
        
        // Generate the hash to be sent along with the request
        //      intermediateHash = Blake2B(sharedSecret, size=42, salt=noncebytes, person='sogs.shared_keys')
        //      secretHash = Blake2B(
        //          Method || Path || Timestamp || Body,
        //          size=42,
        //          key=r,
        //          salt=noncebytes,
        //          person='sogs.auth_header'
        //      )
        let secretHashMessage: Bytes = method.bytes
            .appending(path.bytes)
            .appending("\(timestamp)".bytes)
            .appending(request.httpBody?.bytes ?? [])   // TODO: Might need to do the 'httpBodyStream' as well???
        
        guard let sharedSecret: Data = maybeSharedSecret else { return nil }
        guard let intermediateHash: Bytes = sodium.genericHash.hashSaltPersonal(message: sharedSecret.bytes, outputLength: 42, key: nil, salt: nonce.bytes, personal: Personalization.sharedKeys.bytes) else {
            return nil
        }
        guard let secretHash: Bytes = sodium.genericHash.hashSaltPersonal(message: secretHashMessage, outputLength: 42, key: intermediateHash, salt: nonce.bytes, personal: Personalization.authHeader.bytes) else {
            return nil
        }
        
        updatedRequest.allHTTPHeaderFields = (request.allHTTPHeaderFields ?? [:])
            .updated(with: [
                Header.sogsPubKey.rawValue: blindedKeyPair.hexEncodedPublicKey,
                Header.sogsTimestamp.rawValue: "\(timestamp)",
                Header.sogsNonce.rawValue: nonce.base64EncodedString(),
                Header.sogsHash.rawValue: secretHash.toBase64()
            ])
        
        return updatedRequest
    }
    
    private static func getAuthToken(for room: String, on server: String) -> Promise<String> {
        // TODO: Do we need to check the `/capabilities` of the SOGS to determine if it has new auth and if not then fall back to the old auth approach??????
        let storage = SNMessagingKitConfiguration.shared.storage

        if let authToken: String = storage.getAuthToken(for: room, on: server) {
            return Promise.value(authToken)
        }
        
        if let authTokenPromise: Promise<String> = authTokenPromises.wrappedValue["\(server).\(room)"] {
            return authTokenPromise
        }
        
        let promise: Promise<String> = requestNewAuthToken(for: room, on: server)
            .then(on: OpenGroupAPIV2.workQueue) { claimAuthToken($0, for: room, on: server) }
            .then(on: OpenGroupAPIV2.workQueue) { authToken -> Promise<String> in
                let (promise, seal) = Promise<String>.pending()
                storage.write(with: { transaction in
                    storage.setAuthToken(for: room, on: server, to: authToken, using: transaction)
                }, completion: {
                    seal.fulfill(authToken)
                })
                return promise
            }
        
        promise
            .done(on: OpenGroupAPIV2.workQueue) { _ in
                authTokenPromises.wrappedValue["\(server).\(room)"] = nil
            }
            .catch(on: OpenGroupAPIV2.workQueue) { _ in
                authTokenPromises.wrappedValue["\(server).\(room)"] = nil
            }
        
        authTokenPromises.wrappedValue["\(server).\(room)"] = promise
        return promise
    }

    public static func requestNewAuthToken(for room: String, on server: String) -> Promise<String> {
        SNLog("Requesting auth token for server: \(server).")
        guard let userKeyPair: ECKeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else {
            return Promise(error: Error.generic)
        }
        
        let request: Request = Request(
            verb: .get,
            room: room,
            server: server,
            endpoint: .legacyAuthTokenChallenge(legacyAuth: true),
            queryParameters: [
                .publicKey: getUserHexEncodedPublicKey()
            ],
            isAuthRequired: false
        )
        
        return send(request).map(on: OpenGroupAPIV2.workQueue) { data in
            let response = try data.decoded(as: AuthTokenResponse.self, customError: Error.parsingFailed)
            let symmetricKey = try AESGCM.generateSymmetricKey(x25519PublicKey: response.challenge.ephemeralPublicKey, x25519PrivateKey: userKeyPair.privateKey)
            
            guard let tokenAsData = try? AESGCM.decrypt(response.challenge.ciphertext, with: symmetricKey) else {
                throw Error.decryptionFailed
            }
            
            return tokenAsData.toHexString()
        }
    }

    public static func claimAuthToken(_ authToken: String, for room: String, on server: String) -> Promise<String> {
        let requestBody: PublicKeyBody = PublicKeyBody(publicKey: getUserHexEncodedPublicKey())

        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }

        let request: Request = Request(
            verb: .post,
            room: room,
            server: server,
            endpoint: .legacyAuthTokenClaim(legacyAuth: true),
            body: body,
            headers: [
                // Set explicitly here because is isn't in the database yet at this point
                .authorization: authToken
            ],
            isAuthRequired: false
        )

        return send(request).map(on: OpenGroupAPIV2.workQueue) { _ in authToken }
    }

    /// Should be called when leaving a group.
    public static func deleteAuthToken(for room: String, on server: String) -> Promise<Void> {
        let request: Request = Request(
            verb: .delete,
            room: room,
            server: server,
            endpoint: .legacyAuthToken(legacyAuth: true)
        )
        
        return send(request).map(on: OpenGroupAPIV2.workQueue) { _ in
            let storage = SNMessagingKitConfiguration.shared.storage
            
            storage.write { transaction in
                storage.removeAuthToken(for: room, on: server, using: transaction)
            }
        }
    }
    
    // MARK: - File Storage
    
    public static func upload(_ file: Data, to room: String, on server: String) -> Promise<UInt64> {
        let requestBody: FileUploadBody = FileUploadBody(file: file.base64EncodedString())
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        let request = Request(verb: .post, room: room, server: server, endpoint: .files, body: body)
        
        return send(request).map(on: OpenGroupAPIV2.workQueue) { data in
            let response: FileUploadResponse = try data.decoded(as: FileUploadResponse.self, customError: Error.parsingFailed)
            
            return response.fileId
        }
    }
    
    public static func download(_ file: UInt64, from room: String, on server: String) -> Promise<Data> {
        let request = Request(verb: .get, room: room, server: server, endpoint: .file(file))
        
        return send(request).map(on: OpenGroupAPIV2.workQueue) { data in
            let response: FileDownloadResponse = try data.decoded(as: FileDownloadResponse.self, customError: Error.parsingFailed)
            
            return response.data
        }
    }
    
    // MARK: - Message Sending & Receiving
    
    public static func send(_ message: OpenGroupMessageV2, to room: String, on server: String, with publicKey: String) -> Promise<OpenGroupMessageV2> {
        // TODO: Test if we need a legacy version
        guard let signedMessage = message.sign(with: publicKey) else { return Promise(error: Error.signingFailed) }
        guard let body: Data = try? JSONEncoder().encode(signedMessage) else {
            return Promise(error: Error.parsingFailed)
        }
        let request = Request(verb: .post, room: room, server: server, endpoint: .messages, body: body)
        
        return send(request).map(on: OpenGroupAPIV2.workQueue) { data in
            let message: OpenGroupMessageV2 = try data.decoded(as: OpenGroupMessageV2.self, customError: Error.parsingFailed)
            Storage.shared.write { transaction in
                Storage.shared.addReceivedMessageTimestamp(message.sentTimestamp, using: transaction)
            }
            return message
        }
    }
    
    public static func getMessages(for room: String, on server: String) -> Promise<[OpenGroupMessageV2]> {
        let storage = SNMessagingKitConfiguration.shared.storage
        let request: Request = Request(
            verb: .get,
            room: room,
            server: server,
            endpoint: .messages,
            queryParameters: [
                .fromServerId: storage.getLastMessageServerID(for: room, on: server).map { String($0) }
            ].compactMapValues { $0 }
        )
        
        return send(request).then(on: OpenGroupAPIV2.workQueue) { data -> Promise<[OpenGroupMessageV2]> in
            let messages: [OpenGroupMessageV2] = try data.decoded(as: [OpenGroupMessageV2].self, customError: Error.parsingFailed)
            
            return process(messages: messages, for: room, on: server)
        }
    }
    
    private static func process(messages: [OpenGroupMessageV2]?, for room: String, on server: String) -> Promise<[OpenGroupMessageV2]> {
        guard let messages: [OpenGroupMessageV2] = messages, !messages.isEmpty else { return Promise.value([]) }
        
        let storage = SNMessagingKitConfiguration.shared.storage
        let serverID: Int64 = (messages.compactMap { $0.serverID }.max() ?? 0)
        let lastMessageServerID: Int64 = (storage.getLastMessageServerID(for: room, on: server) ?? 0)
        
        if serverID > lastMessageServerID {
            let (promise, seal) = Promise<[OpenGroupMessageV2]>.pending()
            
            storage.write(
                with: { transaction in
                    storage.setLastMessageServerID(for: room, on: server, to: serverID, using: transaction)
                },
                completion: {
                    seal.fulfill(messages)
                }
            )
            
            return promise
        }
        
        return Promise.value(messages)
    }
    
    // MARK: - Message Deletion
    
    public static func deleteMessage(with serverID: Int64, from room: String, on server: String) -> Promise<Void> {
        let request: Request = Request(
            verb: .delete,
            room: room,
            server: server,
            endpoint: .messagesForServer(serverID)
        )
        // TODO: Legacy version?
        return send(request).map(on: OpenGroupAPIV2.workQueue) { _ in }
    }
    
    public static func getDeletedMessages(for room: String, on server: String) -> Promise<[Deletion]> {
        let storage = SNMessagingKitConfiguration.shared.storage
        
        let request: Request = Request(
            verb: .get,
            room: room,
            server: server,
            endpoint: .deletedMessages,
            queryParameters: [
                .fromServerId: storage.getLastDeletionServerID(for: room, on: server).map { String($0) }
            ].compactMapValues { $0 }
        )
        // TODO: Legacy version?
        return send(request).then(on: OpenGroupAPIV2.workQueue) { data -> Promise<[Deletion]> in
            let response: DeletedMessagesResponse = try data.decoded(as: DeletedMessagesResponse.self, customError: Error.parsingFailed)
            
            return process(deletions: response.deletions, for: room, on: server)
        }
    }
    
    private static func process(deletions: [Deletion]?, for room: String, on server: String) -> Promise<[Deletion]> {
        guard let deletions: [Deletion] = deletions else { return Promise.value([]) }
        
        let storage = SNMessagingKitConfiguration.shared.storage
        let serverID: Int64 = (deletions.compactMap { $0.id }.max() ?? 0)
        let lastDeletionServerID: Int64 = (storage.getLastDeletionServerID(for: room, on: server) ?? 0)
        
        if serverID > lastDeletionServerID {
            let (promise, seal) = Promise<[Deletion]>.pending()
            
            storage.write(
                with: { transaction in
                    storage.setLastDeletionServerID(for: room, on: server, to: serverID, using: transaction)
                },
                completion: {
                    seal.fulfill(deletions)
                }
            )
            
            return promise
        }
        
        return Promise.value(deletions)
    }
    
    // MARK: - Moderation
    
    public static func getModerators(for room: String, on server: String) -> Promise<[String]> {
        let request: Request = Request(
            verb: .get,
            room: room,
            server: server,
            endpoint: .moderators
        )
        // TODO: Legacy version?
        return send(request)
            .map(on: OpenGroupAPIV2.workQueue) { data in
                let response: ModeratorsResponse = try data.decoded(as: ModeratorsResponse.self, customError: Error.parsingFailed)
                
                if var x = self.moderators[server] {
                    x[room] = Set(response.moderators)
                    self.moderators[server] = x
                }
                else {
                    self.moderators[server] = [room: Set(response.moderators)]
                }
                
                return response.moderators
            }
    }
    
    public static func ban(_ publicKey: String, from room: String, on server: String) -> Promise<Void> {
        let requestBody: PublicKeyBody = PublicKeyBody(publicKey: getUserHexEncodedPublicKey())
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        // TODO: Legacy version?
        let request: Request = Request(
            verb: .post,
            room: room,
            server: server,
            endpoint: .blockList,
            body: body
        )
        
        return send(request).map(on: OpenGroupAPIV2.workQueue) { _ in }
    }
    
    public static func banAndDeleteAllMessages(_ publicKey: String, from room: String, on server: String) -> Promise<Void> {
        let requestBody: PublicKeyBody = PublicKeyBody(publicKey: getUserHexEncodedPublicKey())
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        // TODO: Legacy version?
        let request: Request = Request(
            verb: .post,
            room: room,
            server: server,
            endpoint: .banAndDeleteAll,
            body: body
        )
        
        return send(request).map(on: OpenGroupAPIV2.workQueue) { _ in }
    }
    
    public static func unban(_ publicKey: String, from room: String, on server: String) -> Promise<Void> {
        let request: Request = Request(
            verb: .delete,
            room: room,
            server: server,
            endpoint: .blockListIndividual(publicKey)
        )
        // TODO: Legacy version?
        return send(request).map(on: OpenGroupAPIV2.workQueue) { _ in }
    }

    public static func isUserModerator(_ publicKey: String, for room: String, on server: String) -> Bool {
        return moderators[server]?[room]?.contains(publicKey) ?? false
    }
    
    // MARK: - General
    
    public static func getDefaultRoomsIfNeeded() {
        Storage.shared.write(
            with: { transaction in
                Storage.shared.setOpenGroupPublicKey(for: defaultServer, to: defaultServerPublicKey, using: transaction)
            },
            completion: {
                let promise = attempt(maxRetryCount: 8, recoveringOn: DispatchQueue.main) {
                    OpenGroupAPIV2.getAllRooms(from: defaultServer)
                }
                _ = promise.done(on: OpenGroupAPIV2.workQueue) { items in
                    items.forEach { getGroupImage(for: $0.id, on: defaultServer).retainUntilComplete() }
                }
                promise.catch(on: OpenGroupAPIV2.workQueue) { _ in
                    OpenGroupAPIV2.defaultRoomsPromise = nil
                }
                defaultRoomsPromise = promise
            }
        )
    }
    
    public static func getInfo(for room: String, on server: String) -> Promise<RoomInfo> {
        let request: Request = Request(
            verb: .get,
            room: room,
            server: server,
            endpoint: .roomInfo(room),
            isAuthRequired: false
        )
        
        return send(request)
            .map(on: OpenGroupAPIV2.workQueue) { data in
                let response: GetInfoResponse = try data.decoded(as: GetInfoResponse.self, customError: Error.parsingFailed)
                
                return response.room
            }
    }
    
    public static func getAllRooms(from server: String) -> Promise<[RoomInfo]> {
        let request: Request = Request(
            verb: .get,
            room: nil,
            server: server,
            endpoint: .rooms,
            isAuthRequired: false
        )
        
        return send(request)
            .map(on: OpenGroupAPIV2.workQueue) { data in
                let response: RoomsResponse = try data.decoded(as: RoomsResponse.self, customError: Error.parsingFailed)
                
                return response.rooms
            }
    }
    
    public static func getMemberCount(for room: String, on server: String) -> Promise<UInt64> {
        let request: Request = Request(
            verb: .get,
            room: room,
            server: server,
            endpoint: .legacyMemberCount(legacyAuth: true)
        )
        // TODO: Non-legacy version?
        return send(request)
            .map(on: OpenGroupAPIV2.workQueue) { data in
                let response: MemberCountResponse = try data.decoded(as: MemberCountResponse.self, customError: Error.parsingFailed)
                
                let storage = SNMessagingKitConfiguration.shared.storage
                storage.write { transaction in
                    storage.setUserCount(to: response.memberCount, forV2OpenGroupWithID: "\(server).\(room)", using: transaction)
                }
                
                return response.memberCount
            }
    }
    
    public static func getGroupImage(for room: String, on server: String) -> Promise<Data> {
        // Normally the image for a given group is stored with the group thread, so it's only
        // fetched once. However, on the join open group screen we show images for groups the
        // user * hasn't * joined yet. We don't want to re-fetch these images every time the
        // user opens the app because that could slow the app down or be data-intensive. So
        // instead we assume that these images don't change that often and just fetch them once
        // a week. We also assume that they're all fetched at the same time as well, so that
        // we only need to maintain one date in user defaults. On top of all of this we also
        // don't double up on fetch requests by storing the existing request as a promise if
        // there is one.
        let lastOpenGroupImageUpdate: Date? = UserDefaults.standard[.lastOpenGroupImageUpdate]
        let now: Date = Date()
        let timeSinceLastUpdate: TimeInterval = (given(lastOpenGroupImageUpdate) { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude)
        let updateInterval: TimeInterval = (7 * 24 * 60 * 60)
        
        if let data = Storage.shared.getOpenGroupImage(for: room, on: server), server == defaultServer, timeSinceLastUpdate < updateInterval {
            return Promise.value(data)
        }
        
        if let promise = groupImagePromises["\(server).\(room)"] {
            return promise
        }
        
        let request: Request = Request(
            verb: .get,
            room: room,
            server: server,
            endpoint: .roomImage(room),
            isAuthRequired: false
        )
        // TODO: Legacy version (doesn't work on new SOGS)
        let promise: Promise<Data> = send(request).map(on: OpenGroupAPIV2.workQueue) { data in
            let response: FileDownloadResponse = try data.decoded(as: FileDownloadResponse.self, customError: Error.parsingFailed)
            
            if server == defaultServer {
                Storage.shared.write { transaction in
                    Storage.shared.setOpenGroupImage(to: response.data, for: room, on: server, using: transaction)
                }
                UserDefaults.standard[.lastOpenGroupImageUpdate] = now
            }
            
            return response.data
        }
        groupImagePromises["\(server).\(room)"] = promise
        
        return promise
    }
}
