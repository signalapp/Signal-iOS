import PromiseKit

@objc(LKPublicChatAPI)
public final class LokiPublicChatAPI : LokiDotNetAPI {
    private static var moderators: [String:[UInt64:Set<String>]] = [:] // Server URL to (channel ID to set of moderator IDs)
    public static var displayNameUpdatees: [String:Set<String>] = [:]
    
    // MARK: Settings
    private static let fallbackBatchCount = 64
    private static let maxRetryCount: UInt = 8
    
    // MARK: Public Chat
    private static let channelInfoType = "net.patter-app.settings"
    private static let attachmentType = "net.app.core.oembed"
    public static let profilePictureType = "network.loki.messenger.avatar"
    @objc public static let publicChatMessageType = "network.loki.messenger.publicChat"
    
    @objc public static let defaultChats: [LokiPublicChat] = [] // Currently unused
    
    // MARK: Convenience
    private static var userDisplayName: String {
        return SSKEnvironment.shared.contactsManager.displayName(forPhoneIdentifier: userHexEncodedPublicKey) ?? "Anonymous"
    }
    
    // MARK: Database
    override internal class var authTokenCollection: String { "LokiGroupChatAuthTokenCollection" }
    @objc public static let lastMessageServerIDCollection = "LokiGroupChatLastMessageServerIDCollection"
    @objc public static let lastDeletionServerIDCollection = "LokiGroupChatLastDeletionServerIDCollection"
    
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
    
    private static func removeLastMessageServerID(for group: UInt64, on server: String) {
        storage.dbReadWriteConnection.readWrite { transaction in
            transaction.removeObject(forKey: "\(server).\(group)", inCollection: lastMessageServerIDCollection)
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
    
    private static func removeLastDeletionServerID(for group: UInt64, on server: String) {
        storage.dbReadWriteConnection.readWrite { transaction in
            transaction.removeObject(forKey: "\(server).\(group)", inCollection: lastDeletionServerIDCollection)
        }
    }
    
    public static func clearCaches(for channel: UInt64, on server: String) {
        removeLastMessageServerID(for: channel, on: server)
        removeLastDeletionServerID(for: channel, on: server)
    }
    
    // MARK: Public API
    public static func getMessages(for channel: UInt64, on server: String) -> Promise<[LokiPublicChatMessage]> {
        var queryParameters = "include_annotations=1"
        if let lastMessageServerID = getLastMessageServerID(for: channel, on: server) {
            queryParameters += "&since_id=\(lastMessageServerID)"
        } else {
            queryParameters += "&count=\(fallbackBatchCount)&include_deleted=0"
        }
        let url = URL(string: "\(server)/channels/\(channel)/messages?\(queryParameters)")!
        let request = TSRequest(url: url)
        return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global()).map { rawResponse in
            guard let json = rawResponse as? JSON, let rawMessages = json["data"] as? [JSON] else {
                print("[Loki] Couldn't parse messages for public chat channel with ID: \(channel) on server: \(server) from: \(rawResponse).")
                throw LokiDotNetAPIError.parsingFailed
            }
            return rawMessages.flatMap { message in
                let isDeleted = (message["is_deleted"] as? Int == 1)
                guard !isDeleted else { return nil }
                guard let annotations = message["annotations"] as? [JSON], let annotation = annotations.first(where: { $0["type"] as? String == publicChatMessageType }), let value = annotation["value"] as? JSON,
                    let serverID = message["id"] as? UInt64, let hexEncodedSignatureData = value["sig"] as? String, let signatureVersion = value["sigver"] as? UInt64,
                    let body = message["text"] as? String, let user = message["user"] as? JSON, let hexEncodedPublicKey = user["username"] as? String,
                    let timestamp = value["timestamp"] as? UInt64 else {
                        print("[Loki] Couldn't parse message for public chat channel with ID: \(channel) on server: \(server) from: \(message).")
                        return nil
                }
                var profilePicture: LokiPublicChatMessage.ProfilePicture? = nil
                let displayName = user["name"] as? String ?? NSLocalizedString("Anonymous", comment: "")
                if let userAnnotations = user["annotations"] as? [JSON], let profilePictureAnnotation = userAnnotations.first(where: { $0["type"] as? String == profilePictureType }),
                    let profilePictureValue = profilePictureAnnotation["value"] as? JSON, let profileKeyString = profilePictureValue["profileKey"] as? String, let profileKey = Data(base64Encoded: profileKeyString), let url = profilePictureValue["url"] as? String {
                    profilePicture = LokiPublicChatMessage.ProfilePicture(profileKey: profileKey, url: url)
                }
                let lastMessageServerID = getLastMessageServerID(for: channel, on: server)
                if serverID > (lastMessageServerID ?? 0) { setLastMessageServerID(for: channel, on: server, to: serverID) }
                let quote: LokiPublicChatMessage.Quote?
                if let quoteAsJSON = value["quote"] as? JSON, let quotedMessageTimestamp = quoteAsJSON["id"] as? UInt64, let quoteeHexEncodedPublicKey = quoteAsJSON["author"] as? String,
                    let quotedMessageBody = quoteAsJSON["text"] as? String {
                    let quotedMessageServerID = message["reply_to"] as? UInt64
                    quote = LokiPublicChatMessage.Quote(quotedMessageTimestamp: quotedMessageTimestamp, quoteeHexEncodedPublicKey: quoteeHexEncodedPublicKey, quotedMessageBody: quotedMessageBody,
                        quotedMessageServerID: quotedMessageServerID)
                } else {
                    quote = nil
                }
                let signature = LokiPublicChatMessage.Signature(data: Data(hex: hexEncodedSignatureData), version: signatureVersion)
                let attachmentsAsJSON = annotations.filter { $0["type"] as? String == attachmentType }
                let attachments: [LokiPublicChatMessage.Attachment] = attachmentsAsJSON.compactMap { attachmentAsJSON in
                    guard let value = attachmentAsJSON["value"] as? JSON, let kindAsString = value["lokiType"] as? String, let kind = LokiPublicChatMessage.Attachment.Kind(rawValue: kindAsString),
                        let serverID = value["id"] as? UInt64, let contentType = value["contentType"] as? String, let size = value["size"] as? UInt, let url = value["url"] as? String else { return nil }
                    let fileName = value["fileName"] as? String ?? UUID().description
                    let width = value["width"] as? UInt ?? 0
                    let height = value["height"] as? UInt ?? 0
                    let flags = (value["flags"] as? UInt) ?? 0
                    let caption = value["caption"] as? String
                    let linkPreviewURL = value["linkPreviewUrl"] as? String
                    let linkPreviewTitle = value["linkPreviewTitle"] as? String
                    if kind == .linkPreview {
                        guard linkPreviewURL != nil && linkPreviewTitle != nil else {
                            print("[Loki] Ignoring public chat message with invalid link preview.")
                            return nil
                        }
                    }
                    return LokiPublicChatMessage.Attachment(kind: kind, server: server, serverID: serverID, contentType: contentType, size: size, fileName: fileName, flags: flags,
                        width: width, height: height, caption: caption, url: url, linkPreviewURL: linkPreviewURL, linkPreviewTitle: linkPreviewTitle)
                }
                let result = LokiPublicChatMessage(serverID: serverID, hexEncodedPublicKey: hexEncodedPublicKey, displayName: displayName, profilePicture: profilePicture,
                    body: body, type: publicChatMessageType, timestamp: timestamp, quote: quote, attachments: attachments, signature: signature)
                guard result.hasValidSignature() else {
                    print("[Loki] Ignoring public chat message with invalid signature.")
                    return nil
                }
                var existingMessageID: String? = nil
                storage.dbReadConnection.read { transaction in
                    existingMessageID = storage.getIDForMessage(withServerID: UInt(result.serverID!), in: transaction)
                }
                guard existingMessageID == nil else {
                    print("[Loki] Ignoring duplicate public chat message.")
                    return nil
                }
                return result
            }.sorted { $0.timestamp < $1.timestamp }
        }
    }
    
    public static func sendMessage(_ message: LokiPublicChatMessage, to channel: UInt64, on server: String) -> Promise<LokiPublicChatMessage> {
        guard let signedMessage = message.sign(with: userKeyPair.privateKey) else { return Promise(error: LokiDotNetAPIError.signingFailed) }
        return getAuthToken(for: server).then(on: DispatchQueue.global()) { token -> Promise<LokiPublicChatMessage> in
            print("[Loki] Sending message to public chat channel with ID: \(channel) on server: \(server).")
            let url = URL(string: "\(server)/channels/\(channel)/messages")!
            let parameters = signedMessage.toJSON()
            let request = TSRequest(url: url, method: "POST", parameters: parameters)
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            let displayName = userDisplayName
            return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global()).map { rawResponse in
                // ISO8601DateFormatter doesn't support milliseconds before iOS 11
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                guard let json = rawResponse as? JSON, let messageAsJSON = json["data"] as? JSON, let serverID = messageAsJSON["id"] as? UInt64, let body = messageAsJSON["text"] as? String,
                    let dateAsString = messageAsJSON["created_at"] as? String, let date = dateFormatter.date(from: dateAsString) else {
                    print("[Loki] Couldn't parse message for public chat channel with ID: \(channel) on server: \(server) from: \(rawResponse).")
                    throw LokiDotNetAPIError.parsingFailed
                }
                let timestamp = UInt64(date.timeIntervalSince1970) * 1000
                return LokiPublicChatMessage(serverID: serverID, hexEncodedPublicKey: userHexEncodedPublicKey, displayName: displayName, profilePicture: signedMessage.profilePicture, body: body, type: publicChatMessageType, timestamp: timestamp, quote: signedMessage.quote, attachments: signedMessage.attachments, signature: signedMessage.signature)
            }
        }.recover(on: DispatchQueue.global()) { error -> Promise<LokiPublicChatMessage> in
            if let error = error as? NetworkManagerError, error.statusCode == 401 {
                print("[Loki] Group chat auth token for: \(server) expired; dropping it.")
                storage.dbReadWriteConnection.removeObject(forKey: server, inCollection: authTokenCollection)
            }
            throw error
        }.retryingIfNeeded(maxRetryCount: maxRetryCount)
    }
    
    public static func getDeletedMessageServerIDs(for channel: UInt64, on server: String) -> Promise<[UInt64]> {
        print("[Loki] Getting deleted messages for public chat channel with ID: \(channel) on server: \(server).")
        let queryParameters: String
        if let lastDeletionServerID = getLastDeletionServerID(for: channel, on: server) {
            queryParameters = "since_id=\(lastDeletionServerID)"
        } else {
            queryParameters = "count=\(fallbackBatchCount)"
        }
        let url = URL(string: "\(server)/loki/v1/channel/\(channel)/deletes?\(queryParameters)")!
        let request = TSRequest(url: url)
        return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global()).map { rawResponse in
            guard let json = rawResponse as? JSON, let deletions = json["data"] as? [JSON] else {
                print("[Loki] Couldn't parse deleted messages for public chat channel with ID: \(channel) on server: \(server) from: \(rawResponse).")
                throw LokiDotNetAPIError.parsingFailed
            }
            return deletions.flatMap { deletion in
                guard let serverID = deletion["id"] as? UInt64, let messageServerID = deletion["message_id"] as? UInt64 else {
                    print("[Loki] Couldn't parse deleted message for public chat channel with ID: \(channel) on server: \(server) from: \(deletion).")
                    return nil
                }
                let lastDeletionServerID = getLastDeletionServerID(for: channel, on: server)
                if serverID > (lastDeletionServerID ?? 0) { setLastDeletionServerID(for: channel, on: server, to: serverID) }
                return messageServerID
            }
        }
    }
    
    public static func deleteMessage(with messageID: UInt, for channel: UInt64, on server: String, isSentByUser: Bool) -> Promise<Void> {
        return getAuthToken(for: server).then(on: DispatchQueue.global()) { token -> Promise<Void> in
            let isModerationRequest = !isSentByUser
            print("[Loki] Deleting message with ID: \(messageID) for public chat channel with ID: \(channel) on server: \(server) (isModerationRequest = \(isModerationRequest)).")
            let urlAsString = isSentByUser ? "\(server)/channels/\(channel)/messages/\(messageID)" : "\(server)/loki/v1/moderation/message/\(messageID)"
            let url = URL(string: urlAsString)!
            let request = TSRequest(url: url, method: "DELETE", parameters: [:])
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global()).done(on: DispatchQueue.global()) { result -> Void in
                print("[Loki] Deleted message with ID: \(messageID) on server: \(server).")
            }.retryingIfNeeded(maxRetryCount: maxRetryCount)
        }
    }
    
    public static func getModerators(for channel: UInt64, on server: String) -> Promise<Set<String>> {
        let url = URL(string: "\(server)/loki/v1/channel/\(channel)/get_moderators")!
        let request = TSRequest(url: url)
        return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global()).map { rawResponse in
            guard let json = rawResponse as? JSON, let moderators = json["moderators"] as? [String] else {
                print("[Loki] Couldn't parse moderators for public chat channel with ID: \(channel) on server: \(server) from: \(rawResponse).")
                throw LokiDotNetAPIError.parsingFailed
            }
            let moderatorAsSet = Set(moderators);
            if self.moderators.keys.contains(server) {
                self.moderators[server]![channel] = moderatorAsSet
            } else {
                self.moderators[server] = [ channel : moderatorAsSet ]
            }
            return moderatorAsSet
        }
    }
    
    public static func join(_ channel: UInt64, on server: String) -> Promise<Void> {
        return getAuthToken(for: server).then(on: DispatchQueue.global()) { token -> Promise<Void> in
            let url = URL(string: "\(server)/channels/\(channel)/subscribe")!
            let request = TSRequest(url: url, method: "POST", parameters: [:])
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global()).done(on: DispatchQueue.global()) { result -> Void in
                print("[Loki] Joined channel with ID: \(channel) on server: \(server).")
            }.retryingIfNeeded(maxRetryCount: maxRetryCount)
        }
    }
    
    public static func leave(_ channel: UInt64, on server: String) -> Promise<Void> {
        return getAuthToken(for: server).then(on: DispatchQueue.global()) { token -> Promise<Void> in
            let url = URL(string: "\(server)/channels/\(channel)/subscribe")!
            let request = TSRequest(url: url, method: "DELETE", parameters: [:])
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global()).done(on: DispatchQueue.global()) { result -> Void in
                print("[Loki] Left channel with ID: \(channel) on server: \(server).")
            }.retryingIfNeeded(maxRetryCount: maxRetryCount)
        }
    }
    
    public static func getUserCount(for channel: UInt64, on server: String) -> Promise<Int> {
        return getAuthToken(for: server).then(on: DispatchQueue.global()) { token -> Promise<Int> in
            let queryParameters = "count=200"
            let url = URL(string: "\(server)/channels/\(channel)/subscribers?\(queryParameters)")!
            let request = TSRequest(url: url)
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global()).map { rawResponse in
                guard let json = rawResponse as? JSON, let users = json["data"] as? [JSON] else {
                    print("[Loki] Couldn't parse user count for public chat channel with ID: \(channel) on server: \(server) from: \(rawResponse).")
                    throw LokiDotNetAPIError.parsingFailed
                }
                let userCount = users.count
                let storage = OWSPrimaryStorage.shared()
                storage.dbReadWriteConnection.readWrite { transaction in
                    storage.setUserCount(userCount, forPublicChatWithID: "\(server).\(channel)", in: transaction)
                }
                return userCount
            }
        }
    }
    
    public static func getDisplayNames(for channel: UInt64, on server: String) -> Promise<Void> {
        let publicChatID = "\(server).\(channel)"
        guard let hexEncodedPublicKeys = displayNameUpdatees[publicChatID] else { return Promise.value(()) }
        displayNameUpdatees[publicChatID] = []
        print("[Loki] Getting display names for: \(hexEncodedPublicKeys).")
        return getAuthToken(for: server).then(on: DispatchQueue.global()) { token -> Promise<Void> in
            let queryParameters = "ids=\(hexEncodedPublicKeys.map { "@\($0)" }.joined(separator: ","))&include_user_annotations=1"
            let url = URL(string: "\(server)/users?\(queryParameters)")!
            let request = TSRequest(url: url)
            return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global()).map { rawResponse in
                guard let json = rawResponse as? JSON, let data = json["data"] as? [JSON] else {
                    print("[Loki] Couldn't parse display names for users: \(hexEncodedPublicKeys) from: \(rawResponse).")
                    throw LokiDotNetAPIError.parsingFailed
                }
                storage.dbReadWriteConnection.readWrite { transaction in
                    data.forEach { data in
                        guard let user = data["user"] as? JSON, let hexEncodedPublicKey = user["username"] as? String, let rawDisplayName = user["name"] as? String else { return }
                        let endIndex = hexEncodedPublicKey.endIndex
                        let cutoffIndex = hexEncodedPublicKey.index(endIndex, offsetBy: -8)
                        let displayName = "\(rawDisplayName) (...\(hexEncodedPublicKey[cutoffIndex..<endIndex]))"
                        transaction.setObject(displayName, forKey: hexEncodedPublicKey, inCollection: "\(server).\(channel)")
                    }
                }
            }
        }
    }
    
    @objc(isUserModerator:forChannel:onServer:)
    public static func isUserModerator(_ hexEncodedPublicString: String, for channel: UInt64, on server: String) -> Bool {
        return moderators[server]?[channel]?.contains(hexEncodedPublicString) ?? false
    }
    
    public static func setDisplayName(to newDisplayName: String?, on server: String) -> Promise<Void> {
        print("[Loki] Updating display name on server: \(server).")
        return getAuthToken(for: server).then(on: DispatchQueue.global()) { token -> Promise<Void> in
            let parameters: JSON = [ "name" : (newDisplayName ?? "") ]
            let url = URL(string: "\(server)/users/me")!
            let request = TSRequest(url: url, method: "PATCH", parameters: parameters)
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global()).map { _ in }.recover(on: DispatchQueue.global()) { error in
                print("Couldn't update display name due to error: \(error).")
                throw error
            }
        }.retryingIfNeeded(maxRetryCount: maxRetryCount)
    }
    
    public static func setProfilePictureURL(to url: String?, using profileKey: Data, on server: String) -> Promise<Void> {
        print("[Loki] Updating profile picture on server: \(server).")
        return getAuthToken(for: server).then(on: DispatchQueue.global()) { token -> Promise<Void> in
            var annotation: JSON = [ "type" : profilePictureType ]
            if let url = url {
                annotation["value"] = [ "profileKey" : profileKey.base64EncodedString(), "url" : url ]
            }
            let parameters: JSON = [ "annotations" : [ annotation ] ]
            let url = URL(string: "\(server)/users/me")!
            let request = TSRequest(url: url, method: "PATCH", parameters: parameters)
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global()).map { _ in }.recover(on: DispatchQueue.global()) { error in
                print("[Loki] Couldn't update profile picture due to error: \(error).")
                throw error
            }
        }.retryingIfNeeded(maxRetryCount: maxRetryCount)
    }
    
    public static func getInfo(for channel: UInt64, on server: String) -> Promise<LokiPublicChatInfo> {
        let url = URL(string: "\(server)/channels/\(channel)?include_annotations=1")!
        let request = TSRequest(url: url)
        return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global()).map { rawResponse in
            guard let json = rawResponse as? JSON,
                let data = json["data"] as? JSON,
                let annotations = data["annotations"] as? [JSON],
                let annotation = annotations.first,
                let info = annotation["value"] as? JSON,
                let displayName = info["name"] as? String else {
                print("[Loki] Couldn't parse info for public chat channel with ID: \(channel) on server: \(server) from: \(rawResponse).")
                throw LokiDotNetAPIError.parsingFailed
            }
            return LokiPublicChatInfo(displayName: displayName)
        }
    }
    
    public static func reportMessageWithID(_ messageID: UInt64, in channel: UInt64, on server: String) -> Promise<Void> {
        let url = URL(string: "\(server)/loki/v1/channels/\(channel)/messages/\(messageID)/report")!
        let request = TSRequest(url: url, method: "POST", parameters: [:])
        return LokiFileServerProxy(for: server).perform(request).map { _ in }
    }
    
    // MARK: Public API (Obj-C)
    @objc(getMessagesForGroup:onServer:)
    public static func objc_getMessages(for group: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(getMessages(for: group, on: server))
    }
    
    @objc(sendMessage:toGroup:onServer:)
    public static func objc_sendMessage(_ message: LokiPublicChatMessage, to group: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(sendMessage(message, to: group, on: server))
    }
    
    @objc(deleteMessageWithID:forGroup:onServer:isSentByUser:)
    public static func objc_deleteMessage(with messageID: UInt, for group: UInt64, on server: String, isSentByUser: Bool) -> AnyPromise {
        return AnyPromise.from(deleteMessage(with: messageID, for: group, on: server, isSentByUser: isSentByUser))
    }
    
    @objc(getUserCountForGroup:onServer:)
    public static func objc_getUserCount(for group: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(getUserCount(for: group, on: server))
    }
    
    @objc(setDisplayName:on:)
    public static func objc_setDisplayName(to newDisplayName: String?, on server: String) -> AnyPromise {
        return AnyPromise.from(setDisplayName(to: newDisplayName, on: server))
    }
    
    @objc(setProfilePictureURL:usingProfileKey:on:)
    public static func objc_setProfilePicture(to url: String?, using profileKey: Data, on server: String) -> AnyPromise {
        return AnyPromise.from(setProfilePictureURL(to: url, using: profileKey, on: server))
    }
    
    @objc(reportMessageWithID:inChannel:onServer:)
    public static func objc_reportMessageWithID(_ messageID: UInt64, in channel: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(reportMessageWithID(messageID, in: channel, on: server))
    }
}
