import PromiseKit
import SessionSnodeKit

@objc(SNOpenGroupAPIV2)
public final class OpenGroupAPIV2 : NSObject {
    private static var authTokenPromises: [String:Promise<String>] = [:]
    private static var hasPerformedInitialPoll: [String:Bool] = [:]
    private static var hasUpdatedLastOpenDate = false
    public static let workQueue = DispatchQueue(label: "OpenGroupAPIV2.workQueue", qos: .userInitiated) // It's important that this is a serial queue
    public static var moderators: [String:[String:Set<String>]] = [:] // Server URL to room ID to set of moderator IDs
    public static var defaultRoomsPromise: Promise<[Info]>?
    public static var groupImagePromises: [String:Promise<Data>] = [:]

    private static let timeSinceLastOpen: TimeInterval = {
        guard let lastOpen = UserDefaults.standard[.lastOpen] else { return .greatestFiniteMagnitude }
        let now = Date()
        return now.timeIntervalSince(lastOpen)
    }()

    // MARK: Settings
    public static let defaultServer = "http://116.203.70.33"
    public static let defaultServerPublicKey = "a03c383cf63c3c4efe67acc52112a6dd734b3a946b9545f488aaa93da7991238"
    
    // MARK: Error
    public enum Error : LocalizedError {
        case generic
        case parsingFailed
        case decryptionFailed
        case signingFailed
        case invalidURL
        case noPublicKey
        
        public var errorDescription: String? {
            switch self {
            case .generic: return "An error occurred."
            case .parsingFailed: return "Invalid response."
            case .decryptionFailed: return "Couldn't decrypt response."
            case .signingFailed: return "Couldn't sign message."
            case .invalidURL: return "Invalid URL."
            case .noPublicKey: return "Couldn't find server public key."
            }
        }
    }

    // MARK: Request
    private struct Request {
        let verb: HTTP.Verb
        let room: String?
        let server: String
        let endpoint: String
        let queryParameters: [String:String]
        let parameters: JSON
        let headers: [String:String]
        let isAuthRequired: Bool
        /// Always `true` under normal circumstances. You might want to disable
        /// this when running over Lokinet.
        let useOnionRouting: Bool

        init(verb: HTTP.Verb, room: String?, server: String, endpoint: String, queryParameters: [String:String] = [:],
            parameters: JSON = [:], headers: [String:String] = [:], isAuthRequired: Bool = true, useOnionRouting: Bool = true) {
            self.verb = verb
            self.room = room
            self.server = server
            self.endpoint = endpoint
            self.queryParameters = queryParameters
            self.parameters = parameters
            self.headers = headers
            self.isAuthRequired = isAuthRequired
            self.useOnionRouting = useOnionRouting
        }
    }
    
    // MARK: Info
    public struct Info {
        public let id: String
        public let name: String
        public let imageID: String?
        
        public init(id: String, name: String, imageID: String?) {
            self.id = id
            self.name = name
            self.imageID = imageID
        }
    }
    
    // MARK: Compact Poll Response Body
    public struct CompactPollResponseBody {
        let room: String
        let messages: [OpenGroupMessageV2]
        let deletions: [Deletion]
        let moderators: [String]
    }
    
    public struct Deletion {
        let id: Int64
        let deletedMessageID: Int64
        
        public static func from(_ json: JSON) -> Deletion? {
            guard let id = json["id"] as? Int64, let deletedMessageID = json["deleted_message_id"] as? Int64 else { return nil }
            return Deletion(id: id, deletedMessageID: deletedMessageID)
        }
    }

    // MARK: Convenience
    private static func send(_ request: Request) -> Promise<JSON> {
        let tsRequest: TSRequest
        switch request.verb {
        case .get:
            var rawURL = "\(request.server)/\(request.endpoint)"
            if !request.queryParameters.isEmpty {
                let queryString = request.queryParameters.map { key, value in "\(key)=\(value)" }.joined(separator: "&")
                rawURL += "?\(queryString)"
            }
            guard let url = URL(string: rawURL) else { return Promise(error: Error.invalidURL) }
            tsRequest = TSRequest(url: url)
        case .post, .put, .delete:
            let rawURL = "\(request.server)/\(request.endpoint)"
            guard let url = URL(string: rawURL) else { return Promise(error: Error.invalidURL) }
            tsRequest = TSRequest(url: url, method: request.verb.rawValue, parameters: request.parameters)
        }
        tsRequest.allHTTPHeaderFields = request.headers
        tsRequest.setValue(request.room, forHTTPHeaderField: "Room")
        if request.useOnionRouting {
            guard let publicKey = SNMessagingKitConfiguration.shared.storage.getOpenGroupPublicKey(for: request.server) else { return Promise(error: Error.noPublicKey) }
            if request.isAuthRequired, let room = request.room { // Because auth happens on a per-room basis, we need both to make an authenticated request
                return getAuthToken(for: room, on: request.server).then(on: OpenGroupAPIV2.workQueue) { authToken -> Promise<JSON> in
                    tsRequest.setValue(authToken, forHTTPHeaderField: "Authorization")
                    let promise = OnionRequestAPI.sendOnionRequest(tsRequest, to: request.server, using: publicKey)
                    promise.catch(on: OpenGroupAPIV2.workQueue) { error in
                        // A 401 means that we didn't provide a (valid) auth token for a route that required one. We use this as an
                        // indication that the token we're using has expired. Note that a 403 has a different meaning; it means that
                        // we provided a valid token but it doesn't have a high enough permission level for the route in question.
                        if case OnionRequestAPI.Error.httpRequestFailedAtDestination(let statusCode, _, _) = error, statusCode == 401 {
                            let storage = SNMessagingKitConfiguration.shared.storage
                            storage.writeSync { transaction in
                                storage.removeAuthToken(for: room, on: request.server, using: transaction)
                            }
                        }
                    }
                    return promise
                }
            } else {
                return OnionRequestAPI.sendOnionRequest(tsRequest, to: request.server, using: publicKey)
            }
        } else {
            preconditionFailure("It's currently not allowed to send non onion routed requests.")
        }
    }
    
    public static func compactPoll(_ server: String) -> Promise<[CompactPollResponseBody]> {
        let storage = SNMessagingKitConfiguration.shared.storage
        let rooms = storage.getAllV2OpenGroups().values.filter { $0.server == server }.map { $0.room }
        var body: [JSON] = []
        var authTokenPromises: [String:Promise<String>] = [:]
        let useMessageLimit = (hasPerformedInitialPoll[server] != true && timeSinceLastOpen > OpenGroupPollerV2.maxInactivityPeriod)
        hasPerformedInitialPoll[server] = true
        if !hasUpdatedLastOpenDate {
            UserDefaults.standard[.lastOpen] = Date()
            hasUpdatedLastOpenDate = true
        }
        for room in rooms {
            authTokenPromises[room] = getAuthToken(for: room, on: server)
            var json: JSON = [ "room_id" : room ]
            if let lastMessageServerID = storage.getLastMessageServerID(for: room, on: server) {
                json["from_message_server_id"] = useMessageLimit ? nil : lastMessageServerID
            }
            if let lastDeletionServerID = storage.getLastDeletionServerID(for: room, on: server) {
                json["from_deletion_server_id"] = useMessageLimit ? nil : lastDeletionServerID
            }
            body.append(json)
        }
        return when(fulfilled: [Promise<String>](authTokenPromises.values)).then(on: OpenGroupAPIV2.workQueue) { _ -> Promise<[CompactPollResponseBody]> in
            let bodyWithAuthTokens = body.compactMap { json -> JSON? in
                guard let roomID = json["room_id"] as? String, let authToken = authTokenPromises[roomID]?.value else { return nil }
                var json = json
                json["auth_token"] = authToken
                return json
            }
            let request = Request(verb: .post, room: nil, server: server, endpoint: "compact_poll", parameters: [ "requests" : bodyWithAuthTokens ], isAuthRequired: false)
            return send(request).then(on: OpenGroupAPIV2.workQueue) { json -> Promise<[CompactPollResponseBody]> in
                guard let results = json["results"] as? [JSON] else { throw Error.parsingFailed }
                let promises = results.compactMap { json -> Promise<CompactPollResponseBody>? in
                    guard let room = json["room_id"] as? String, let status = json["status_code"] as? UInt else { return nil }
                    // A 401 means that we didn't provide a (valid) auth token for a route that required one. We use this as an
                    // indication that the token we're using has expired. Note that a 403 has a different meaning; it means that
                    // we provided a valid token but it doesn't have a high enough permission level for the route in question.
                    guard status != 401 else {
                        storage.writeSync { transaction in
                            storage.removeAuthToken(for: room, on: server, using: transaction)
                        }
                        return nil
                    }
                    let rawDeletions = json["deletions"] as? [JSON] ?? []
                    let moderators = json["moderators"] as? [String] ?? []
                    return try? parseMessages(from: json, for: room, on: server).then(on: OpenGroupAPIV2.workQueue) { messages in
                        parseDeletions(from: rawDeletions, for: room, on: server).map(on: OpenGroupAPIV2.workQueue) { deletions in
                            return CompactPollResponseBody(room: room, messages: messages, deletions: deletions, moderators: moderators)
                        }
                    }
                }
                return when(fulfilled: promises)
            }
        }
    }
    
    // MARK: Authorization
    private static func getAuthToken(for room: String, on server: String) -> Promise<String> {
        let storage = SNMessagingKitConfiguration.shared.storage
        if let authToken = storage.getAuthToken(for: room, on: server) {
            return Promise.value(authToken)
        } else {
            if let authTokenPromise = authTokenPromises["\(server).\(room)"] {
                return authTokenPromise
            } else {
                let promise = requestNewAuthToken(for: room, on: server)
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
                promise.done(on: OpenGroupAPIV2.workQueue) { _ in
                    authTokenPromises["\(server).\(room)"] = nil
                }.catch(on: OpenGroupAPIV2.workQueue) { _ in
                    authTokenPromises["\(server).\(room)"] = nil
                }
                authTokenPromises["\(server).\(room)"] = promise
                return promise
            }
        }
    }

    public static func requestNewAuthToken(for room: String, on server: String) -> Promise<String> {
        SNLog("Requesting auth token for server: \(server).")
        guard let userKeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else { return Promise(error: Error.generic) }
        let queryParameters = [ "public_key" : getUserHexEncodedPublicKey() ]
        let request = Request(verb: .get, room: room, server: server, endpoint: "auth_token_challenge", queryParameters: queryParameters, isAuthRequired: false)
        return send(request).map(on: OpenGroupAPIV2.workQueue) { json in
            guard let challenge = json["challenge"] as? JSON, let base64EncodedCiphertext = challenge["ciphertext"] as? String,
                let base64EncodedEphemeralPublicKey = challenge["ephemeral_public_key"] as? String, let ciphertext = Data(base64Encoded: base64EncodedCiphertext),
                let ephemeralPublicKey = Data(base64Encoded: base64EncodedEphemeralPublicKey) else {
                throw Error.parsingFailed
            }
            let symmetricKey = try AESGCM.generateSymmetricKey(x25519PublicKey: ephemeralPublicKey, x25519PrivateKey: userKeyPair.privateKey)
            guard let tokenAsData = try? AESGCM.decrypt(ciphertext, with: symmetricKey) else { throw Error.decryptionFailed }
            return tokenAsData.toHexString()
        }
    }
    
    public static func claimAuthToken(_ authToken: String, for room: String, on server: String) -> Promise<String> {
        let parameters = [ "public_key" : getUserHexEncodedPublicKey() ]
        let headers = [ "Authorization" : authToken ] // Set explicitly here because is isn't in the database yet at this point
        let request = Request(verb: .post, room: room, server: server, endpoint: "claim_auth_token",
            parameters: parameters, headers: headers, isAuthRequired: false)
        return send(request).map(on: OpenGroupAPIV2.workQueue) { _ in authToken }
    }
    
    /// Should be called when leaving a group.
    public static func deleteAuthToken(for room: String, on server: String) -> Promise<Void> {
        let request = Request(verb: .delete, room: room, server: server, endpoint: "auth_token")
        return send(request).map(on: OpenGroupAPIV2.workQueue) { _ in
            let storage = SNMessagingKitConfiguration.shared.storage
            storage.write { transaction in
                storage.removeAuthToken(for: room, on: server, using: transaction)
            }
        }
    }
    
    // MARK: File Storage
    public static func upload(_ file: Data, to room: String, on server: String) -> Promise<UInt64> {
        let base64EncodedFile = file.base64EncodedString()
        let parameters = [ "file" : base64EncodedFile ]
        let request = Request(verb: .post, room: room, server: server, endpoint: "files", parameters: parameters)
        return send(request).map(on: OpenGroupAPIV2.workQueue) { json in
            guard let fileID = json["result"] as? UInt64 else { throw Error.parsingFailed }
            return fileID
        }
    }
    
    public static func download(_ file: UInt64, from room: String, on server: String) -> Promise<Data> {
        let request = Request(verb: .get, room: room, server: server, endpoint: "files/\(file)")
        return send(request).map(on: OpenGroupAPIV2.workQueue) { json in
            guard let base64EncodedFile = json["result"] as? String, let file = Data(base64Encoded: base64EncodedFile) else { throw Error.parsingFailed }
            return file
        }
    }
    
    // MARK: Message Sending & Receiving
    public static func send(_ message: OpenGroupMessageV2, to room: String, on server: String) -> Promise<OpenGroupMessageV2> {
        guard let signedMessage = message.sign() else { return Promise(error: Error.signingFailed) }
        guard let json = signedMessage.toJSON() else { return Promise(error: Error.parsingFailed) }
        let request = Request(verb: .post, room: room, server: server, endpoint: "messages", parameters: json)
        return send(request).map(on: OpenGroupAPIV2.workQueue) { json in
            guard let rawMessage = json["message"] as? JSON, let message = OpenGroupMessageV2.fromJSON(rawMessage) else { throw Error.parsingFailed }
            Storage.shared.write { transaction in
                Storage.shared.addReceivedMessageTimestamp(message.sentTimestamp, using: transaction)
            }
            return message
        }
    }
    
    public static func getMessages(for room: String, on server: String) -> Promise<[OpenGroupMessageV2]> {
        let storage = SNMessagingKitConfiguration.shared.storage
        var queryParameters: [String:String] = [:]
        if let lastMessageServerID = storage.getLastMessageServerID(for: room, on: server) {
            queryParameters["from_server_id"] = String(lastMessageServerID)
        }
        let request = Request(verb: .get, room: room, server: server, endpoint: "messages", queryParameters: queryParameters)
        return send(request).then(on: OpenGroupAPIV2.workQueue) { json -> Promise<[OpenGroupMessageV2]> in
            try parseMessages(from: json, for: room, on: server)
        }
    }
    
    private static func parseMessages(from json: JSON, for room: String, on server: String) throws -> Promise<[OpenGroupMessageV2]> {
        let storage = SNMessagingKitConfiguration.shared.storage
        guard let rawMessages = json["messages"] as? [JSON] else { throw Error.parsingFailed }
        let messages: [OpenGroupMessageV2] = rawMessages.compactMap { json in
            guard let message = OpenGroupMessageV2.fromJSON(json), message.serverID != nil, let sender = message.sender, let data = Data(base64Encoded: message.base64EncodedData),
                let base64EncodedSignature = message.base64EncodedSignature, let signature = Data(base64Encoded: base64EncodedSignature) else {
                SNLog("Couldn't parse open group message from JSON: \(json).")
                return nil
            }
            // Validate the message signature
            let publicKey = Data(hex: sender.removing05PrefixIfNeeded())
            let isValid = (try? Ed25519.verifySignature(signature, publicKey: publicKey, data: data)) ?? false
            guard isValid else {
                SNLog("Ignoring message with invalid signature.")
                return nil
            }
            return message
        }
        let serverID = messages.map { $0.serverID! }.max() ?? 0 // Safe because messages with a nil serverID are filtered out
        let lastMessageServerID = storage.getLastMessageServerID(for: room, on: server) ?? 0
        if serverID > lastMessageServerID {
            let (promise, seal) = Promise<[OpenGroupMessageV2]>.pending()
            storage.write(with: { transaction in
                storage.setLastMessageServerID(for: room, on: server, to: serverID, using: transaction)
            }, completion: {
                seal.fulfill(messages)
            })
            return promise
        } else {
            return Promise.value(messages)
        }
    }
    
    // MARK: Message Deletion
    public static func deleteMessage(with serverID: Int64, from room: String, on server: String) -> Promise<Void> {
        let request = Request(verb: .delete, room: room, server: server, endpoint: "messages/\(serverID)")
        return send(request).map(on: OpenGroupAPIV2.workQueue) { _ in }
    }
    
    public static func getDeletedMessages(for room: String, on server: String) -> Promise<[Deletion]> {
        let storage = SNMessagingKitConfiguration.shared.storage
        var queryParameters: [String:String] = [:]
        if let lastDeletionServerID = storage.getLastDeletionServerID(for: room, on: server) {
            queryParameters["from_server_id"] = String(lastDeletionServerID)
        }
        let request = Request(verb: .get, room: room, server: server, endpoint: "deleted_messages", queryParameters: queryParameters)
        return send(request).then(on: OpenGroupAPIV2.workQueue) { json -> Promise<[Deletion]> in
            guard let rawDeletions = json["ids"] as? [JSON] else { throw Error.parsingFailed }
            return parseDeletions(from: rawDeletions, for: room, on: server)
        }
    }
    
    private static func parseDeletions(from rawDeletions: [JSON], for room: String, on server: String) -> Promise<[Deletion]> {
        let storage = SNMessagingKitConfiguration.shared.storage
        let deletions = rawDeletions.compactMap { Deletion.from($0) }
        let serverID = deletions.map { $0.id }.max() ?? 0
        let lastDeletionServerID = storage.getLastDeletionServerID(for: room, on: server) ?? 0
        if serverID > lastDeletionServerID {
            let (promise, seal) = Promise<[Deletion]>.pending()
            storage.write(with: { transaction in
                storage.setLastDeletionServerID(for: room, on: server, to: serverID, using: transaction)
            }, completion: {
                seal.fulfill(deletions)
            })
            return promise
        } else {
            return Promise.value(deletions)
        }
    }
    
    // MARK: Moderation
    public static func getModerators(for room: String, on server: String) -> Promise<[String]> {
        let request = Request(verb: .get, room: room, server: server, endpoint: "moderators")
        return send(request).map(on: OpenGroupAPIV2.workQueue) { json in
            guard let moderators = json["moderators"] as? [String] else { throw Error.parsingFailed }
            if var x = self.moderators[server] {
                x[room] = Set(moderators)
                self.moderators[server] = x
            } else {
                self.moderators[server] = [room:Set(moderators)]
            }
            return moderators
        }
    }
    
    public static func ban(_ publicKey: String, from room: String, on server: String) -> Promise<Void> {
        let parameters = [ "public_key" : publicKey ]
        let request = Request(verb: .post, room: room, server: server, endpoint: "block_list", parameters: parameters)
        return send(request).map(on: OpenGroupAPIV2.workQueue) { _ in }
    }
    
    public static func banAndDeleteAllMessages(_ publicKey: String, from room: String, on server: String) -> Promise<Void> {
        let parameters = [ "public_key" : publicKey ]
        let request = Request(verb: .post, room: room, server: server, endpoint: "ban_and_delete_all", parameters: parameters)
        return send(request).map(on: OpenGroupAPIV2.workQueue) { _ in }
    }
    
    public static func unban(_ publicKey: String, from room: String, on server: String) -> Promise<Void> {
        let request = Request(verb: .delete, room: room, server: server, endpoint: "block_list/\(publicKey)")
        return send(request).map(on: OpenGroupAPIV2.workQueue) { _ in }
    }

    public static func isUserModerator(_ publicKey: String, for room: String, on server: String) -> Bool {
        return moderators[server]?[room]?.contains(publicKey) ?? false
    }
    
    // MARK: General
    public static func getDefaultRoomsIfNeeded() {
        Storage.shared.write(with: { transaction in
            Storage.shared.setOpenGroupPublicKey(for: defaultServer, to: defaultServerPublicKey, using: transaction)
        }, completion: {
            let promise = attempt(maxRetryCount: 8, recoveringOn: DispatchQueue.main) {
                OpenGroupAPIV2.getAllRooms(from: defaultServer)
            }
            let _ = promise.done(on: OpenGroupAPIV2.workQueue) { items in
                items.forEach { getGroupImage(for: $0.id, on: defaultServer).retainUntilComplete() }
            }
            promise.catch(on: OpenGroupAPIV2.workQueue) { _ in
                OpenGroupAPIV2.defaultRoomsPromise = nil
            }
            defaultRoomsPromise = promise
        })
    }
    
    public static func getInfo(for room: String, on server: String) -> Promise<Info> {
        let request = Request(verb: .get, room: room, server: server, endpoint: "rooms/\(room)", isAuthRequired: false)
        let promise: Promise<Info> = send(request).map(on: OpenGroupAPIV2.workQueue) { json in
            guard let rawRoom = json["room"] as? JSON, let id = rawRoom["id"] as? String, let name = rawRoom["name"] as? String else { throw Error.parsingFailed }
            let imageID = rawRoom["image_id"] as? String
            return Info(id: id, name: name, imageID: imageID)
        }
        return promise
    }
    
    public static func getAllRooms(from server: String) -> Promise<[Info]> {
        let request = Request(verb: .get, room: nil, server: server, endpoint: "rooms", isAuthRequired: false)
        return send(request).map(on: OpenGroupAPIV2.workQueue) { json in
            guard let rawRooms = json["rooms"] as? [JSON] else { throw Error.parsingFailed }
            let rooms: [Info] = rawRooms.compactMap { json in
                guard let id = json["id"] as? String, let name = json["name"] as? String else {
                    SNLog("Couldn't parse room from JSON: \(json).")
                    return nil
                }
                let imageID = json["image_id"] as? String
                return Info(id: id, name: name, imageID: imageID)
            }
            return rooms
        }
    }
    
    public static func getMemberCount(for room: String, on server: String) -> Promise<UInt64> {
        let request = Request(verb: .get, room: room, server: server, endpoint: "member_count")
        return send(request).map(on: OpenGroupAPIV2.workQueue) { json in
            guard let memberCount = json["member_count"] as? UInt64 else { throw Error.parsingFailed }
            let storage = SNMessagingKitConfiguration.shared.storage
            storage.write { transaction in
                storage.setUserCount(to: memberCount, forV2OpenGroupWithID: "\(server).\(room)", using: transaction)
            }
            return memberCount
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
        let lastOpenGroupImageUpdate = UserDefaults.standard[.lastOpenGroupImageUpdate]
        let now = Date()
        let timeSinceLastUpdate = given(lastOpenGroupImageUpdate) { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        let updateInterval: TimeInterval = 7 * 24 * 60 * 60
        if let data = Storage.shared.getOpenGroupImage(for: room, on: server), server == defaultServer, timeSinceLastUpdate < updateInterval {
            return Promise.value(data)
        } else if let promise = groupImagePromises["\(server).\(room)"] {
            return promise
        } else {
            let request = Request(verb: .get, room: room, server: server, endpoint: "rooms/\(room)/image", isAuthRequired: false)
            let promise: Promise<Data> = send(request).map(on: OpenGroupAPIV2.workQueue) { json in
                guard let base64EncodedFile = json["result"] as? String, let file = Data(base64Encoded: base64EncodedFile) else { throw Error.parsingFailed }
                if server == defaultServer {
                    Storage.shared.write { transaction in
                        Storage.shared.setOpenGroupImage(to: file, for: room, on: server, using: transaction)
                    }
                    UserDefaults.standard[.lastOpenGroupImageUpdate] = now
                }
                return file
            }
            groupImagePromises["\(server).\(room)"] = promise
            return promise
        }
    }
}
