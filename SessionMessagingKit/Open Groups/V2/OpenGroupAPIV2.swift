import PromiseKit
import SessionSnodeKit

// TODO: Auth token & public key storage

public enum OpenGroupAPIV2 {
    
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
        let room: String
        let server: String
        let endpoint: String
        let queryParameters: [String:String]
        let parameters: JSON
        let isAuthRequired: Bool
        /// Always `true` under normal circumstances. You might want to disable
        /// this when running over Lokinet.
        let useOnionRouting: Bool

        init(verb: HTTP.Verb, room: String, server: String, endpoint: String, queryParameters: [String:String] = [:],
            parameters: JSON = [:], isAuthRequired: Bool = true, useOnionRouting: Bool = true) {
            self.verb = verb
            self.room = room
            self.server = server
            self.endpoint = endpoint
            self.queryParameters = queryParameters
            self.parameters = parameters
            self.isAuthRequired = isAuthRequired
            self.useOnionRouting = useOnionRouting
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
        tsRequest.setValue(request.room, forKey: "Room")
        if request.useOnionRouting {
            guard let publicKey = SNMessagingKitConfiguration.shared.storage.getOpenGroupPublicKey(for: request.server) else { return Promise(error: Error.noPublicKey) }
            return getAuthToken(for: request.server).then(on: DispatchQueue.global(qos: .default)) { authToken -> Promise<JSON> in
                tsRequest.setValue(authToken, forKey: "Authorization")
                return OnionRequestAPI.sendOnionRequest(tsRequest, to: request.server, using: publicKey)
            }
        } else {
            preconditionFailure("It's currently not allowed to send non onion routed requests.")
        }
    }
    
    // MARK: Authorization
    private static func getAuthToken(for server: String) -> Promise<String> {
        return Promise.value("") // TODO: Implement
    }

    public static func requestNewAuthToken(for room: String, on server: String) -> Promise<String> {
        SNLog("Requesting auth token for server: \(server).")
        guard let userKeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else { return Promise(error: Error.generic) }
        let queryParameters = [ "public_key" : getUserHexEncodedPublicKey() ]
        let request = Request(verb: .get, room: room, server: server, endpoint: "auth_token_challenge", queryParameters: queryParameters, isAuthRequired: false)
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let base64EncodedCiphertext = json["ciphertext"] as? String, let base64EncodedEphemeralPublicKey = json["ephemeral_public_key"] as? String,
                let ciphertext = Data(base64Encoded: base64EncodedCiphertext), let ephemeralPublicKey = Data(base64Encoded: base64EncodedEphemeralPublicKey) else {
                throw Error.parsingFailed
            }
            let symmetricKey = try AESGCM.generateSymmetricKey(x25519PublicKey: ephemeralPublicKey, x25519PrivateKey: userKeyPair.privateKey)
            guard let tokenAsData = try? AESGCM.decrypt(ciphertext, with: symmetricKey) else { throw Error.decryptionFailed }
            return tokenAsData.toHexString()
        }
    }
    
    public static func claimAuthToken(for room: String, on server: String) -> Promise<Void> {
        guard let userKeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else { return Promise(error: Error.generic) }
        let parameters = [ "public_key" : userKeyPair.publicKey.toHexString() ]
        let request = Request(verb: .post, room: room, server: server, endpoint: "claim_auth_token", parameters: parameters)
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { _ in }
    }
    
    /// Should be called when leaving a group.
    public static func deleteAuthToken(for room: String, on server: String) -> Promise<Void> {
        let request = Request(verb: .delete, room: room, server: server, endpoint: "auth_token")
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { _ in }
    }
    
    // MARK: File Storage
    public static func upload(_ file: Data, to room: String, on server: String) -> Promise<String> {
        let base64EncodedFile = file.base64EncodedString()
        let parameters = [ "file" : base64EncodedFile ]
        let request = Request(verb: .post, room: room, server: server, endpoint: "files", parameters: parameters)
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let fileID = json["result"] as? String else { throw Error.parsingFailed }
            return fileID
        }
    }
    
    public static func download(_ file: String, from room: String, on server: String) -> Promise<Data> {
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
            guard let message = OpenGroupMessageV2.fromJSON(json) else { throw Error.parsingFailed }
            return message
        }
    }
    
    public static func getMessages(for room: String, on server: String) -> Promise<[OpenGroupMessageV2]> {
        // TODO: From server ID & limit
        let queryParameters: [String:String] = [:]
        let request = Request(verb: .get, room: room, server: server, endpoint: "messages", queryParameters: queryParameters)
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let rawMessages = json["messages"] as? [[String:Any]] else { throw Error.parsingFailed }
            let messages: [OpenGroupMessageV2] = rawMessages.compactMap { json in
                // TODO: Signature validation
                guard let message = OpenGroupMessageV2.fromJSON(json) else {
                    SNLog("Couldn't parse open group message from JSON: \(json).")
                    return nil
                }
                return message
            }
            return messages
        }
    }
    
    // MARK: Message Deletion
    public static func deleteMessage(with serverID: Int64, from room: String, on server: String) -> Promise<Void> {
        let request = Request(verb: .delete, room: room, server: server, endpoint: "messages/\(serverID)")
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { _ in }
    }
    
    public static func getDeletedMessages(for room: String, on server: String) -> Promise<[Int64]> {
        // TODO: From server ID & limit
        let queryParameters: [String:String] = [:]
        let request = Request(verb: .get, room: room, server: server, endpoint: "deleted_messages", queryParameters: queryParameters)
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let ids = json["ids"] as? [Int64] else { throw Error.parsingFailed }
            return ids
        }
    }
    
    // MARK: Moderation
    public static func getModerators(for room: String, on server: String) -> Promise<[String]> {
        let request = Request(verb: .get, room: room, server: server, endpoint: "moderators")
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let moderators = json["moderators"] as? [String] else { throw Error.parsingFailed }
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
    
    // MARK: General
    public static func getMemberCount(for room: String, on server: String) -> Promise<UInt> {
        let request = Request(verb: .get, room: room, server: server, endpoint: "member_count")
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let memberCount = json["member_count"] as? UInt else { throw Error.parsingFailed }
            return memberCount
        }
    }
}
