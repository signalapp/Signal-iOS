import PromiseKit
import SessionSnodeKit

// TODO: Cache group images

@objc(SNOpenGroupAPIV2)
public final class OpenGroupAPIV2 : NSObject {
    private static var moderators: [String:[String:Set<String>]] = [:] // Server URL to room ID to set of moderator IDs
    private static var authTokenPromise: Promise<String>?
    
    public static let defaultServer = "https://sessionopengroup.com"
    public static let defaultServerPublicKey = "658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231b"
    public static var defaultRoomsPromise: Promise<[Info]>?
    public static var groupImagePromises: [String:Promise<Data>] = [:]
    
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
                return getAuthToken(for: room, on: request.server).then(on: DispatchQueue.global(qos: .default)) { authToken -> Promise<JSON> in
                    tsRequest.setValue(authToken, forHTTPHeaderField: "Authorization")
                    let promise = OnionRequestAPI.sendOnionRequest(tsRequest, to: request.server, using: publicKey)
                    promise.catch(on: DispatchQueue.global(qos: .default)) { error in
                        // A 401 means that we didn't provide a (valid) auth token for a route that required one. We use this as an
                        // indication that the token we're using has expired. Note that a 403 has a different meaning; it means that
                        // we provided a valid token but it doesn't have a high enough permission level for the route in question.
                        if case OnionRequestAPI.Error.httpRequestFailedAtDestination(let statusCode, _) = error, statusCode == 401 {
                            let storage = SNMessagingKitConfiguration.shared.storage
                            storage.write { transaction in
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
    
    // MARK: Authorization
    private static func getAuthToken(for room: String, on server: String) -> Promise<String> {
        let storage = SNMessagingKitConfiguration.shared.storage
        if let authToken = storage.getAuthToken(for: room, on: server) {
            return Promise.value(authToken)
        } else {
            if let authTokenPromise = authTokenPromise {
                return authTokenPromise
            } else {
                let promise = requestNewAuthToken(for: room, on: server)
                .then(on: DispatchQueue.global(qos: .userInitiated)) { claimAuthToken($0, for: room, on: server) }
                .then(on: DispatchQueue.global(qos: .userInitiated)) { authToken -> Promise<String> in
                    let (promise, seal) = Promise<String>.pending()
                    storage.write(with: { transaction in
                        storage.setAuthToken(for: room, on: server, to: authToken, using: transaction)
                    }, completion: {
                        seal.fulfill(authToken)
                    })
                    return promise
                }
                promise.done(on: DispatchQueue.global(qos: .userInitiated)) { _ in
                    authTokenPromise = nil
                }.catch(on: DispatchQueue.global(qos: .userInitiated)) { _ in
                    authTokenPromise = nil
                }
                authTokenPromise = promise
                return promise
            }
        }
    }

    public static func requestNewAuthToken(for room: String, on server: String) -> Promise<String> {
        SNLog("Requesting auth token for server: \(server).")
        guard let userKeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else { return Promise(error: Error.generic) }
        let queryParameters = [ "public_key" : getUserHexEncodedPublicKey() ]
        let request = Request(verb: .get, room: room, server: server, endpoint: "auth_token_challenge", queryParameters: queryParameters, isAuthRequired: false)
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
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
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { _ in authToken }
    }
    
    /// Should be called when leaving a group.
    public static func deleteAuthToken(for room: String, on server: String) -> Promise<Void> {
        let request = Request(verb: .delete, room: room, server: server, endpoint: "auth_token")
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { _ in
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
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let fileID = json["result"] as? UInt64 else { throw Error.parsingFailed }
            return fileID
        }
    }
    
    public static func download(_ file: UInt64, from room: String, on server: String) -> Promise<Data> {
        let request = Request(verb: .get, room: room, server: server, endpoint: "files/\(file)")
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let base64EncodedFile = json["result"] as? String, let file = Data(base64Encoded: base64EncodedFile) else { throw Error.parsingFailed }
            return file
        }
    }
    
    // MARK: Message Sending & Receiving
    public static func send(_ message: OpenGroupMessageV2, to room: String, on server: String) -> Promise<OpenGroupMessageV2> {
        guard let signedMessage = message.sign() else { return Promise(error: Error.signingFailed) }
        guard let json = signedMessage.toJSON() else { return Promise(error: Error.parsingFailed) }
        let request = Request(verb: .post, room: room, server: server, endpoint: "messages", parameters: json)
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let rawMessage = json["message"] as? JSON, let message = OpenGroupMessageV2.fromJSON(rawMessage) else { throw Error.parsingFailed }
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
        return send(request).then(on: DispatchQueue.global(qos: .userInitiated)) { json -> Promise<[OpenGroupMessageV2]> in
            guard let rawMessages = json["messages"] as? [[String:Any]] else { throw Error.parsingFailed }
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
    }
    
    // MARK: Message Deletion
    public static func deleteMessage(with serverID: Int64, from room: String, on server: String) -> Promise<Void> {
        let request = Request(verb: .delete, room: room, server: server, endpoint: "messages/\(serverID)")
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { _ in }
    }
    
    public static func getDeletedMessages(for room: String, on server: String) -> Promise<[Int64]> {
        let storage = SNMessagingKitConfiguration.shared.storage
        var queryParameters: [String:String] = [:]
        if let lastDeletionServerID = storage.getLastDeletionServerID(for: room, on: server) {
            queryParameters["from_server_id"] = String(lastDeletionServerID)
        }
        let request = Request(verb: .get, room: room, server: server, endpoint: "deleted_messages", queryParameters: queryParameters)
        return send(request).then(on: DispatchQueue.global(qos: .userInitiated)) { json -> Promise<[Int64]> in
            guard let serverIDs = json["ids"] as? [Int64] else { throw Error.parsingFailed }
            let serverID = serverIDs.max() ?? 0
            let lastDeletionServerID = storage.getLastDeletionServerID(for: room, on: server) ?? 0
            if serverID > lastDeletionServerID {
                let (promise, seal) = Promise<[Int64]>.pending()
                storage.write(with: { transaction in
                    storage.setLastDeletionServerID(for: room, on: server, to: serverID, using: transaction)
                }, completion: {
                    seal.fulfill(serverIDs)
                })
                return promise
            } else {
                return Promise.value(serverIDs)
            }
        }
    }
    
    // MARK: Moderation
    public static func getModerators(for room: String, on server: String) -> Promise<[String]> {
        let request = Request(verb: .get, room: room, server: server, endpoint: "moderators")
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
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
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { _ in }
    }
    
    public static func unban(_ publicKey: String, from room: String, on server: String) -> Promise<Void> {
        let request = Request(verb: .delete, room: room, server: server, endpoint: "block_list/\(publicKey)")
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { _ in }
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
            let _ = promise.done(on: DispatchQueue.global(qos: .userInitiated)) { items in
                items.forEach { getGroupImage(for: $0.id, on: defaultServer).retainUntilComplete() }
            }
            defaultRoomsPromise = promise
        })
    }
    
    public static func getInfo(for room: String, on server: String) -> Promise<Info> {
        let request = Request(verb: .get, room: room, server: server, endpoint: "rooms/\(room)", isAuthRequired: false)
        let promise: Promise<Info> = send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let rawRoom = json["room"] as? JSON, let id = rawRoom["id"] as? String, let name = rawRoom["name"] as? String else { throw Error.parsingFailed }
            let imageID = rawRoom["image_id"] as? String
            return Info(id: id, name: name, imageID: imageID)
        }
        return promise
    }
    
    public static func getAllRooms(from server: String) -> Promise<[Info]> {
        let request = Request(verb: .get, room: nil, server: server, endpoint: "rooms", isAuthRequired: false)
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
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
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let memberCount = json["member_count"] as? UInt64 else { throw Error.parsingFailed }
            let storage = SNMessagingKitConfiguration.shared.storage
            storage.write { transaction in
                storage.setUserCount(to: memberCount, forV2OpenGroupWithID: "\(server).\(room)", using: transaction)
            }
            return memberCount
        }
    }
    
    public static func getGroupImage(for room: String, on server: String) -> Promise<Data> {
        if let promise = groupImagePromises["\(server).\(room)"] {
            return promise
        } else {
            let request = Request(verb: .get, room: room, server: server, endpoint: "group_image")
            let promise: Promise<Data> = send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
                guard let base64EncodedFile = json["result"] as? String, let file = Data(base64Encoded: base64EncodedFile) else { throw Error.parsingFailed }
                return file
            }
            groupImagePromises["\(server).\(room)"] = promise
            return promise
        }
    }
}
