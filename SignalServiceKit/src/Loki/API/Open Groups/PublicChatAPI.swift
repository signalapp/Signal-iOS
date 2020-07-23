import PromiseKit

@objc(LKPublicChatAPI)
public final class PublicChatAPI : DotNetAPI {
    private static var moderators: [String:[UInt64:Set<String>]] = [:] // Server URL to (channel ID to set of moderator IDs)

    @objc public static let defaultChats: [PublicChat] = [] // Currently unused

    public static var displayNameUpdatees: [String:Set<String>] = [:]
    
    public static var useOnionRequests = true
    
    // MARK: Settings
    private static let attachmentType = "net.app.core.oembed"
    private static let channelInfoType = "net.patter-app.settings"
    private static let fallbackBatchCount = 64
    private static let maxRetryCount: UInt = 4

    public static let profilePictureType = "network.loki.messenger.avatar"
    
    @objc public static let publicChatMessageType = "network.loki.messenger.publicChat"

    // MARK: Convenience
    private static var userDisplayName: String {
        let userPublicKey = UserDefaults.standard[.masterHexEncodedPublicKey] ?? getUserHexEncodedPublicKey()
        return SSKEnvironment.shared.profileManager.profileNameForRecipient(withID: userPublicKey) ?? "Anonymous"
    }
    
    // MARK: Database
    override internal class var authTokenCollection: String { "LokiGroupChatAuthTokenCollection" }
    
    @objc public static let lastMessageServerIDCollection = "LokiGroupChatLastMessageServerIDCollection"
    @objc public static let lastDeletionServerIDCollection = "LokiGroupChatLastDeletionServerIDCollection"
    
    @objc public static let openGroupPublicKeyCollection = "LokiGroupChatPublicKeyCollection"
    
    private static func getOpenGroupPublicKey(on server: String) -> String? {
        var result: String? = nil
        storage.dbReadConnection.read { transaction in
            result = transaction.object(forKey: "\(server)", inCollection: openGroupPublicKeyCollection) as! String?
        }
        return result
    }
    
    private static func setOpneGroupPublicKey(on server: String, value publicKey: String) {
        try! Storage.writeSync { transaction in
            transaction.setObject(publicKey, forKey: "\(server)", inCollection: openGroupPublicKeyCollection)
        }
    }
    
    private static func removeOpenGroupPublicKey(on server: String) {
        try! Storage.writeSync { transaction in
            transaction.removeObject(forKey: "\(server)", inCollection: openGroupPublicKeyCollection)
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
        try! Storage.writeSync { transaction in
            transaction.setObject(newValue, forKey: "\(server).\(group)", inCollection: lastMessageServerIDCollection)
        }
    }
    
    private static func removeLastMessageServerID(for group: UInt64, on server: String) {
        try! Storage.writeSync { transaction in
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
        try! Storage.writeSync { transaction in
            transaction.setObject(newValue, forKey: "\(server).\(group)", inCollection: lastDeletionServerIDCollection)
        }
    }
    
    private static func removeLastDeletionServerID(for group: UInt64, on server: String) {
        try! Storage.writeSync { transaction in
            transaction.removeObject(forKey: "\(server).\(group)", inCollection: lastDeletionServerIDCollection)
        }
    }
    
    public static func clearCaches(for channel: UInt64, on server: String) {
        removeLastMessageServerID(for: channel, on: server)
        removeLastDeletionServerID(for: channel, on: server)
        removeOpenGroupPublicKey(on: server)
    }
    
    // MARK: Open Group Public Key Validation
    public static func getOpenGroupServerPublicKey(on server: String) -> Promise<String> {
        if let publicKey = getOpenGroupPublicKey(on: server) {
            return Promise.value(publicKey)
        } else {
            return FileServerAPI.getOpenGroupKey(for: server).then2 { hexEncodedPublicKey -> Promise<String> in
                let url = URL(string: server)!
                let request = TSRequest(url: url)
                return OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublicKey, noJSON: true).map2 { _ -> String in
                    setOpneGroupPublicKey(on: server, value: hexEncodedPublicKey)
                    return hexEncodedPublicKey
                }
            }
        }
    }
    
    // MARK: Receiving
    @objc(getMessagesForGroup:onServer:)
    public static func objc_getMessages(for group: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(getMessages(for: group, on: server))
    }

    public static func getMessages(for channel: UInt64, on server: String) -> Promise<[PublicChatMessage]> {
        
        func handleMessages(rawResponse: Any) throws -> [PublicChatMessage] {
            guard let json = rawResponse as? JSON, let rawMessages = json["data"] as? [JSON] else {
                print("[Loki] Couldn't parse messages for public chat channel with ID: \(channel) on server: \(server) from: \(rawResponse).")
                throw DotNetAPIError.parsingFailed
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
                var profilePicture: PublicChatMessage.ProfilePicture? = nil
                let displayName = user["name"] as? String ?? NSLocalizedString("Anonymous", comment: "")
                if let userAnnotations = user["annotations"] as? [JSON], let profilePictureAnnotation = userAnnotations.first(where: { $0["type"] as? String == profilePictureType }),
                    let profilePictureValue = profilePictureAnnotation["value"] as? JSON, let profileKeyString = profilePictureValue["profileKey"] as? String, let profileKey = Data(base64Encoded: profileKeyString), let url = profilePictureValue["url"] as? String {
                    profilePicture = PublicChatMessage.ProfilePicture(profileKey: profileKey, url: url)
                }
                let lastMessageServerID = getLastMessageServerID(for: channel, on: server)
                if serverID > (lastMessageServerID ?? 0) { setLastMessageServerID(for: channel, on: server, to: serverID) }
                let quote: PublicChatMessage.Quote?
                if let quoteAsJSON = value["quote"] as? JSON, let quotedMessageTimestamp = quoteAsJSON["id"] as? UInt64, let quoteePublicKey = quoteAsJSON["author"] as? String,
                    let quotedMessageBody = quoteAsJSON["text"] as? String {
                    let quotedMessageServerID = message["reply_to"] as? UInt64
                    quote = PublicChatMessage.Quote(quotedMessageTimestamp: quotedMessageTimestamp, quoteePublicKey: quoteePublicKey, quotedMessageBody: quotedMessageBody,
                        quotedMessageServerID: quotedMessageServerID)
                } else {
                    quote = nil
                }
                let signature = PublicChatMessage.Signature(data: Data(hex: hexEncodedSignatureData), version: signatureVersion)
                let attachmentsAsJSON = annotations.filter { $0["type"] as? String == attachmentType }
                let attachments: [PublicChatMessage.Attachment] = attachmentsAsJSON.compactMap { attachmentAsJSON in
                    guard let value = attachmentAsJSON["value"] as? JSON, let kindAsString = value["lokiType"] as? String, let kind = PublicChatMessage.Attachment.Kind(rawValue: kindAsString),
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
                    return PublicChatMessage.Attachment(kind: kind, server: server, serverID: serverID, contentType: contentType, size: size, fileName: fileName, flags: flags,
                        width: width, height: height, caption: caption, url: url, linkPreviewURL: linkPreviewURL, linkPreviewTitle: linkPreviewTitle)
                }
                let result = PublicChatMessage(serverID: serverID, senderPublicKey: hexEncodedPublicKey, displayName: displayName, profilePicture: profilePicture,
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

        var queryParameters = "include_annotations=1"
        if let lastMessageServerID = getLastMessageServerID(for: channel, on: server) {
            queryParameters += "&since_id=\(lastMessageServerID)"
        } else {
            queryParameters += "&count=\(fallbackBatchCount)&include_deleted=0"
        }
        return getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<[PublicChatMessage]> in
            let url = URL(string: "\(server)/channels/\(channel)/messages?\(queryParameters)")!
            let request = TSRequest(url: url)
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            if (useOnionRequests) {
                return getOpenGroupServerPublicKey(on: server).then2 { hexEncodedPublickey in
                    OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublickey).map2 { rawResponse in
                        return try handleMessages(rawResponse: rawResponse)
                    }
                }
            }
            return LokiFileServerProxy(for: server).perform(request).map(on: DispatchQueue.global(qos: .default)) { rawResponse in
                return try handleMessages(rawResponse: rawResponse)
            }
        }.handlingInvalidAuthTokenIfNeeded(for: server)
    }

    // MARK: Sending
    @objc(sendMessage:toGroup:onServer:)
    public static func objc_sendMessage(_ message: PublicChatMessage, to group: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(sendMessage(message, to: group, on: server))
    }

    public static func sendMessage(_ message: PublicChatMessage, to channel: UInt64, on server: String) -> Promise<PublicChatMessage> {
        
        func handleSendMessageResult(rawResponse: Any, with displayName: String, for signedMessage: PublicChatMessage) throws -> PublicChatMessage {
            // ISO8601DateFormatter doesn't support milliseconds before iOS 11
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            guard let json = rawResponse as? JSON, let messageAsJSON = json["data"] as? JSON, let serverID = messageAsJSON["id"] as? UInt64, let body = messageAsJSON["text"] as? String,
                let dateAsString = messageAsJSON["created_at"] as? String, let date = dateFormatter.date(from: dateAsString) else {
                print("[Loki] Couldn't parse message for public chat channel with ID: \(channel) on server: \(server) from: \(rawResponse).")
                throw DotNetAPIError.parsingFailed
            }
            let timestamp = UInt64(date.timeIntervalSince1970) * 1000
            return PublicChatMessage(serverID: serverID, senderPublicKey: getUserHexEncodedPublicKey(), displayName: displayName, profilePicture: signedMessage.profilePicture, body: body, type: publicChatMessageType, timestamp: timestamp, quote: signedMessage.quote, attachments: signedMessage.attachments, signature: signedMessage.signature)
        }

        print("[Loki] Sending message to public chat channel with ID: \(channel) on server: \(server).")
        let (promise, seal) = Promise<PublicChatMessage>.pending()
        DispatchQueue.global(qos: .userInitiated).async { [privateKey = userKeyPair.privateKey] in
            guard let signedMessage = message.sign(with: privateKey) else { return seal.reject(DotNetAPIError.signingFailed) }
            attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
                getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<PublicChatMessage> in
                    let url = URL(string: "\(server)/channels/\(channel)/messages")!
                    let parameters = signedMessage.toJSON()
                    let request = TSRequest(url: url, method: "POST", parameters: parameters)
                    request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                    let displayName = userDisplayName
                    if (useOnionRequests) {
                        return getOpenGroupServerPublicKey(on: server).then2 { hexEncodedPublicKey in
                            OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublicKey).map2 { rawResponse in
                                return try handleSendMessageResult(rawResponse: rawResponse, with: displayName, for: signedMessage)
                            }
                        }
                    }
                    return LokiFileServerProxy(for: server).perform(request).map(on: DispatchQueue.global(qos: .default)) { rawResponse in
                        return try handleSendMessageResult(rawResponse: rawResponse, with: displayName, for: signedMessage)
                    }
                }.handlingInvalidAuthTokenIfNeeded(for: server)
            }.done(on: DispatchQueue.global(qos: .default)) { message in
                seal.fulfill(message)
            }.catch(on: DispatchQueue.global(qos: .default)) { error in
                seal.reject(error)
            }
        }
        return promise
    }

    // MARK: Deletion
    public static func getDeletedMessageServerIDs(for channel: UInt64, on server: String) -> Promise<[UInt64]> {
        
        func handleDeletedMessageServerIDs(rawResponse: Any) throws -> [UInt64] {
            guard let json = rawResponse as? JSON, let deletions = json["data"] as? [JSON] else {
                print("[Loki] Couldn't parse deleted messages for public chat channel with ID: \(channel) on server: \(server) from: \(rawResponse).")
                throw DotNetAPIError.parsingFailed
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
        
        print("[Loki] Getting deleted messages for public chat channel with ID: \(channel) on server: \(server).")
        let queryParameters: String
        if let lastDeletionServerID = getLastDeletionServerID(for: channel, on: server) {
            queryParameters = "since_id=\(lastDeletionServerID)"
        } else {
            queryParameters = "count=\(fallbackBatchCount)"
        }
        return getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<[UInt64]> in
            let url = URL(string: "\(server)/loki/v1/channel/\(channel)/deletes?\(queryParameters)")!
            let request = TSRequest(url: url)
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            if (useOnionRequests) {
                return getOpenGroupServerPublicKey(on: server).then2 { hexEncodedPublicKey in
                    OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublicKey).map2 { rawResponse in
                        return try handleDeletedMessageServerIDs(rawResponse: rawResponse)
                    }
                }
            }
            return LokiFileServerProxy(for: server).perform(request).map(on: DispatchQueue.global(qos: .default)) { rawResponse in
                return try handleDeletedMessageServerIDs(rawResponse: rawResponse)
            }
        }.handlingInvalidAuthTokenIfNeeded(for: server)
    }

    @objc(deleteMessageWithID:forGroup:onServer:isSentByUser:)
    public static func objc_deleteMessage(with messageID: UInt, for group: UInt64, on server: String, isSentByUser: Bool) -> AnyPromise {
        return AnyPromise.from(deleteMessage(with: messageID, for: group, on: server, isSentByUser: isSentByUser))
    }
    
    public static func deleteMessage(with messageID: UInt, for channel: UInt64, on server: String, isSentByUser: Bool) -> Promise<Void> {
        let isModerationRequest = !isSentByUser
        print("[Loki] Deleting message with ID: \(messageID) for public chat channel with ID: \(channel) on server: \(server) (isModerationRequest = \(isModerationRequest)).")
        let urlAsString = isSentByUser ? "\(server)/channels/\(channel)/messages/\(messageID)" : "\(server)/loki/v1/moderation/message/\(messageID)"
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
            getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Void> in
                let url = URL(string: urlAsString)!
                let request = TSRequest(url: url, method: "DELETE", parameters: [:])
                request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                if (useOnionRequests) {
                    return getOpenGroupServerPublicKey(on: server).then2 { hexEncodedPublicKey in
                        OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublicKey).done2 { result -> Void in
                            print("[Loki] Deleted message with ID: \(messageID) on server: \(server).")
                        }
                    }
                }
                return LokiFileServerProxy(for: server).perform(request).done(on: DispatchQueue.global(qos: .default)) { result -> Void in
                    print("[Loki] Deleted message with ID: \(messageID) on server: \(server).")
                }
            }.handlingInvalidAuthTokenIfNeeded(for: server)
        }
    }

    // MARK: Display Name & Profile Picture
    public static func getDisplayNames(for channel: UInt64, on server: String) -> Promise<Void> {
        
        func handleDisplayNames(rawResponse: Any, for hexEncodedPublicKeys: Set<String>) throws {
            guard let json = rawResponse as? JSON, let data = json["data"] as? [JSON] else {
                print("[Loki] Couldn't parse display names for users: \(hexEncodedPublicKeys) from: \(rawResponse).")
                throw DotNetAPIError.parsingFailed
            }
            try! Storage.writeSync { transaction in
                data.forEach { data in
                    guard let user = data["user"] as? JSON, let hexEncodedPublicKey = user["username"] as? String, let rawDisplayName = user["name"] as? String else { return }
                    let endIndex = hexEncodedPublicKey.endIndex
                    let cutoffIndex = hexEncodedPublicKey.index(endIndex, offsetBy: -8)
                    let displayName = "\(rawDisplayName) (...\(hexEncodedPublicKey[cutoffIndex..<endIndex]))"
                    transaction.setObject(displayName, forKey: hexEncodedPublicKey, inCollection: "\(server).\(channel)")
                }
            }
        }
        
        let publicChatID = "\(server).\(channel)"
        guard let hexEncodedPublicKeys = displayNameUpdatees[publicChatID] else { return Promise.value(()) }
        displayNameUpdatees[publicChatID] = []
        print("[Loki] Getting display names for: \(hexEncodedPublicKeys).")
        return getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Void> in
            let queryParameters = "ids=\(hexEncodedPublicKeys.map { "@\($0)" }.joined(separator: ","))&include_user_annotations=1"
            let url = URL(string: "\(server)/users?\(queryParameters)")!
            let request = TSRequest(url: url)
            if (useOnionRequests) {
                return getOpenGroupServerPublicKey(on: server).then2 { hexEncodedPublicKey in
                    OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublicKey).map2 { rawResponse in
                        try handleDisplayNames(rawResponse: rawResponse, for: hexEncodedPublicKeys)
                    }
                }
            }
            return LokiFileServerProxy(for: server).perform(request).map(on: DispatchQueue.global(qos: .default)) { rawResponse in
                try handleDisplayNames(rawResponse: rawResponse, for: hexEncodedPublicKeys)
            }
        }.handlingInvalidAuthTokenIfNeeded(for: server)
    }

    @objc(setDisplayName:on:)
    public static func objc_setDisplayName(to newDisplayName: String?, on server: String) -> AnyPromise {
        return AnyPromise.from(setDisplayName(to: newDisplayName, on: server))
    }

    public static func setDisplayName(to newDisplayName: String?, on server: String) -> Promise<Void> {
        print("[Loki] Updating display name on server: \(server).")
        let parameters: JSON = [ "name" : (newDisplayName ?? "") ]
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
            getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Void> in
                let url = URL(string: "\(server)/users/me")!
                let request = TSRequest(url: url, method: "PATCH", parameters: parameters)
                request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                if (useOnionRequests) {
                    return getOpenGroupServerPublicKey(on: server).then2 { hexEncodedPublicKey in
                        OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublicKey).map2 { _ in }.recover(on: DispatchQueue.global(qos: .default)) { error in
                            print("Couldn't update display name due to error: \(error).")
                            throw error
                        }
                    }
                }
                return LokiFileServerProxy(for: server).perform(request).map(on: DispatchQueue.global(qos: .default)) { _ in }.recover(on: DispatchQueue.global(qos: .default)) { error in
                    print("Couldn't update display name due to error: \(error).")
                    throw error
                }
            }.handlingInvalidAuthTokenIfNeeded(for: server)
        }
    }

    @objc(setProfilePictureURL:usingProfileKey:on:)
    public static func objc_setProfilePicture(to url: String?, using profileKey: Data, on server: String) -> AnyPromise {
        return AnyPromise.from(setProfilePictureURL(to: url, using: profileKey, on: server))
    }

    public static func setProfilePictureURL(to url: String?, using profileKey: Data, on server: String) -> Promise<Void> {
        print("[Loki] Updating profile picture on server: \(server).")
        var annotation: JSON = [ "type" : profilePictureType ]
        if let url = url {
            annotation["value"] = [ "profileKey" : profileKey.base64EncodedString(), "url" : url ]
        }
        let parameters: JSON = [ "annotations" : [ annotation ] ]
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
            getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Void> in
                let url = URL(string: "\(server)/users/me")!
                let request = TSRequest(url: url, method: "PATCH", parameters: parameters)
                request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                if (useOnionRequests) {
                    return getOpenGroupServerPublicKey(on: server).then2 { hexEncodedPublicKey in
                        OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublicKey).map2 { _ in }.recover(on: DispatchQueue.global(qos: .default)) { error in
                            print("[Loki] Couldn't update profile picture due to error: \(error).")
                            throw error
                        }
                    }
                }
                return LokiFileServerProxy(for: server).perform(request).map(on: DispatchQueue.global(qos: .default)) { _ in }.recover(on: DispatchQueue.global(qos: .default)) { error in
                    print("[Loki] Couldn't update profile picture due to error: \(error).")
                    throw error
                }
            }.handlingInvalidAuthTokenIfNeeded(for: server)
        }
    }

    static func updateProfileIfNeeded(for channel: UInt64, on server: String, from info: PublicChatInfo) {
        let storage = OWSPrimaryStorage.shared()
        let publicChatID = "\(server).\(channel)"
        try! Storage.writeSync { transaction in
            // Update user count
            storage.setUserCount(info.memberCount, forPublicChatWithID: publicChatID, in: transaction)
            let groupThread = TSGroupThread.getOrCreateThread(withGroupId: publicChatID.data(using: .utf8)!, groupType: .openGroup, transaction: transaction)
            // Update display name if needed
            let groupModel = groupThread.groupModel
            if groupModel.groupName != info.displayName {
                let newGroupModel = TSGroupModel(title: info.displayName, memberIds: groupModel.groupMemberIds, image: groupModel.groupImage, groupId: groupModel.groupId, groupType: groupModel.groupType, adminIds: groupModel.groupAdminIds)
                groupThread.groupModel = newGroupModel
                groupThread.save(with: transaction)
            }
            // Download and update profile picture if needed
            let oldProfilePictureURL = storage.getProfilePictureURL(forPublicChatWithID: publicChatID, in: transaction)
            if oldProfilePictureURL != info.profilePictureURL || groupModel.groupImage == nil {
                storage.setProfilePictureURL(info.profilePictureURL, forPublicChatWithID: publicChatID, in: transaction)
                if let avatarURL = info.profilePictureURL {
                    let configuration = URLSessionConfiguration.default
                    let manager = AFURLSessionManager.init(sessionConfiguration: configuration)
                    let url = URL(string: "\(server)\(avatarURL)")!
                    let request = URLRequest(url: url)
                    let task = manager.downloadTask(with: request, progress: nil,
                        destination: { (targetPath: URL, response: URLResponse) -> URL in
                            let tempFilePath = URL(fileURLWithPath: OWSTemporaryDirectoryAccessibleAfterFirstAuth()).appendingPathComponent(UUID().uuidString)
                            return tempFilePath
                        },
                        completionHandler: { (response: URLResponse, filePath: URL?, error: Error?) in
                            if let error = error {
                                print("[Loki] Couldn't download profile picture for public chat channel with ID: \(channel) on server: \(server).")
                                return
                            }
                            if let filePath = filePath, let avatarData = try? Data.init(contentsOf: filePath) {
                                let attachmentStream = TSAttachmentStream(contentType: OWSMimeTypeImageJpeg, byteCount: UInt32(avatarData.count), sourceFilename: nil, caption: nil, albumMessageId: nil)
                                try! attachmentStream.write(avatarData)
                                groupThread.updateAvatar(with: attachmentStream)
                            }
                    })
                    task.resume()
                }
            }
        }
    }

    // MARK: Joining & Leaving
    @objc(getInfoForChannelWithID:onServer:)
    public static func objc_getInfo(for channel: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(getInfo(for: channel, on: server))
    }

    public static func getInfo(for channel: UInt64, on server: String) -> Promise<PublicChatInfo> {
        
        func handleInfo(rawResponse: Any) throws -> PublicChatInfo {
            guard let json = rawResponse as? JSON,
                let data = json["data"] as? JSON,
                let annotations = data["annotations"] as? [JSON],
                let annotation = annotations.first,
                let info = annotation["value"] as? JSON,
                let displayName = info["name"] as? String,
                let profilePictureURL = info["avatar"] as? String,
                let countInfo = data["counts"] as? JSON,
                let memberCount = countInfo["subscribers"] as? Int else {
                print("[Loki] Couldn't parse info for public chat channel with ID: \(channel) on server: \(server) from: \(rawResponse).")
                throw DotNetAPIError.parsingFailed
            }
            let storage = OWSPrimaryStorage.shared()
            try! Storage.writeSync { transaction in
                storage.setUserCount(memberCount, forPublicChatWithID: "\(server).\(channel)", in: transaction)
            }
            let publicChatInfo = PublicChatInfo(displayName: displayName, profilePictureURL: profilePictureURL, memberCount: memberCount)
            updateProfileIfNeeded(for: channel, on: server, from: publicChatInfo)
            return publicChatInfo
        }

        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
            getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<PublicChatInfo> in
                let url = URL(string: "\(server)/channels/\(channel)?include_annotations=1")!
                let request = TSRequest(url: url)
                request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                if (useOnionRequests) {
                    return getOpenGroupServerPublicKey(on: server).then2 { hexEncodedPublicKey in
                        return OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublicKey).map2 { rawResponse in
                            return try handleInfo(rawResponse: rawResponse)
                        }
                    }
                }
                return LokiFileServerProxy(for: server).perform(request).map(on: DispatchQueue.global(qos: .default)) { rawResponse in
                    return try handleInfo(rawResponse: rawResponse)
                }
            }.handlingInvalidAuthTokenIfNeeded(for: server)
        }
    }

    public static func join(_ channel: UInt64, on server: String) -> Promise<Void> {
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
            getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Void> in
                let url = URL(string: "\(server)/channels/\(channel)/subscribe")!
                let request = TSRequest(url: url, method: "POST", parameters: [:])
                request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                if (useOnionRequests) {
                    return getOpenGroupServerPublicKey(on: server).then2 { hexEncodedPublicKey in
                        OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublicKey).done2 { result -> Void in
                            print("[Loki] Joined channel with ID: \(channel) on server: \(server).")
                        }
                    }
                }
                return LokiFileServerProxy(for: server).perform(request).done(on: DispatchQueue.global(qos: .default)) { result -> Void in
                    print("[Loki] Joined channel with ID: \(channel) on server: \(server).")
                }
            }.handlingInvalidAuthTokenIfNeeded(for: server)
        }
    }

    public static func leave(_ channel: UInt64, on server: String) -> Promise<Void> {
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
            getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Void> in
                let url = URL(string: "\(server)/channels/\(channel)/subscribe")!
                let request = TSRequest(url: url, method: "DELETE", parameters: [:])
                request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                if (useOnionRequests) {
                    return getOpenGroupServerPublicKey(on: server).then2 { hexEncodedPublicKey in
                        OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublicKey).done2 { result -> Void in
                            print("[Loki] Left channel with ID: \(channel) on server: \(server).")
                        }
                    }
                }
                return LokiFileServerProxy(for: server).perform(request).done(on: DispatchQueue.global(qos: .default)) { result -> Void in
                    print("[Loki] Left channel with ID: \(channel) on server: \(server).")
                }
            }.handlingInvalidAuthTokenIfNeeded(for: server)
        }
    }

    // MARK: Reporting
    @objc(reportMessageWithID:inChannel:onServer:)
    public static func objc_reportMessageWithID(_ messageID: UInt64, in channel: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(reportMessageWithID(messageID, in: channel, on: server))
    }

    public static func reportMessageWithID(_ messageID: UInt64, in channel: UInt64, on server: String) -> Promise<Void> {
        let url = URL(string: "\(server)/loki/v1/channels/\(channel)/messages/\(messageID)/report")!
        let request = TSRequest(url: url, method: "POST", parameters: [:])
        // Only used for the Loki Public Chat which doesn't require authentication
        if (useOnionRequests) {
            return getOpenGroupServerPublicKey(on: server).then2 { hexEncodedPublicKey in
                OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublicKey).map2 { _ in}
            }
        }
        return LokiFileServerProxy(for: server).perform(request).map(on: DispatchQueue.global(qos: .default)) { _ in }
    }

    // MARK: Moderators
    public static func getModerators(for channel: UInt64, on server: String) -> Promise<Set<String>> {
        
        func handleModerators(rawResponse: Any) throws -> Set<String> {
            guard let json = rawResponse as? JSON, let moderators = json["moderators"] as? [String] else {
                print("[Loki] Couldn't parse moderators for public chat channel with ID: \(channel) on server: \(server) from: \(rawResponse).")
                throw DotNetAPIError.parsingFailed
            }
            let moderatorsAsSet = Set(moderators);
            if self.moderators.keys.contains(server) {
                self.moderators[server]![channel] = moderatorsAsSet
            } else {
                self.moderators[server] = [ channel : moderatorsAsSet ]
            }
            return moderatorsAsSet
        }
        
        return getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Set<String>> in
            let url = URL(string: "\(server)/loki/v1/channel/\(channel)/get_moderators")!
            let request = TSRequest(url: url)
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            if (useOnionRequests) {
                return getOpenGroupServerPublicKey(on: server).then2 { hexEncodedPublicKey in
                    OnionRequestAPI.sendOnionRequestLsrpcDest(request, server: server, using: hexEncodedPublicKey).map2 { rawResponse in
                        return try handleModerators(rawResponse: rawResponse)
                    }
                }
            }
            return LokiFileServerProxy(for: server).perform(request).map(on: DispatchQueue.global(qos: .default)) { rawResponse in
                return try handleModerators(rawResponse: rawResponse)
            }
        }.handlingInvalidAuthTokenIfNeeded(for: server)
    }

    @objc(isUserModerator:forChannel:onServer:)
    public static func isUserModerator(_ hexEncodedPublicString: String, for channel: UInt64, on server: String) -> Bool {
        return moderators[server]?[channel]?.contains(hexEncodedPublicString) ?? false
    }
}
