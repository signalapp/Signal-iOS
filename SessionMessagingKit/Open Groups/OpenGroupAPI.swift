import PromiseKit
import SessionSnodeKit
import Sodium
import Curve25519Kit

@objc(SNOpenGroupAPI)
public final class OpenGroupAPI: NSObject {
    
    // MARK: - Settings
    
    public static let defaultServer = "http://116.203.70.33"
    public static let defaultServerPublicKey = "a03c383cf63c3c4efe67acc52112a6dd734b3a946b9545f488aaa93da7991238"
    
    public static let workQueue = DispatchQueue(label: "OpenGroupAPI.workQueue", qos: .userInitiated) // It's important that this is a serial queue
    
    // MARK: - Polling State
    
    private static var hasPerformedInitialPoll: [String: Bool] = [:]
    private static var timeSinceLastPoll: [String: TimeInterval] = [:]
    private static var lastPollTime: TimeInterval = .greatestFiniteMagnitude

    private static let timeSinceLastOpen: TimeInterval = {
        guard let lastOpen = UserDefaults.standard[.lastOpen] else { return .greatestFiniteMagnitude }
        
        return Date().timeIntervalSince(lastOpen)
    }()
    
    
    // TODO: Remove these
    private static var legacyAuthTokenPromises: Atomic<[String: Promise<String>]> = Atomic([:])
    private static var legacyHasUpdatedLastOpenDate = false
    private static var legacyGroupImagePromises: [String: Promise<Data>] = [:]
    

    // MARK: - Batching & Polling
    
    /// This is a convenience method which calls `/batch` with a pre-defined set of requests used to update an Open
    /// Group, currently this will retrieve:
    /// - Capabilities for the server
    /// - For each room:
    ///    - Poll Info
    ///    - Messages (includes additions and deletions)
    public static func poll(_ server: String, using dependencies: Dependencies = Dependencies()) -> Promise<[Endpoint: (OnionRequestResponseInfoType, Codable)]> {
        // Store a local copy of the cached state for this server
        let hadPerformedInitialPoll: Bool = (hasPerformedInitialPoll[server] == true)
        let originalTimeSinceLastPoll: TimeInterval = (timeSinceLastPoll[server] ?? min(lastPollTime, timeSinceLastOpen))
        
        // Update the cached state for this server
        hasPerformedInitialPoll[server] = true
        lastPollTime = min(lastPollTime, timeSinceLastOpen)
        UserDefaults.standard[.lastOpen] = Date()
        
        // Generate the requests
        let requestResponseType: [BatchRequestInfo] = [
            BatchRequestInfo(
                request: Request(
                    server: server,
                    endpoint: .capabilities,
                    queryParameters: [:] // TODO: Add any requirements '.required'
                ),
                responseType: Capabilities.self
            )
        ]
        .appending(
            dependencies.storage.getAllOpenGroups().values
                .filter { $0.server == server.lowercased() }    // Note: The `OpenGroup` type converts to lowercase in init
                .flatMap { openGroup -> [BatchRequestInfo] in
                    let lastSeqNo: Int64? = dependencies.storage.getLastMessageServerID(for: openGroup.room, on: server)
                    let targetSeqNo: Int64 = (lastSeqNo ?? 0)
                    let shouldRetrieveRecentMessages: Bool = (
                        lastSeqNo == nil || (
                            // If it's the first poll for this launch and it's been longer than
                            // 'maxInactivityPeriod' then just retrieve recent messages instead
                            // of trying to get all messages since the last one retrieved
                            !hadPerformedInitialPoll &&
                            originalTimeSinceLastPoll > OpenGroupAPI.Poller.maxInactivityPeriod
                        )
                    )
                    
                    return [
                        BatchRequestInfo(
                            request: Request(
                                server: server,
                                endpoint: .roomPollInfo(openGroup.room, openGroup.infoUpdates)
                            ),
                            responseType: RoomPollInfo.self
                        ),
                        BatchRequestInfo(
                            request: Request(
                                server: server,
                                endpoint: (shouldRetrieveRecentMessages ?
                                    .roomMessagesRecent(openGroup.room) :
                                    .roomMessagesSince(openGroup.room, seqNo: targetSeqNo)
                                )
                                // TODO: Limit?
//                                queryParameters: [ .limit: 256 ]
                            ),
                            responseType: [Message].self
                        )
                    ]
                }
        )
        
        return batch(server, requests: requestResponseType, using: dependencies)
    }
    
    /// This is used, for example, to poll multiple rooms on the same server for updates in a single query rather than needing to make multiple requests for each room.
    ///
    /// No guarantee is made as to the order in which sub-requests are processed; use the `/sequence` instead if you need that.
    ///
    /// For contained subrequests that specify a body (i.e. POST or PUT requests) exactly one of `json`, `b64`, or `bytes` must be provided with the request body.
    private static func batch(_ server: String, requests: [BatchRequestInfo], using dependencies: Dependencies = Dependencies()) -> Promise<[Endpoint: (OnionRequestResponseInfoType, Codable)]> {
        let requestBody: BatchRequest = requests.map { BatchSubRequest(request: $0.request) }
        let responseTypes = requests.map { $0.responseType }
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .batch,
            body: body
        )
        
        return send(request, using: dependencies)
            .decoded(as: responseTypes, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
            .map { result in
                result.enumerated()
                    .reduce(into: [:]) { prev, next in
                        prev[requests[next.offset].request.endpoint] = next.element
                    }
            }
    }
    
    /// The requests are guaranteed to be performed sequentially in the order given in the request and will abort if any request does not return a status-`2xx` response.
    ///
    /// For example, this can be used to ban and delete all of a user's messages by sequencing the ban followed by the `delete_all`: if the ban fails (e.g. because
    /// permission is denied) then the `delete_all` will not occur. The batch body and response are identical to the `/batch` endpoint; requests that are not
    /// carried out because of an earlier failure will have a response code of `412` (Precondition Failed)."
    private static func sequence(_ server: String, requests: [BatchRequestInfo], using dependencies: Dependencies = Dependencies()) -> Promise<[Endpoint: (OnionRequestResponseInfoType, Codable)]> {
        let requestBody: BatchRequest = requests.map { BatchSubRequest(request: $0.request) }
        let responseTypes = requests.map { $0.responseType }
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .sequence,
            body: body
        )
        
        // TODO: Handle a `412` response (ie. a required capability isn't supported)
        return send(request, using: dependencies)
            .decoded(as: responseTypes, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
            .map { result in
                result.enumerated()
                    .reduce(into: [:]) { prev, next in
                        prev[requests[next.offset].request.endpoint] = next.element
                    }
            }
    }
    
    // MARK: - Capabilities
    
    public static func capabilities(on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, Capabilities)> {
        let request: Request = Request(
            server: server,
            endpoint: .capabilities,
            queryParameters: [:] // TODO: Add any requirements '.required'.
        )
        
        // TODO: Handle a `412` response (ie. a required capability isn't supported)
        return send(request, using: dependencies)
            .decoded(as: Capabilities.self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    // MARK: - Room
    
    public static func rooms(for server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, [Room])> {
        let request: Request = Request(
            server: server,
            endpoint: .rooms
        )
        
        return send(request, using: dependencies)
            .decoded(as: [Room].self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    public static func room(for roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, Room)> {
        let request: Request = Request(
            server: server,
            endpoint: .room(roomToken)
        )
        
        return send(request, using: dependencies)
            .decoded(as: Room.self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    public static func roomPollInfo(lastUpdated: Int64, for roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, RoomPollInfo)> {
        let request: Request = Request(
            server: server,
            endpoint: .roomPollInfo(roomToken, lastUpdated)
        )
        
        return send(request, using: dependencies)
            .decoded(as: RoomPollInfo.self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    // MARK: - Messages
    
    public static func send(
        _ plaintext: Data,
        to roomToken: String,
        on server: String,
        whisperTo: String?,
        whisperMods: Bool,
        using dependencies: Dependencies = Dependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Message)> {
        guard let signedMessage: (data: Data, signature: Data) = sign(message: plaintext, to: roomToken, on: server, using: dependencies) else {
            return Promise(error: Error.signingFailed)
        }
        
        let requestBody: SendMessageRequest = SendMessageRequest(
            data: signedMessage.data,
            signature: signedMessage.signature,
            whisperTo: whisperTo,
            whisperMods: whisperMods,
            fileIds: nil // TODO: Add support for 'fileIds'.
        )
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: Error.parsingFailed)
        }
        
        let request = Request(
            method: .post,
            server: server,
            endpoint: .roomMessage(roomToken),
            body: body
        )
        
        return send(request, using: dependencies)
            .decoded(as: Message.self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    public static func message(_ id: Int64, in roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, Message)> {
        let request: Request = Request(
            server: server,
            endpoint: .roomMessageIndividual(roomToken, id: id)
        )

        return send(request, using: dependencies)
            .decoded(as: Message.self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    public static func messageUpdate(
        _ id: Int64,
        plaintext: Data,
        in roomToken: String,
        on server: String,
        using dependencies: Dependencies = Dependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        guard let signedMessage: (data: Data, signature: Data) = sign(message: plaintext, to: roomToken, on: server, using: dependencies) else {
            return Promise(error: Error.signingFailed)
        }
        
        let requestBody: UpdateMessageRequest = UpdateMessageRequest(
            data: signedMessage.data,
            signature: signedMessage.signature
        )
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: Error.parsingFailed)
        }
        
        let request: Request = Request(
            method: .put,
            server: server,
            endpoint: .roomMessageIndividual(roomToken, id: id),
            body: body
        )

        // TODO: Handle custom response info?
        return send(request, using: dependencies)
    }

    /// This is the direct request to retrieve recent messages from an Open Group so should be retrieved automatically from the `poll()`
    /// method, if the logic should change then remove the `@available` line and make sure to route the response of this method to
    /// the `OpenGroupManager` `handleMessages` method (otherwise the logic may not work correctly)
    @available(*, unavailable, message: "Avoid using this directly, use the pre-build `poll()` method instead")
    public static func recentMessages(in roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, [Message])> {
        let request: Request = Request(
            server: server,
            endpoint: .roomMessagesRecent(roomToken)
            // TODO: Limit?.
//            queryParameters: [ .limit: 50 ]
        )

        return send(request, using: dependencies)
            .decoded(as: [Message].self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    /// This is the direct request to retrieve recent messages from an Open Group so should be retrieved automatically from the `poll()`
    /// method, if the logic should change then remove the `@available` line and make sure to route the response of this method to
    /// the `OpenGroupManager` `handleMessages` method (otherwise the logic may not work correctly)
    @available(*, unavailable, message: "Avoid using this directly, use the pre-build `poll()` method instead")
    public static func messagesBefore(messageId: Int64, in roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, [Message])> {
        // TODO: Do we need to be able to load old messages?
        let request: Request = Request(
            server: server,
            endpoint: .roomMessagesBefore(roomToken, id: messageId)
            // TODO: Limit?.
//            queryParameters: [ .limit: 50 ]
        )

        return send(request, using: dependencies)
            .decoded(as: [Message].self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    /// This is the direct request to retrieve recent messages from an Open Group so should be retrieved automatically from the `poll()`
    /// method, if the logic should change then remove the `@available` line and make sure to route the response of this method to
    /// the `OpenGroupManager` `handleMessages` method (otherwise the logic may not work correctly)
    @available(*, unavailable, message: "Avoid using this directly, use the pre-build `poll()` method instead")
    public static func messagesSince(seqNo: Int64, in roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, [Message])> {
        let request: Request = Request(
            server: server,
            endpoint: .roomMessagesSince(roomToken, seqNo: seqNo)
            // TODO: Limit?.
//            queryParameters: [ .limit: 50 ]
        )

        return send(request, using: dependencies)
            .decoded(as: [Message].self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    // MARK: - Pinning
    
    public static func pinMessage(id: Int64, in roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<OnionRequestResponseInfoType> {
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .roomPinMessage(roomToken, id: id)
        )

        return send(request, using: dependencies)
            .map { responseInfo, _ in responseInfo }
    }
    
    public static func unpinMessage(id: Int64, in roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<OnionRequestResponseInfoType> {
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .roomUnpinMessage(roomToken, id: id)
        )

        return send(request, using: dependencies)
            .map { responseInfo, _ in responseInfo }
    }

    public static func unpinAll(in roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<OnionRequestResponseInfoType> {
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .roomUnpinAll(roomToken)
        )

        return send(request, using: dependencies)
            .map { responseInfo, _ in responseInfo }
    }
    
    // MARK: - Files
    
    public static func uploadFile(_ bytes: [UInt8], fileName: String? = nil, to roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, FileUploadResponse)> {
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .roomFile(roomToken),
            headers: [ .fileName: fileName ].compactMapValues { $0 },
            body: Data(bytes)
        )
        
        return send(request, using: dependencies)
            .decoded(as: FileUploadResponse.self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    /// Warning: This approach is less efficient as it expects the data to be base64Encoded (with is 33% larger than binary), please use the binary approach
    /// whenever possible
    public static func uploadFile(_ base64EncodedString: String, fileName: String? = nil, to roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, FileUploadResponse)> {
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .roomFileJson(roomToken),
            headers: [ .fileName: fileName ].compactMapValues { $0 },
            body: Data(base64Encoded: base64EncodedString)
        )
        
        return send(request, using: dependencies)
            .decoded(as: FileUploadResponse.self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    public static func downloadFile(_ fileId: Int64, from roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, Data)> {
        let request: Request = Request(
            server: server,
            endpoint: .roomFileIndividual(roomToken, fileId)
        )
        
        return send(request, using: dependencies)
            .map { responseInfo, maybeData in
                guard let data: Data = maybeData else { throw Error.parsingFailed }
                
                return (responseInfo, data)
            }
    }
    
    public static func downloadFileJson(_ fileId: Int64, from roomToken: String, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, FileDownloadResponse)> {
        let request: Request = Request(
            server: server,
            endpoint: .roomFileIndividualJson(roomToken, fileId)
        )
        // TODO: This endpoint is getting rewritten to return just data (properties would come through as headers).
        return send(request, using: dependencies)
            .decoded(as: FileDownloadResponse.self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    // MARK: - Inbox (Message Requests)

    public static func messageRequests(on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, [DirectMessage])> {
        let request: Request = Request(
            server: server,
            endpoint: .inbox
        )
        
        return send(request, using: dependencies)
            .decoded(as: [DirectMessage].self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    public static func messageRequestsSince(id: Int64, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, [DirectMessage])> {
        let request: Request = Request(
            server: server,
            endpoint: .inboxSince(id: id)
        )
        
        return send(request, using: dependencies)
            .decoded(as: [DirectMessage].self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    public static func sendMessageRequest(_ plaintext: Data, to blindedSessionId: String, on server: String, with serverPublicKey: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, [DirectMessage])> {
        guard let signedMessage: Data = sign(message: plaintext, to: blindedSessionId, on: server, with: serverPublicKey, using: dependencies) else {
            return Promise(error: Error.signingFailed)
        }
        
        let requestBody: SendDirectMessageRequest = SendDirectMessageRequest(
            data: signedMessage
//            signature: signedMessage.signature    // TODO: Confirm whether this needs a signature??
        )
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: Error.parsingFailed)
        }
        
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .inboxFor(sessionId: blindedSessionId),
            body: body
        )
        
        return send(request, using: dependencies)
            .decoded(as: [DirectMessage].self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    // MARK: - Users
    
    public static func userBan(_ sessionId: String, for timeout: TimeInterval? = nil, from roomTokens: [String]? = nil, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        let requestBody: UserBanRequest = UserBanRequest(
            rooms: roomTokens,
            global: (roomTokens == nil ? true : nil),
            timeout: timeout
        )
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: Error.parsingFailed)
        }
        
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .userBan(sessionId),
            body: body
        )
        
        return send(request, using: dependencies)
    }
    
    public static func userUnban(_ sessionId: String, from roomTokens: [String]? = nil, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        let requestBody: UserUnbanRequest = UserUnbanRequest(
            rooms: roomTokens,
            global: (roomTokens == nil ? true : nil)
        )
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: Error.parsingFailed)
        }
        
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .userUnban(sessionId),
            body: body
        )
        
        return send(request, using: dependencies)
    }
    
    public static func userPermissionUpdate(_ sessionId: String, read: Bool, write: Bool, upload: Bool, for roomTokens: [String], timeout: TimeInterval, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        let requestBody: UserPermissionsRequest = UserPermissionsRequest(
            rooms: roomTokens,
            timeout: timeout,
            read: read,
            write: write,
            upload: upload
        )
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: Error.parsingFailed)
        }
        
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .userPermission(sessionId),
            body: body
        )
        
        return send(request, using: dependencies)
    }
    
    public static func userModeratorUpdate(_ sessionId: String, moderator: Bool, admin: Bool, visible: Bool, for roomTokens: [String]? = nil, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        let requestBody: UserModeratorRequest = UserModeratorRequest(
            rooms: roomTokens,
            global: (roomTokens == nil ? true : nil),
            moderator: moderator,
            admin: admin,
            visible: visible
        )
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: Error.parsingFailed)
        }
        
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .userModerator(sessionId),
            body: body
        )
        
        return send(request, using: dependencies)
    }
    
    public static func userDeleteMessages(_ sessionId: String, for roomTokens: [String]? = nil, on server: String, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, UserDeleteMessagesResponse)> {
        let requestBody: UserDeleteMessagesRequest = UserDeleteMessagesRequest(
            rooms: roomTokens,
            global: (roomTokens == nil ? true : nil)
        )
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: Error.parsingFailed)
        }
        
        let request: Request = Request(
            method: .post,
            server: server,
            endpoint: .userDeleteMessages(sessionId),
            body: body
        )
        
        return send(request, using: dependencies)
            .decoded(as: UserDeleteMessagesResponse.self, on: OpenGroupAPI.workQueue, error: Error.parsingFailed)
    }
    
    // MARK: - Authentication
    
    /// Sign a message to be sent to SOGS (handles both un-blinded and blinded signing based on the server capabilities)
    public static func sign(message: Data, to roomToken: String, on serverName: String, using dependencies: Dependencies = Dependencies()) -> (data: Data, signature: Data)? {
        let server: Server? = dependencies.storage.getOpenGroupServer(name: serverName)
        let targetKeyPair: ECKeyPair

        // Determine if we want to sign using standard or blinded keys based on the server capabilities (assume
        // unblinded if we have none)
        // TODO: Remove this (blinding will be required)
        if server?.capabilities.capabilities.contains(.blinding) == true {
            // TODO: Validate this 'openGroupId' is correct for the 'getOpenGroup' call
            let openGroupId: String = "\(serverName).\(roomToken)"
            
            // TODO: Validate this is the correct logic (Most likely not)
            guard let openGroup: OpenGroup = Storage.shared.getOpenGroup(for: openGroupId) else { return nil }
            guard let userEdKeyPair: Box.KeyPair = dependencies.storage.getUserED25519KeyPair() else { return nil }
            guard let blindedKeyPair: Box.KeyPair = dependencies.sodium.blindedKeyPair(serverPublicKey: openGroup.publicKey, edKeyPair: userEdKeyPair, genericHash: dependencies.genericHash) else {
                return nil
            }

            targetKeyPair = blindedKeyPair
        }
        else {
            guard let userKeyPair: ECKeyPair = dependencies.storage.getUserKeyPair() else { return nil }

            targetKeyPair = userKeyPair
        }
        
        guard let signature = try? Ed25519.sign(message, with: targetKeyPair) else {
            SNLog("Failed to sign open group message.")
            return nil
        }
        
        return (message, signature)
    }
    
    /// Sign a blinded message request to be sent to a users inbox via SOGS v4
    private static func sign(message: Data, to blindedSessionId: String, on serverName: String, with serverPublicKey: String, using dependencies: Dependencies = Dependencies()) -> Data? {
        guard let userEdKeyPair: Box.KeyPair = dependencies.storage.getUserED25519KeyPair() else { return nil }
        guard let blindedKeyPair: BlindedECKeyPair = dependencies.sodium.blindedKeyPair(serverPublicKey: serverPublicKey, edKeyPair: userEdKeyPair, genericHash: dependencies.genericHash) else {
            return nil
        }
        guard let blindedRecipientPublicKey: Data = String(blindedSessionId.suffix(from: blindedSessionId.index(blindedSessionId.startIndex, offsetBy: IdPrefix.blinded.rawValue.count))).dataFromHex() else {
            return nil
        }
        
        /// Generate the sharedSecret by "a kB || kA || kB" where
        /// a, A are the users private and public keys respectively,
        /// kA is the users blinded public key
        /// kB is the recipients blinded public key
        let maybeSharedSecret: Data? = dependencies.sodium
            .sharedEdSecret(userEdKeyPair.secretKey, blindedRecipientPublicKey.bytes)?
            .appending(blindedKeyPair.publicKey.bytes)
            .appending(blindedRecipientPublicKey.bytes)
        
        guard let sharedSecret: Data = maybeSharedSecret else { return nil }
        guard let intermediateHash: Bytes = dependencies.genericHash.hash(message: sharedSecret.bytes) else { return nil }
        
        /// Generate the inner message by "message || A" where
        /// A is the sender's ed25519 master pubkey (**not** kA blinded pubkey)
        let innerMessage: Bytes = (message.bytes + userEdKeyPair.publicKey)
        guard let (ciphertext, nonce) = dependencies.aeadXChaCha20Poly1305Ietf.encrypt(message: innerMessage, secretKey: intermediateHash) else {
            return nil
        }
        
        /// Generate the final data by "b'\x00' + ciphertext + nonce"
        let finalData: Bytes = [0] + ciphertext + nonce
        
        return Data(finalData)
    }
    
    /// Sign a request to be sent to SOGS (handles both un-blinded and blinded signing based on the server capabilities)
    private static func sign(_ request: URLRequest, for serverName: String, with serverPublicKey: String, using dependencies: Dependencies = Dependencies()) -> URLRequest? {
        guard let url: URL = request.url else { return nil }
        
        var updatedRequest: URLRequest = request
        let path: String = url.path
            .appending(url.query.map { value in "?\(value)" })
        let method: String = (request.httpMethod ?? "GET")
        let timestamp: Int = Int(floor(dependencies.date.timeIntervalSince1970))
        let nonce: Data = Data(dependencies.nonceGenerator.nonce())
        let server: Server? = dependencies.storage.getOpenGroupServer(name: serverName)
        let userPublicKeyHex: String
        let signatureBytes: Bytes
        
        guard let serverPublicKeyData: Data = serverPublicKey.dataFromHex() else { return nil }
        guard let timestampBytes: Bytes = "\(timestamp)".data(using: .ascii)?.bytes else { return nil }
        guard let userEdKeyPair: Box.KeyPair = dependencies.storage.getUserED25519KeyPair() else { return nil }
        
        /// Get a hash of any body content
        let bodyHash: Bytes? = {
            // Note: We need the `!body.isEmpty` check because of the default `Data()` value when trying to
            // init data from the httpBodyStream
            guard let body: Data = (request.httpBody ?? request.httpBodyStream.map { ((try? Data(from: $0)) ?? Data()) }), !body.isEmpty else {
                return nil
            }
            
            return dependencies.genericHash.hash(message: body.bytes, outputLength: 64)
        }()
        
        /// Generate the signature message
        /// "ServerPubkey || Nonce || Timestamp || Method || Path || Blake2b Hash(Body)
        ///     `ServerPubkey`
        ///     `Nonce`
        ///     `Timestamp` is the bytes of an ascii decimal string
        ///     `Method`
        ///     `Path`
        ///     `Body` is a Blake2b hash of the data (if there is a body)
        let signatureMessageBytes: Bytes = serverPublicKeyData.bytes
            .appending(nonce.bytes)
            .appending(timestampBytes)
            .appending(method.bytes)
            .appending(path.bytes)
            .appending(bodyHash ?? [])
        
        // Determine if we want to sign using standard or blinded keys based on the server capabilities (assume
        // unblinded if we have none)
        // TODO: Remove this (blinding will be required)
        if server?.capabilities.capabilities.contains(.blinding) == true {
            // TODO: More testing of this blinded id signing (though it seems to be working!!!)
            guard let blindedKeyPair: Box.KeyPair = dependencies.sodium.blindedKeyPair(serverPublicKey: serverPublicKey, edKeyPair: userEdKeyPair, genericHash: dependencies.genericHash) else {
                return nil
            }
            
            userPublicKeyHex = IdPrefix.blinded.hexEncodedPublicKey(for: blindedKeyPair.publicKey)
            
            guard let signatureResult: Bytes = Sodium().sogsSignature(message: signatureMessageBytes, secretKey: userEdKeyPair.secretKey, blindedSecretKey: blindedKeyPair.secretKey, blindedPublicKey: blindedKeyPair.publicKey) else {
                return nil
            }
            
            signatureBytes = signatureResult
        }
        else {
            userPublicKeyHex = IdPrefix.unblinded.hexEncodedPublicKey(for: userEdKeyPair.publicKey)
            
            // TODO: shift this to dependencies
            guard let signatureResult: Bytes = Sodium().sign.signature(message: signatureMessageBytes, secretKey: userEdKeyPair.secretKey) else {
                return nil
            }
            
            signatureBytes = signatureResult
        }
        
        print("RAWR X-SOGS-Pubkey: \(userPublicKeyHex)")
        print("RAWR X-SOGS-Timestamp: \(timestamp)")
        print("RAWR X-SOGS-Nonce: \(nonce.base64EncodedString())")
        print("RAWR X-SOGS-Signature: \(signatureBytes.toBase64())")
        updatedRequest.allHTTPHeaderFields = (request.allHTTPHeaderFields ?? [:])
            .updated(with: [
                Header.sogsPubKey.rawValue: userPublicKeyHex,
                Header.sogsTimestamp.rawValue: "\(timestamp)",
                Header.sogsNonce.rawValue: nonce.base64EncodedString(),
                Header.sogsSignature.rawValue: signatureBytes.toBase64()
            ])
        
        return updatedRequest
    }
    
    // MARK: - Convenience
    
    private static func send(_ request: Request, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        guard let url: URL = request.url else { return Promise(error: Error.invalidURL) }
        
        var urlRequest: URLRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.allHTTPHeaderFields = request.headers
            .setting(.room, request.room)   // TODO: Is this needed anymore? Add at the request level?.
            .toHTTPHeaders()
        urlRequest.httpBody = request.body
        
        if request.useOnionRouting {
            guard let publicKey = SNMessagingKitConfiguration.shared.storage.getOpenGroupPublicKey(for: request.server) else {
                return Promise(error: Error.noPublicKey)
            }
            
            if request.isAuthRequired {
                // Attempt to sign the request with the new auth
                guard let signedRequest: URLRequest = sign(urlRequest, for: request.server, with: publicKey, using: dependencies) else {
                    return Promise(error: Error.signingFailed)
                }
                
                // TODO: 'removeAuthToken' as a migration??? (would previously do this when getting a `401`)
                return dependencies.api.sendOnionRequest(signedRequest, to: request.server, with: publicKey)
            }
            
            return dependencies.api.sendOnionRequest(urlRequest, to: request.server, with: publicKey)
        }
        
        preconditionFailure("It's currently not allowed to send non onion routed requests.")
    }
    
    // MARK: -
    // MARK: -
    // MARK: - Legacy Requests (To be removed)
    // TODO: Remove the legacy requests (should be unused once we release - just here for testing)
    
    public static var legacyDefaultRoomsPromise: Promise<[LegacyRoomInfo]>?
    
    // MARK: -- Legacy Auth
    
    @available(*, deprecated, message: "Use request signing instead")
    private static func legacyGetAuthToken(for room: String, on server: String) -> Promise<String> {
        let storage = SNMessagingKitConfiguration.shared.storage

        if let authToken: String = storage.getAuthToken(for: room, on: server) {
            return Promise.value(authToken)
        }
        
        if let authTokenPromise: Promise<String> = legacyAuthTokenPromises.wrappedValue["\(server).\(room)"] {
            return authTokenPromise
        }
        
        let promise: Promise<String> = legacyRequestNewAuthToken(for: room, on: server)
            .then(on: OpenGroupAPI.workQueue) { legacyClaimAuthToken($0, for: room, on: server) }
            .then(on: OpenGroupAPI.workQueue) { authToken -> Promise<String> in
                let (promise, seal) = Promise<String>.pending()
                storage.write(with: { transaction in
                    storage.setAuthToken(for: room, on: server, to: authToken, using: transaction)
                }, completion: {
                    seal.fulfill(authToken)
                })
                return promise
            }
        
        promise
            .done(on: OpenGroupAPI.workQueue) { _ in
                legacyAuthTokenPromises.wrappedValue["\(server).\(room)"] = nil
            }
            .catch(on: OpenGroupAPI.workQueue) { _ in
                legacyAuthTokenPromises.wrappedValue["\(server).\(room)"] = nil
            }
        
        legacyAuthTokenPromises.wrappedValue["\(server).\(room)"] = promise
        return promise
    }

    @available(*, deprecated, message: "Use request signing instead")
    public static func legacyRequestNewAuthToken(for room: String, on server: String) -> Promise<String> {
        SNLog("Requesting auth token for server: \(server).")
        guard let userKeyPair: ECKeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else {
            return Promise(error: Error.generic)
        }
        
        let request: Request = Request(
            server: server,
            room: room,
            endpoint: .legacyAuthTokenChallenge(legacyAuth: true),
            queryParameters: [
                .publicKey: getUserHexEncodedPublicKey()
            ],
            isAuthRequired: false
        )
        
        return legacySend(request).map(on: OpenGroupAPI.workQueue) { _, maybeData in
            guard let data: Data = maybeData else { throw Error.parsingFailed }
            let response = try data.decoded(as: LegacyAuthTokenResponse.self, customError: Error.parsingFailed)
            let symmetricKey = try AESGCM.generateSymmetricKey(x25519PublicKey: response.challenge.ephemeralPublicKey, x25519PrivateKey: userKeyPair.privateKey)
            
            guard let tokenAsData = try? AESGCM.decrypt(response.challenge.ciphertext, with: symmetricKey) else {
                throw Error.decryptionFailed
            }
            
            return tokenAsData.toHexString()
        }
    }

    @available(*, deprecated, message: "Use request signing instead")
    public static func legacyClaimAuthToken(_ authToken: String, for room: String, on server: String) -> Promise<String> {
        let requestBody: LegacyPublicKeyBody = LegacyPublicKeyBody(publicKey: getUserHexEncodedPublicKey())

        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }

        let request: Request = Request(
            method: .post,
            server: server,
            room: room,
            endpoint: .legacyAuthTokenClaim(legacyAuth: true),
            headers: [
                // Set explicitly here because is isn't in the database yet at this point
                .authorization: authToken
            ],
            body: body,
            isAuthRequired: false
        )

        return legacySend(request).map(on: OpenGroupAPI.workQueue) { _ in authToken }
    }

    /// Should be called when leaving a group.
    @available(*, deprecated, message: "Use request signing instead")
    public static func legacyDeleteAuthToken(for room: String, on server: String) -> Promise<Void> {
        let request: Request = Request(
            method: .delete,
            server: server,
            room: room,
            endpoint: .legacyAuthToken(legacyAuth: true)
        )
        
        return legacySend(request).map(on: OpenGroupAPI.workQueue) { _ in
            let storage = SNMessagingKitConfiguration.shared.storage
            
            storage.write { transaction in
                storage.removeAuthToken(for: room, on: server, using: transaction)
            }
        }
    }
    
    // MARK: -- Legacy Requests
    
    @available(*, deprecated, message: "Use poll or batch instead")
    public static func legacyCompactPoll(_ server: String) -> Promise<LegacyCompactPollResponse> {
        let storage: SessionMessagingKitStorageProtocol = SNMessagingKitConfiguration.shared.storage
        let rooms: [String] = storage.getAllOpenGroups().values
            .filter { $0.server == server }
            .map { $0.room }
        var getAuthTokenPromises: [String: Promise<String>] = [:]
        let useMessageLimit = (hasPerformedInitialPoll[server] != true && timeSinceLastOpen > OpenGroupAPI.Poller.maxInactivityPeriod)

        hasPerformedInitialPoll[server] = true
        
        if !legacyHasUpdatedLastOpenDate {
            UserDefaults.standard[.lastOpen] = Date()
            legacyHasUpdatedLastOpenDate = true
        }
        
        for room in rooms {
            getAuthTokenPromises[room] = legacyGetAuthToken(for: room, on: server)
        }
        
        let requestBody: LegacyCompactPollBody = LegacyCompactPollBody(
            requests: rooms
                .map { roomId -> LegacyCompactPollBody.Room in
                    LegacyCompactPollBody.Room(
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
            .then(on: OpenGroupAPI.workQueue) { _ -> Promise<LegacyCompactPollResponse> in
                let requestBodyWithAuthTokens: LegacyCompactPollBody = LegacyCompactPollBody(
                    requests: requestBody.requests.compactMap { oldRoom -> LegacyCompactPollBody.Room? in
                        guard let authToken: String = getAuthTokenPromises[oldRoom.id]?.value else { return nil }
                        
                        return LegacyCompactPollBody.Room(
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
                    method: .post,
                    server: server,
                    endpoint: .legacyCompactPoll(legacyAuth: true),
                    body: body,
                    isAuthRequired: false
                )
        
                return legacySend(request)
                    .then(on: OpenGroupAPI.workQueue) { _, maybeData -> Promise<LegacyCompactPollResponse> in
                        guard let data: Data = maybeData else { throw Error.parsingFailed }
                        let response: LegacyCompactPollResponse = try data.decoded(as: LegacyCompactPollResponse.self, customError: Error.parsingFailed)

                        return when(
                            fulfilled: response.results
                                .compactMap { (result: LegacyCompactPollResponse.Result) -> Promise<[LegacyDeletion]>? in
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
                                    
                                    return legacyProcess(messages: result.messages, for: result.room, on: server)
                                        .then(on: OpenGroupAPI.workQueue) { _ ->  Promise<[LegacyDeletion]> in
                                            legacyProcess(deletions: result.deletions, for: result.room, on: server)
                                        }
                                }
                        ).then(on: OpenGroupAPI.workQueue) { _ in Promise.value(response) }
                    }
            }
    }
    
    @available(*, deprecated, message: "Use getDefaultRoomsIfNeeded instead")
    public static func legacyGetDefaultRoomsIfNeeded() {
        Storage.shared.write(
            with: { transaction in
                Storage.shared.setOpenGroupPublicKey(for: defaultServer, to: defaultServerPublicKey, using: transaction)
            },
            completion: {
                let promise = attempt(maxRetryCount: 8, recoveringOn: DispatchQueue.main) {
                    OpenGroupAPI.legacyGetAllRooms(from: defaultServer)
                }
                _ = promise.done(on: OpenGroupAPI.workQueue) { items in
                    items.forEach { legacyGetGroupImage(for: $0.id, on: defaultServer).retainUntilComplete() }
                }
                promise.catch(on: OpenGroupAPI.workQueue) { _ in
                    OpenGroupAPI.legacyDefaultRoomsPromise = nil
                }
                legacyDefaultRoomsPromise = promise
            }
        )
    }
    
    @available(*, deprecated, message: "Use rooms(for:) instead")
    public static func legacyGetAllRooms(from server: String) -> Promise<[LegacyRoomInfo]> {
        let request: Request = Request(
            server: server,
            endpoint: .legacyRooms,
            isAuthRequired: false
        )
        
        return legacySend(request)
            .map(on: OpenGroupAPI.workQueue) { _, maybeData in
                guard let data: Data = maybeData else { throw Error.parsingFailed }
                let response: LegacyRoomsResponse = try data.decoded(as: LegacyRoomsResponse.self, customError: Error.parsingFailed)
                
                return response.rooms
            }
    }
    
    @available(*, deprecated, message: "Use room(for:on:) instead")
    public static func legacyGetRoomInfo(for room: String, on server: String) -> Promise<LegacyRoomInfo> {
        let request: Request = Request(
            server: server,
            room: room,
            endpoint: .legacyRoomInfo(room),
            isAuthRequired: false
        )
        
        return legacySend(request)
            .map(on: OpenGroupAPI.workQueue) { _, maybeData in
                guard let data: Data = maybeData else { throw Error.parsingFailed }
                let response: LegacyGetInfoResponse = try data.decoded(as: LegacyGetInfoResponse.self, customError: Error.parsingFailed)
                
                return response.room
            }
    }
    
    @available(*, deprecated, message: "Use roomImage(_:for:on:) instead")
    public static func legacyGetGroupImage(for room: String, on server: String) -> Promise<Data> {
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
        
        if let promise = legacyGroupImagePromises["\(server).\(room)"] {
            return promise
        }
        
        let request: Request = Request(
            server: server,
            room: room,
            endpoint: .legacyRoomImage(room),
            isAuthRequired: false
        )
        
        let promise: Promise<Data> = legacySend(request).map(on: OpenGroupAPI.workQueue) { _, maybeData in
            guard let data: Data = maybeData else { throw Error.parsingFailed }
            let response: LegacyFileDownloadResponse = try data.decoded(as: LegacyFileDownloadResponse.self, customError: Error.parsingFailed)
            
            if server == defaultServer {
                Storage.shared.write { transaction in
                    Storage.shared.setOpenGroupImage(to: response.data, for: room, on: server, using: transaction)
                }
                UserDefaults.standard[.lastOpenGroupImageUpdate] = now
            }
            
            return response.data
        }
        legacyGroupImagePromises["\(server).\(room)"] = promise
        
        return promise
    }
    
    @available(*, deprecated, message: "Use room(for:on:) instead")
    public static func legacyGetMemberCount(for room: String, on server: String) -> Promise<UInt64> {
        let request: Request = Request(
            server: server,
            room: room,
            endpoint: .legacyMemberCount(legacyAuth: true)
        )
        
        return legacySend(request)
            .map(on: OpenGroupAPI.workQueue) { _, maybeData in
                guard let data: Data = maybeData else { throw Error.parsingFailed }
                let response: LegacyMemberCountResponse = try data.decoded(as: LegacyMemberCountResponse.self, customError: Error.parsingFailed)
                
                let storage = SNMessagingKitConfiguration.shared.storage
                storage.write { transaction in
                    storage.setUserCount(to: response.memberCount, forOpenGroupWithID: "\(server).\(room)", using: transaction)
                }
                
                return response.memberCount
            }
    }
    
    // MARK: - Legacy File Storage
    
    @available(*, deprecated, message: "Use uploadFile(_:fileName:to:on:) instead")
    public static func legacyUpload(_ file: Data, to room: String, on server: String) -> Promise<UInt64> {
        let requestBody: FileUploadBody = FileUploadBody(file: file.base64EncodedString())
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        let request = Request(method: .post, server: server, room: room, endpoint: .legacyFiles, body: body)
        
        return legacySend(request).map(on: OpenGroupAPI.workQueue) { _, maybeData in
            guard let data: Data = maybeData else { throw Error.parsingFailed }
            let response: LegacyFileUploadResponse = try data.decoded(as: LegacyFileUploadResponse.self, customError: Error.parsingFailed)
            
            return response.fileId
        }
    }
    
    @available(*, deprecated, message: "Use downloadFile(_:from:on:) instead")
    public static func legacyDownload(_ file: UInt64, from room: String, on server: String) -> Promise<Data> {
        let request = Request(server: server, room: room, endpoint: .legacyFile(file))
        
        return legacySend(request).map(on: OpenGroupAPI.workQueue) { _, maybeData in
            guard let data: Data = maybeData else { throw Error.parsingFailed }
            let response: LegacyFileDownloadResponse = try data.decoded(as: LegacyFileDownloadResponse.self, customError: Error.parsingFailed)
            
            return response.data
        }
    }
    
    // MARK: - Legacy Message Sending & Receiving
    
    @available(*, deprecated, message: "Use send(_:to:on:whisperTo:whisperMods:with:) instead")
    public static func legacySend(_ message: LegacyOpenGroupMessageV2, to room: String, on server: String, with publicKey: String) -> Promise<LegacyOpenGroupMessageV2> {
        guard let signedMessage = message.sign(with: publicKey) else { return Promise(error: Error.signingFailed) }
        guard let body: Data = try? JSONEncoder().encode(signedMessage) else {
            return Promise(error: Error.parsingFailed)
        }
        let request = Request(method: .post, server: server, room: room, endpoint: .legacyMessages, body: body)
        
        return legacySend(request).map(on: OpenGroupAPI.workQueue) { _, maybeData in
            guard let data: Data = maybeData else { throw Error.parsingFailed }
            let message: LegacyOpenGroupMessageV2 = try data.decoded(as: LegacyOpenGroupMessageV2.self, customError: Error.parsingFailed)
            Storage.shared.write { transaction in
                Storage.shared.addReceivedMessageTimestamp(message.sentTimestamp, using: transaction)
            }
            return message
        }
    }
    
    @available(*, deprecated, message: "Use recentMessages(in:on:) or messagesSince(seqNo:in:on:) instead")
    public static func legacyGetMessages(for room: String, on server: String) -> Promise<[LegacyOpenGroupMessageV2]> {
        let storage = SNMessagingKitConfiguration.shared.storage
        let request: Request = Request(
            server: server,
            room: room,
            endpoint: .legacyMessages,
            queryParameters: [
                .fromServerId: storage.getLastMessageServerID(for: room, on: server).map { String($0) }
            ].compactMapValues { $0 }
        )
        
        return legacySend(request).then(on: OpenGroupAPI.workQueue) { _, maybeData -> Promise<[LegacyOpenGroupMessageV2]> in
            guard let data: Data = maybeData else { throw Error.parsingFailed }
            let messages: [LegacyOpenGroupMessageV2] = try data.decoded(as: [LegacyOpenGroupMessageV2].self, customError: Error.parsingFailed)
            
            return legacyProcess(messages: messages, for: room, on: server)
        }
    }
    
    // MARK: - Legacy Message Deletion
    
    // TODO: No delete method????.
    @available(*, deprecated, message: "Use v4 endpoint instead")
    public static func legacyDeleteMessage(with serverID: Int64, from room: String, on server: String) -> Promise<Void> {
        let request: Request = Request(
            method: .delete,
            server: server,
            room: room,
            endpoint: .legacyMessagesForServer(serverID)
        )
        
        return legacySend(request).map(on: OpenGroupAPI.workQueue) { _ in }
    }
    
    @available(*, deprecated, message: "Use v4 endpoint instead")
    public static func legacyGetDeletedMessages(for room: String, on server: String) -> Promise<[LegacyDeletion]> {
        let storage = SNMessagingKitConfiguration.shared.storage
        
        let request: Request = Request(
            server: server,
            room: room,
            endpoint: .legacyDeletedMessages,
            queryParameters: [
                .fromServerId: storage.getLastDeletionServerID(for: room, on: server).map { String($0) }
            ].compactMapValues { $0 }
        )
        
        return legacySend(request).then(on: OpenGroupAPI.workQueue) { _, maybeData -> Promise<[LegacyDeletion]> in
            guard let data: Data = maybeData else { throw Error.parsingFailed }
            let response: LegacyDeletedMessagesResponse = try data.decoded(as: LegacyDeletedMessagesResponse.self, customError: Error.parsingFailed)
            
            return legacyProcess(deletions: response.deletions, for: room, on: server)
        }
    }
    
    // MARK: - Legacy Moderation
    
    @available(*, deprecated, message: "Use v4 endpoint instead")
    public static func legacyGetModerators(for room: String, on server: String) -> Promise<[String]> {
        let request: Request = Request(
            server: server,
            room: room,
            endpoint: .legacyModerators
        )
        
        return legacySend(request)
            .map(on: OpenGroupAPI.workQueue) { _, maybeData in
                guard let data: Data = maybeData else { throw Error.parsingFailed }
                let response: LegacyModeratorsResponse = try data.decoded(as: LegacyModeratorsResponse.self, customError: Error.parsingFailed)
                
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
    
    @available(*, deprecated, message: "Use v4 endpoint instead")
    public static func legacyBan(_ publicKey: String, from room: String, on server: String) -> Promise<Void> {
        let requestBody: LegacyPublicKeyBody = LegacyPublicKeyBody(publicKey: getUserHexEncodedPublicKey())
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        let request: Request = Request(
            method: .post,
            server: server,
            room: room,
            endpoint: .legacyBlockList,
            body: body
        )
        
        return legacySend(request).map(on: OpenGroupAPI.workQueue) { _ in }
    }
    
    @available(*, deprecated, message: "Use v4 endpoint instead")
    public static func legacyBanAndDeleteAllMessages(_ publicKey: String, from room: String, on server: String) -> Promise<Void> {
        let requestBody: LegacyPublicKeyBody = LegacyPublicKeyBody(publicKey: getUserHexEncodedPublicKey())
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        let request: Request = Request(
            method: .post,
            server: server,
            room: room,
            endpoint: .legacyBanAndDeleteAll,
            body: body
        )
        
        return legacySend(request).map(on: OpenGroupAPI.workQueue) { _ in }
    }
    
    @available(*, deprecated, message: "Use v4 endpoint instead")
    public static func legacyUnban(_ publicKey: String, from room: String, on server: String) -> Promise<Void> {
        let request: Request = Request(
            method: .delete,
            server: server,
            room: room,
            endpoint: .legacyBlockListIndividual(publicKey)
        )
        
        return legacySend(request).map(on: OpenGroupAPI.workQueue) { _ in }
    }
    
    // MARK: - Processing
    // TODO: Move these methods to the OpenGroupManager? (seems odd for them to be in the API)
    
    @available(*, deprecated, message: "Use v4 endpoint instead")
    private static func legacyProcess(messages: [LegacyOpenGroupMessageV2]?, for room: String, on server: String) -> Promise<[LegacyOpenGroupMessageV2]> {
        guard let messages: [LegacyOpenGroupMessageV2] = messages, !messages.isEmpty else { return Promise.value([]) }
        
        let storage = SNMessagingKitConfiguration.shared.storage
        let serverID: Int64 = (messages.compactMap { $0.serverID }.max() ?? 0)
        let lastMessageServerID: Int64 = (storage.getLastMessageServerID(for: room, on: server) ?? 0)
        
        if serverID > lastMessageServerID {
            let (promise, seal) = Promise<[LegacyOpenGroupMessageV2]>.pending()
            
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
    
    @available(*, deprecated, message: "Use v4 endpoint instead")
    private static func legacyProcess(deletions: [LegacyDeletion]?, for room: String, on server: String) -> Promise<[LegacyDeletion]> {
        guard let deletions: [LegacyDeletion] = deletions else { return Promise.value([]) }
        
        let storage = SNMessagingKitConfiguration.shared.storage
        let serverID: Int64 = (deletions.compactMap { $0.id }.max() ?? 0)
        let lastDeletionServerID: Int64 = (storage.getLastDeletionServerID(for: room, on: server) ?? 0)
        
        if serverID > lastDeletionServerID {
            let (promise, seal) = Promise<[LegacyDeletion]>.pending()
            
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
    
    // MARK: - Legacy Convenience
    
    @available(*, deprecated, message: "Use v4 endpoint instead")
    private static func legacySend(_ request: Request, through api: OnionRequestAPIType.Type = OnionRequestAPI.self) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        guard let url: URL = request.url else { return Promise(error: Error.invalidURL) }
        
        var urlRequest: URLRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.allHTTPHeaderFields = request.headers
            .setting(.room, request.room)   // TODO: Is this needed anymore? Add at the request level?.
            .toHTTPHeaders()
        urlRequest.httpBody = request.body
        
        if request.useOnionRouting {
            guard let publicKey = SNMessagingKitConfiguration.shared.storage.getOpenGroupPublicKey(for: request.server) else {
                return Promise(error: Error.noPublicKey)
            }
            
            if request.isAuthRequired {
                // Because legacy auth happens on a per-room basis, we need to have a room to
                // make an authenticated request
                guard let room = request.room else {
                    return api.sendOnionRequest(urlRequest, to: request.server, using: .v3, with: publicKey)
                }
                
                return legacyGetAuthToken(for: room, on: request.server)
                    .then(on: OpenGroupAPI.workQueue) { authToken -> Promise<(OnionRequestResponseInfoType, Data?)> in
                        urlRequest.setValue(authToken, forHTTPHeaderField: Header.authorization.rawValue)
                        
                        let promise = api.sendOnionRequest(urlRequest, to: request.server, using: .v3, with: publicKey)
                        promise.catch(on: OpenGroupAPI.workQueue) { error in
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
            
            return api.sendOnionRequest(urlRequest, to: request.server, using: .v3, with: publicKey)
        }
        
        preconditionFailure("It's currently not allowed to send non onion routed requests.")
    }
}
