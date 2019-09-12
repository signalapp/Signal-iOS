import PromiseKit

@objc(LKGroupChatAPI)
public final class LokiGroupChatAPI : NSObject {
    private static let storage = OWSPrimaryStorage.shared()
    
    private static var moderators: [String:[UInt64:Set<String>]] = [:] // Server URL to (channel ID to set of moderator IDs)
    
    // MARK: Settings
    private static let fallbackBatchCount = 40
    private static let maxRetryCount: UInt = 4
    
    // MARK: Public Chat
    @objc public static let publicChatServer = "https://chat-dev.lokinet.org"
    @objc public static let publicChatMessageType = "network.loki.messenger.publicChat"
    @objc public static let publicChatServerID: UInt64 = 1
    
    // MARK: Convenience
    private static var userDisplayName: String {
        return SSKEnvironment.shared.contactsManager.displayName(forPhoneIdentifier: userHexEncodedPublicKey) ?? "Anonymous"
    }
    
    private static var userKeyPair: ECKeyPair {
        return OWSIdentityManager.shared().identityKeyPair()!
    }
    
    private static var userHexEncodedPublicKey: String {
        return userKeyPair.hexEncodedPublicKey
    }
    
    // MARK: Error
    public enum Error : Swift.Error {
        case parsingFailed, decryptionFailed
    }
    
    // MARK: Database
    private static let authTokenCollection = "LokiGroupChatAuthTokenCollection"
    private static let lastMessageServerIDCollection = "LokiGroupChatLastMessageServerIDCollection"
    private static let lastDeletionServerIDCollection = "LokiGroupChatLastDeletionServerIDCollection"
    
    private static func getAuthTokenFromDatabase(for server: String) -> String? {
        var result: String? = nil
        storage.dbReadConnection.read { transaction in
            result = transaction.object(forKey: server, inCollection: authTokenCollection) as! String?
        }
        return result
    }
    
    private static func setAuthToken(for server: String, to newValue: String) {
        storage.dbReadWriteConnection.readWrite { transaction in
            transaction.setObject(newValue, forKey: server, inCollection: authTokenCollection)
        }
    }
    
    private static func getLastMessageServerID(for group: UInt64, on server: String) -> UInt? {
        var result: UInt? = nil
        storage.dbReadConnection.read { transaction in
            result = transaction.object(forKey: "\(server).\(group)", inCollection: lastMessageServerIDCollection) as! UInt?
        }
        return result
    }
    
    private static func setLastMessageServerID(for group: UInt64, on server: String, to newValue: UInt64) {
        storage.dbReadWriteConnection.readWrite { transaction in
            transaction.setObject(newValue, forKey: "\(server).\(group)", inCollection: lastMessageServerIDCollection)
        }
    }
    
    private static func getLastDeletionServerID(for group: UInt64, on server: String) -> UInt? {
        var result: UInt? = nil
        storage.dbReadConnection.read { transaction in
            result = transaction.object(forKey: "\(server).\(group)", inCollection: lastDeletionServerIDCollection) as! UInt?
        }
        return result
    }
    
    private static func setLastDeletionServerID(for group: UInt64, on server: String, to newValue: UInt64) {
        storage.dbReadWriteConnection.readWrite { transaction in
            transaction.setObject(newValue, forKey: "\(server).\(group)", inCollection: lastDeletionServerIDCollection)
        }
    }
    
    // MARK: Private API
    private static func requestNewAuthToken(for server: String) -> Promise<String> {
        print("[Loki] Requesting group chat auth token for server: \(server).")
        let queryParameters = "pubKey=\(userHexEncodedPublicKey)"
        let url = URL(string: "\(server)/loki/v1/get_challenge?\(queryParameters)")!
        let request = TSRequest(url: url)
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse in
            guard let json = rawResponse as? JSON, let base64EncodedChallenge = json["cipherText64"] as? String, let base64EncodedServerPublicKey = json["serverPubKey64"] as? String,
                let challenge = Data(base64Encoded: base64EncodedChallenge), var serverPublicKey = Data(base64Encoded: base64EncodedServerPublicKey) else {
                throw Error.parsingFailed
            }
            // Discard the "05" prefix if needed
            if (serverPublicKey.count == 33) {
                let hexEncodedServerPublicKey = serverPublicKey.hexadecimalString
                serverPublicKey = Data.data(fromHex: hexEncodedServerPublicKey.substring(from: 2))!
            }
            // The challenge is prefixed by the 16 bit IV
            guard let tokenAsData = try? DiffieHellman.decrypt(challenge, publicKey: serverPublicKey, privateKey: userKeyPair.privateKey),
                let token = String(bytes: tokenAsData, encoding: .utf8) else {
                throw Error.decryptionFailed
            }
            return token
        }
    }
    
    private static func submitAuthToken(_ token: String, for server: String) -> Promise<String> {
        print("[Loki] Submitting group chat auth token for server: \(server).")
        let url = URL(string: "\(server)/loki/v1/submit_challenge")!
        let parameters = [ "pubKey" : userHexEncodedPublicKey, "token" : token ]
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        return TSNetworkManager.shared().makePromise(request: request).map { _ in token }
    }
    
    private static func getAuthToken(for server: String) -> Promise<String> {
        if let token = getAuthTokenFromDatabase(for: server) {
            return Promise.value(token)
        } else {
            return requestNewAuthToken(for: server).then { submitAuthToken($0, for: server) }.map { token -> String in
                setAuthToken(for: server, to: token)
                return token
            }
        }
    }
    
    // MARK: Public API
    public static func getMessages(for group: UInt64, on server: String) -> Promise<[LokiGroupMessage]> {
        print("[Loki] Getting messages for group chat with ID: \(group) on server: \(server).")
        var queryParameters = "include_annotations=1"
        if let lastMessageServerID = getLastMessageServerID(for: group, on: server) {
            queryParameters += "&since_id=\(lastMessageServerID)"
        } else {
            queryParameters += "&count=-\(fallbackBatchCount)"
        }
        let url = URL(string: "\(server)/channels/\(group)/messages?\(queryParameters)")!
        let request = TSRequest(url: url)
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse in
            guard let json = rawResponse as? JSON, let rawMessages = json["data"] as? [JSON] else {
                print("[Loki] Couldn't parse messages for group chat with ID: \(group) on server: \(server) from: \(rawResponse).")
                throw Error.parsingFailed
            }
            return rawMessages.flatMap { message in
                let isDeleted = (message["is_deleted"] as? Int == 1)
                guard !isDeleted else { return nil }
                guard let annotations = message["annotations"] as? [JSON], let annotation = annotations.first, let value = annotation["value"] as? JSON,
                    let serverID = message["id"] as? UInt64, let body = message["text"] as? String, let hexEncodedPublicKey = value["source"] as? String, let displayName = value["from"] as? String,
                    let timestamp = value["timestamp"] as? UInt64 else {
                        print("[Loki] Couldn't parse message for group chat with ID: \(group) on server: \(server) from: \(message).")
                        return nil
                }
                let lastMessageServerID = getLastMessageServerID(for: group, on: server)
                if serverID > (lastMessageServerID ?? 0) { setLastMessageServerID(for: group, on: server, to: serverID) }
                let quote: LokiGroupMessage.Quote?
                if let quoteAsJSON = value["quote"] as? JSON, let quotedMessageTimestamp = quoteAsJSON["id"] as? UInt64, let quoteeHexEncodedPublicKey = quoteAsJSON["author"] as? String, let quotedMessageBody = quoteAsJSON["text"] as? String {
                    quote = LokiGroupMessage.Quote(quotedMessageTimestamp: quotedMessageTimestamp, quoteeHexEncodedPublicKey: quoteeHexEncodedPublicKey, quotedMessageBody: quotedMessageBody)
                } else {
                    quote = nil
                }
                return LokiGroupMessage(serverID: serverID, hexEncodedPublicKey: hexEncodedPublicKey, displayName: displayName, body: body, type: publicChatMessageType, timestamp: timestamp, quote: quote)
            }
        }
    }
    
    public static func sendMessage(_ message: LokiGroupMessage, to group: UInt64, on server: String) -> Promise<LokiGroupMessage> {
        return getAuthToken(for: server).then { token -> Promise<LokiGroupMessage> in
            print("[Loki] Sending message to group chat with ID: \(group) on server: \(server).")
            let url = URL(string: "\(server)/channels/\(group)/messages")!
            let parameters = message.toJSON()
            let request = TSRequest(url: url, method: "POST", parameters: parameters)
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            let displayName = userDisplayName
            return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse in
                // ISO8601DateFormatter doesn't support milliseconds before iOS 11
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                guard let json = rawResponse as? JSON, let messageAsJSON = json["data"] as? JSON, let serverID = messageAsJSON["id"] as? UInt64, let body = messageAsJSON["text"] as? String,
                    let dateAsString = messageAsJSON["created_at"] as? String, let date = dateFormatter.date(from: dateAsString) else {
                    print("[Loki] Couldn't parse message for group chat with ID: \(group) on server: \(server) from: \(rawResponse).")
                    throw Error.parsingFailed
                }
                let timestamp = UInt64(date.timeIntervalSince1970) * 1000
                return LokiGroupMessage(serverID: serverID, hexEncodedPublicKey: userHexEncodedPublicKey, displayName: displayName, body: body, type: publicChatMessageType, timestamp: timestamp, quote: message.quote)
            }
        }.recover { error -> Promise<LokiGroupMessage> in
            if let error = error as? NetworkManagerError, error.statusCode == 401 {
                print("[Loki] Group chat auth token for: \(server) expired; dropping it.")
                storage.dbReadWriteConnection.removeObject(forKey: server, inCollection: authTokenCollection)
            }
            throw error
        }.retryingIfNeeded(maxRetryCount: maxRetryCount).map { message in
            Analytics.shared.track("Group Message Sent")
            return message
        }.recover { error -> Promise<LokiGroupMessage> in
            Analytics.shared.track("Failed to Send Group Message")
            throw error
        }
    }
    
    public static func getDeletedMessageServerIDs(for group: UInt64, on server: String) -> Promise<[UInt64]> {
        print("[Loki] Getting deleted messages for group chat with ID: \(group) on server: \(server).")
        let queryParameters: String
        if let lastDeletionServerID = getLastDeletionServerID(for: group, on: server) {
            queryParameters = "since_id=\(lastDeletionServerID)"
        } else {
            queryParameters = "count=\(fallbackBatchCount)"
        }
        let url = URL(string: "\(server)/loki/v1/channel/\(group)/deletes?\(queryParameters)")!
        let request = TSRequest(url: url)
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse in
            guard let json = rawResponse as? JSON, let deletions = json["data"] as? [JSON] else {
                print("[Loki] Couldn't parse deleted messages for group chat with ID: \(group) on server: \(server) from: \(rawResponse).")
                throw Error.parsingFailed
            }
            return deletions.flatMap { deletion in
                guard let serverID = deletion["id"] as? UInt64, let messageServerID = deletion["message_id"] as? UInt64 else {
                    print("[Loki] Couldn't parse deleted message for group chat with ID: \(group) on server: \(server) from: \(deletion).")
                    return nil
                }
                let lastDeletionServerID = getLastDeletionServerID(for: group, on: server)
                if serverID > (lastDeletionServerID ?? 0) { setLastDeletionServerID(for: group, on: server, to: serverID) }
                return messageServerID
            }
        }
    }
    
    public static func deleteMessage(with messageID: UInt, for group: UInt64, on server: String, isSentByUser: Bool) -> Promise<Void> {
        return getAuthToken(for: server).then { token -> Promise<Void> in
            let isModerationRequest = !isSentByUser
            print("[Loki] Deleting message with ID: \(messageID) for group chat with ID: \(group) on server: \(server) (isModerationRequest = \(isModerationRequest)).")
            let urlAsString = isSentByUser ? "\(server)/channels/\(group)/messages/\(messageID)" : "\(server)/loki/v1/moderation/message/\(messageID)"
            let url = URL(string: urlAsString)!
            let request = TSRequest(url: url, method: "DELETE", parameters: [:])
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            return TSNetworkManager.shared().makePromise(request: request).done { result -> Void in
                print("[Loki] Deleted message with ID: \(messageID) on server: \(server).")
            }.retryingIfNeeded(maxRetryCount: maxRetryCount)
        }
    }
    
    public static func getModerators(for group: UInt64, on server: String) -> Promise<Set<String>> {
        let url = URL(string: "\(server)/loki/v1/channel/\(group)/get_moderators")!
        let request = TSRequest(url: url)
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse in
            guard let json = rawResponse as? JSON, let moderators = json["moderators"] as? [String] else {
                print("[Loki] Couldn't parse moderators for group chat with ID: \(group) on server: \(server) from: \(rawResponse).")
                throw Error.parsingFailed
            }
            let moderatorAsSet = Set(moderators);
            if self.moderators.keys.contains(server) {
                self.moderators[server]![group] = moderatorAsSet
            } else {
                self.moderators[server] = [ group : moderatorAsSet ]
            }
            return moderatorAsSet
        }
    }
    
    @objc (isUserModerator:forGroup:onServer:)
    public static func isUserModerator(_ hexEncodedPublicString: String, for group: UInt64, on server: String) -> Bool {
        return moderators[server]?[group]?.contains(hexEncodedPublicString) ?? false
    }
    
    // MARK: Public API (Obj-C)
    @objc(getMessagesForGroup:onServer:)
    public static func objc_getMessages(for group: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(getMessages(for: group, on: server))
    }
    
    @objc(sendMessage:toGroup:onServer:)
    public static func objc_sendMessage(_ message: LokiGroupMessage, to group: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(sendMessage(message, to: group, on: server))
    }
    
    @objc (deleteMessageWithID:forGroup:onServer:isSentByUser:)
    public static func objc_deleteMessage(with messageID: UInt, for group: UInt64, on server: String, isSentByUser: Bool) -> AnyPromise {
        return AnyPromise.from(deleteMessage(with: messageID, for: group, on: server, isSentByUser: isSentByUser))
    }
}
