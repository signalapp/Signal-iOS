import AFNetworking
import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

@objc(SNOpenGroupAPI)
public final class OpenGroupAPI : DotNetAPI {
    private static var moderators: [String:[UInt64:Set<String>]] = [:] // Server URL to (channel ID to set of moderator IDs)

    public static var displayNameUpdatees: [String:Set<String>] = [:]

    // MARK: Settings
    private static let attachmentType = "net.app.core.oembed"
    private static let channelInfoType = "net.patter-app.settings"
    private static let fallbackBatchCount = 64
    private static let maxRetryCount: UInt = 4

    public static let profilePictureType = "network.loki.messenger.avatar"
    @objc public static let openGroupMessageType = "network.loki.messenger.publicChat"

    // MARK: Open Group Public Key Validation
    public static func getOpenGroupServerPublicKey(for server: String) -> Promise<String> {
        if let publicKey = SNMessagingKitConfiguration.shared.storage.getOpenGroupPublicKey(for: server) {
            return Promise.value(publicKey)
        } else {
            return FileServerAPI.getPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { publicKey -> Promise<String> in
                let url = URL(string: server)!
                let request = TSRequest(url: url)
                return OnionRequestAPI.sendOnionRequest(request, to: server, using: publicKey, isJSONRequired: false).map(on: DispatchQueue.global(qos: .default)) { _ -> String in
                    SNMessagingKitConfiguration.shared.storage.with { transaction in
                        SNMessagingKitConfiguration.shared.storage.setOpenGroupPublicKey(for: server, to: publicKey, using: transaction)
                    }
                    return publicKey
                }
            }
        }
    }
    
    // MARK: Receiving
    @objc(getMessagesForGroup:onServer:)
    public static func objc_getMessages(for group: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(getMessages(for: group, on: server))
    }

    public static func getMessages(for channel: UInt64, on server: String) -> Promise<[OpenGroupMessage]> {
        let storage = SNMessagingKitConfiguration.shared.storage
        var queryParameters = "include_annotations=1"
        if let lastMessageServerID = storage.getLastMessageServerID(for: channel, on: server) {
            queryParameters += "&since_id=\(lastMessageServerID)"
        } else {
            queryParameters += "&count=\(fallbackBatchCount)&include_deleted=0"
        }
        return getOpenGroupServerPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { serverPublicKey in
            getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<[OpenGroupMessage]> in
                let url = URL(string: "\(server)/channels/\(channel)/messages?\(queryParameters)")!
                let request = TSRequest(url: url)
                request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                return OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey).map(on: DispatchQueue.global(qos: .default)) { json in
                    guard let rawMessages = json["data"] as? [JSON] else {
                        SNLog("Couldn't parse messages for open group channel with ID: \(channel) on server: \(server) from: \(json).")
                        throw Error.parsingFailed
                    }
                    return rawMessages.compactMap { message in
                        let isDeleted = (message["is_deleted"] as? Int == 1)
                        guard !isDeleted else { return nil }
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                        guard let annotations = message["annotations"] as? [JSON], let annotation = annotations.first(where: { $0["type"] as? String == openGroupMessageType }), let value = annotation["value"] as? JSON,
                            let serverID = message["id"] as? UInt64, let hexEncodedSignatureData = value["sig"] as? String, let signatureVersion = value["sigver"] as? UInt64,
                            let body = message["text"] as? String, let user = message["user"] as? JSON, let hexEncodedPublicKey = user["username"] as? String,
                            let timestamp = value["timestamp"] as? UInt64, let dateAsString = message["created_at"] as? String, let date = dateFormatter.date(from: dateAsString) else {
                                SNLog("Couldn't parse message for open group channel with ID: \(channel) on server: \(server) from: \(message).")
                                return nil
                        }
                        let serverTimestamp = UInt64(date.timeIntervalSince1970) * 1000
                        var profilePicture: OpenGroupMessage.ProfilePicture? = nil
                        let displayName = user["name"] as? String ?? NSLocalizedString("Anonymous", comment: "")
                        if let userAnnotations = user["annotations"] as? [JSON], let profilePictureAnnotation = userAnnotations.first(where: { $0["type"] as? String == profilePictureType }),
                            let profilePictureValue = profilePictureAnnotation["value"] as? JSON, let profileKeyString = profilePictureValue["profileKey"] as? String, let profileKey = Data(base64Encoded: profileKeyString), let url = profilePictureValue["url"] as? String {
                            profilePicture = OpenGroupMessage.ProfilePicture(profileKey: profileKey, url: url)
                        }
                        let lastMessageServerID = storage.getLastMessageServerID(for: channel, on: server)
                        if serverID > (lastMessageServerID ?? 0) {
                            storage.with { transaction in
                                storage.setLastMessageServerID(for: channel, on: server, to: serverID, using: transaction)
                            }
                        }
                        let quote: OpenGroupMessage.Quote?
                        if let quoteAsJSON = value["quote"] as? JSON, let quotedMessageTimestamp = quoteAsJSON["id"] as? UInt64, let quoteePublicKey = quoteAsJSON["author"] as? String,
                           let quotedMessageBody = quoteAsJSON["text"] as? String {
                            let quotedMessageServerID = message["reply_to"] as? UInt64
                            quote = OpenGroupMessage.Quote(quotedMessageTimestamp: quotedMessageTimestamp, quoteePublicKey: quoteePublicKey, quotedMessageBody: quotedMessageBody,
                                quotedMessageServerID: quotedMessageServerID)
                        } else {
                            quote = nil
                        }
                        let signature = OpenGroupMessage.Signature(data: Data(hex: hexEncodedSignatureData), version: signatureVersion)
                        let attachmentsAsJSON = annotations.filter { $0["type"] as? String == attachmentType }
                        let attachments: [OpenGroupMessage.Attachment] = attachmentsAsJSON.compactMap { attachmentAsJSON in
                            guard let value = attachmentAsJSON["value"] as? JSON, let kindAsString = value["lokiType"] as? String, let kind = OpenGroupMessage.Attachment.Kind(rawValue: kindAsString),
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
                                    SNLog("Ignoring open group message with invalid link preview.")
                                    return nil
                                }
                            }
                            return OpenGroupMessage.Attachment(kind: kind, server: server, serverID: serverID, contentType: contentType, size: size, fileName: fileName, flags: flags,
                                width: width, height: height, caption: caption, url: url, linkPreviewURL: linkPreviewURL, linkPreviewTitle: linkPreviewTitle)
                        }
                        let result = OpenGroupMessage(serverID: serverID, senderPublicKey: hexEncodedPublicKey, displayName: displayName, profilePicture: profilePicture,
                            body: body, type: openGroupMessageType, timestamp: timestamp, quote: quote, attachments: attachments, signature: signature, serverTimestamp: serverTimestamp)
                        guard result.hasValidSignature() else {
                            SNLog("Ignoring open group message with invalid signature.")
                            return nil
                        }
                        let existingMessageID = storage.getIDForMessage(withServerID: result.serverID!)
                        guard existingMessageID == nil else {
                            SNLog("Ignoring duplicate open group message.")
                            return nil
                        }
                        return result
                    }.sorted { $0.serverTimestamp < $1.serverTimestamp}
                }
            }
        }.handlingInvalidAuthTokenIfNeeded(for: server)
    }

    // MARK: Sending
    @objc(sendMessage:toGroup:onServer:)
    public static func objc_sendMessage(_ message: OpenGroupMessage, to group: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(sendMessage(message, to: group, on: server))
    }

    public static func sendMessage(_ message: OpenGroupMessage, to channel: UInt64, on server: String) -> Promise<OpenGroupMessage> {
        SNLog("Sending message to open group channel with ID: \(channel) on server: \(server).")
        let storage = SNMessagingKitConfiguration.shared.storage
        guard let userKeyPair = storage.getUserKeyPair() else { return Promise(error: Error.generic) }
        guard let userDisplayName = storage.getUserDisplayName() else { return Promise(error: Error.generic) }
        let (promise, seal) = Promise<OpenGroupMessage>.pending()
        DispatchQueue.global(qos: .userInitiated).async { [privateKey = userKeyPair.privateKey] in
            guard let signedMessage = message.sign(with: privateKey) else { return seal.reject(Error.signingFailed) }
            attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
                getOpenGroupServerPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { serverPublicKey in
                    getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<OpenGroupMessage> in
                        let url = URL(string: "\(server)/channels/\(channel)/messages")!
                        let parameters = signedMessage.toJSON()
                        let request = TSRequest(url: url, method: "POST", parameters: parameters)
                        request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                        let displayName = userDisplayName
                        return OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey).map(on: DispatchQueue.global(qos: .default)) { json in
                            // ISO8601DateFormatter doesn't support milliseconds before iOS 11
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                            guard let messageAsJSON = json["data"] as? JSON, let serverID = messageAsJSON["id"] as? UInt64, let body = messageAsJSON["text"] as? String,
                                let dateAsString = messageAsJSON["created_at"] as? String, let date = dateFormatter.date(from: dateAsString) else {
                                SNLog("Couldn't parse message for open group channel with ID: \(channel) on server: \(server) from: \(json).")
                                throw Error.parsingFailed
                            }
                            let timestamp = UInt64(date.timeIntervalSince1970) * 1000
                            return OpenGroupMessage(serverID: serverID, senderPublicKey: userKeyPair.publicKey.toHexString(), displayName: displayName, profilePicture: signedMessage.profilePicture, body: body, type: openGroupMessageType, timestamp: timestamp, quote: signedMessage.quote, attachments: signedMessage.attachments, signature: signedMessage.signature, serverTimestamp: timestamp)
                        }
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
        SNLog("Getting deleted messages for open group channel with ID: \(channel) on server: \(server).")
        let storage = SNMessagingKitConfiguration.shared.storage
        let queryParameters: String
        if let lastDeletionServerID = storage.getLastDeletionServerID(for: channel, on: server) {
            queryParameters = "since_id=\(lastDeletionServerID)"
        } else {
            queryParameters = "count=\(fallbackBatchCount)"
        }
        return getOpenGroupServerPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { serverPublicKey in
            getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<[UInt64]> in
                let url = URL(string: "\(server)/loki/v1/channel/\(channel)/deletes?\(queryParameters)")!
                let request = TSRequest(url: url)
                request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                return OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey).map(on: DispatchQueue.global(qos: .default)) { json in
                    guard let body = json["body"] as? JSON, let deletions = body["data"] as? [JSON] else {
                        SNLog("Couldn't parse deleted messages for open group channel with ID: \(channel) on server: \(server) from: \(json).")
                        throw Error.parsingFailed
                    }
                    return deletions.compactMap { deletion in
                        guard let serverID = deletion["id"] as? UInt64, let messageServerID = deletion["message_id"] as? UInt64 else {
                            SNLog("Couldn't parse deleted message for open group channel with ID: \(channel) on server: \(server) from: \(deletion).")
                            return nil
                        }
                        let lastDeletionServerID = storage.getLastDeletionServerID(for: channel, on: server)
                        if serverID > (lastDeletionServerID ?? 0) {
                            storage.with { transaction in
                                storage.setLastDeletionServerID(for: channel, on: server, to: serverID, using: transaction)
                            }
                        }
                        return messageServerID
                    }
                }
            }
        }.handlingInvalidAuthTokenIfNeeded(for: server)
    }

    @objc(deleteMessageWithID:forGroup:onServer:isSentByUser:)
    public static func objc_deleteMessage(with messageID: UInt, for group: UInt64, on server: String, isSentByUser: Bool) -> AnyPromise {
        return AnyPromise.from(deleteMessage(with: messageID, for: group, on: server, isSentByUser: isSentByUser))
    }
    
    public static func deleteMessage(with messageID: UInt, for channel: UInt64, on server: String, isSentByUser: Bool) -> Promise<Void> {
        let isModerationRequest = !isSentByUser
        SNLog("Deleting message with ID: \(messageID) for open group channel with ID: \(channel) on server: \(server) (isModerationRequest = \(isModerationRequest)).")
        let urlAsString = isSentByUser ? "\(server)/channels/\(channel)/messages/\(messageID)" : "\(server)/loki/v1/moderation/message/\(messageID)"
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
            getOpenGroupServerPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { serverPublicKey in
                getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Void> in
                    let url = URL(string: urlAsString)!
                    let request = TSRequest(url: url, method: "DELETE", parameters: [:])
                    request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                    return OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey, isJSONRequired: false).done(on: DispatchQueue.global(qos: .default)) { _ -> Void in
                        SNLog("Deleted message with ID: \(messageID) on server: \(server).")
                    }
                }
            }.handlingInvalidAuthTokenIfNeeded(for: server)
        }
    }

    // MARK: Display Name & Profile Picture
    public static func getDisplayNames(for channel: UInt64, on server: String) -> Promise<Void> {
        let openGroupID = "\(server).\(channel)"
        guard let publicKeys = displayNameUpdatees[openGroupID] else { return Promise.value(()) }
        displayNameUpdatees[openGroupID] = []
        SNLog("Getting display names for: \(publicKeys).")
        return getOpenGroupServerPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { serverPublicKey in
            getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Void> in
                let queryParameters = "ids=\(publicKeys.map { "@\($0)" }.joined(separator: ","))&include_user_annotations=1"
                let url = URL(string: "\(server)/users?\(queryParameters)")!
                let request = TSRequest(url: url)
                return OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey).map(on: DispatchQueue.global(qos: .default)) { json in
                    guard let data = json["data"] as? [JSON] else {
                        SNLog("Couldn't parse display names for users: \(publicKeys) from: \(json).")
                        throw Error.parsingFailed
                    }
                    let storage = SNMessagingKitConfiguration.shared.storage
                    storage.with { transaction in
                        data.forEach { data in
                            guard let user = data["user"] as? JSON, let hexEncodedPublicKey = user["username"] as? String, let rawDisplayName = user["name"] as? String else { return }
                            let endIndex = hexEncodedPublicKey.endIndex
                            let cutoffIndex = hexEncodedPublicKey.index(endIndex, offsetBy: -8)
                            let displayName = "\(rawDisplayName) (...\(hexEncodedPublicKey[cutoffIndex..<endIndex]))"
                            storage.setOpenGroupDisplayName(to: displayName, for: hexEncodedPublicKey, inOpenGroupWithID: "\(server).\(channel)", using: transaction)
                        }
                    }
                }
            }
        }.handlingInvalidAuthTokenIfNeeded(for: server)
    }

    @objc(setDisplayName:on:)
    public static func objc_setDisplayName(to newDisplayName: String?, on server: String) -> AnyPromise {
        return AnyPromise.from(setDisplayName(to: newDisplayName, on: server))
    }

    public static func setDisplayName(to newDisplayName: String?, on server: String) -> Promise<Void> {
        SNLog("Updating display name on server: \(server).")
        let parameters: JSON = [ "name" : (newDisplayName ?? "") ]
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
            getOpenGroupServerPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { serverPublicKey in
                getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Void> in
                    let url = URL(string: "\(server)/users/me")!
                    let request = TSRequest(url: url, method: "PATCH", parameters: parameters)
                    request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                    return OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey).map(on: DispatchQueue.global(qos: .default)) { _ in }.recover(on: DispatchQueue.global(qos: .default)) { error in
                        print("Couldn't update display name due to error: \(error).")
                        throw error
                    }
                }
            }.handlingInvalidAuthTokenIfNeeded(for: server)
        }
    }

    @objc(setProfilePictureURL:usingProfileKey:on:)
    public static func objc_setProfilePicture(to url: String?, using profileKey: Data, on server: String) -> AnyPromise {
        return AnyPromise.from(setProfilePictureURL(to: url, using: profileKey, on: server))
    }

    public static func setProfilePictureURL(to url: String?, using profileKey: Data, on server: String) -> Promise<Void> {
        SNLog("Updating profile picture on server: \(server).")
        var annotation: JSON = [ "type" : profilePictureType ]
        if let url = url {
            annotation["value"] = [ "profileKey" : profileKey.base64EncodedString(), "url" : url ]
        }
        let parameters: JSON = [ "annotations" : [ annotation ] ]
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
            getOpenGroupServerPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { serverPublicKey in
                getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Void> in
                    let url = URL(string: "\(server)/users/me")!
                    let request = TSRequest(url: url, method: "PATCH", parameters: parameters)
                    request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                    return OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey).map(on: DispatchQueue.global(qos: .default)) { _ in }.recover(on: DispatchQueue.global(qos: .default)) { error in
                        SNLog("Couldn't update profile picture due to error: \(error).")
                        throw error
                    }
                }
            }.handlingInvalidAuthTokenIfNeeded(for: server)
        }
    }

    // MARK: Joining & Leaving
    @objc(getInfoForChannelWithID:onServer:)
    public static func objc_getInfo(for channel: UInt64, on server: String) -> AnyPromise {
        return AnyPromise.from(getInfo(for: channel, on: server))
    }

    public static func getInfo(for channel: UInt64, on server: String) -> Promise<OpenGroupInfo> {
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
            getOpenGroupServerPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { serverPublicKey in
                getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<OpenGroupInfo> in
                    let url = URL(string: "\(server)/channels/\(channel)?include_annotations=1")!
                    let request = TSRequest(url: url)
                    request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                    return OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey).map(on: DispatchQueue.global(qos: .default)) { json in
                        guard let data = json["data"] as? JSON,
                            let annotations = data["annotations"] as? [JSON],
                            let annotation = annotations.first,
                            let info = annotation["value"] as? JSON,
                            let displayName = info["name"] as? String,
                            let profilePictureURL = info["avatar"] as? String,
                            let countInfo = data["counts"] as? JSON,
                            let memberCount = countInfo["subscribers"] as? Int else {
                            SNLog("Couldn't parse info for open group channel with ID: \(channel) on server: \(server) from: \(json).")
                            throw Error.parsingFailed
                        }
                        let storage = SNMessagingKitConfiguration.shared.storage
                        storage.with { transaction in
                            storage.setUserCount(to: memberCount, forOpenGroupWithID: "\(server).\(channel)", using: transaction)
                        }
                        let openGroupInfo = OpenGroupInfo(displayName: displayName, profilePictureURL: profilePictureURL, memberCount: memberCount)
                        OpenGroupAPI.updateProfileIfNeeded(for: channel, on: server, from: openGroupInfo)
                        return openGroupInfo
                    }
                }
            }.handlingInvalidAuthTokenIfNeeded(for: server)
        }
    }

    public static func updateProfileIfNeeded(for channel: UInt64, on server: String, from info: OpenGroupInfo) {
        let openGroupID = "\(server).\(channel)"
        Storage.write { transaction in
            // Update user count
            Storage.shared.setUserCount(to: info.memberCount, forOpenGroupWithID: openGroupID, using: transaction)
            let thread = TSGroupThread.getOrCreateThread(withGroupId: openGroupID.data(using: .utf8)!, groupType: .openGroup, transaction: transaction)
            // Update display name if needed
            let model = thread.groupModel
            if model.groupName != info.displayName {
                let newGroupModel = TSGroupModel(title: info.displayName, memberIds: model.groupMemberIds, image: model.groupImage, groupId: model.groupId, groupType: model.groupType, adminIds: model.groupAdminIds)
                thread.groupModel = newGroupModel
                thread.save(with: transaction)
            }
            // Download and update profile picture if needed
            let oldProfilePictureURL = Storage.shared.getProfilePictureURL(forOpenGroupWithID: openGroupID)
            if oldProfilePictureURL != info.profilePictureURL || model.groupImage == nil {
                Storage.shared.setProfilePictureURL(to: info.profilePictureURL, forOpenGroupWithID: openGroupID, using: transaction)
                if let profilePictureURL = info.profilePictureURL {
                    var sanitizedServerURL = server
                    while sanitizedServerURL.hasSuffix("/") { sanitizedServerURL.removeLast() }
                    var sanitizedProfilePictureURL = profilePictureURL
                    while sanitizedProfilePictureURL.hasPrefix("/") { sanitizedProfilePictureURL.removeFirst() }
                    let url = "\(sanitizedServerURL)/\(sanitizedProfilePictureURL)"
                    FileServerAPI.downloadAttachment(from: url).map2 { data in
                        let attachmentStream = TSAttachmentStream(contentType: OWSMimeTypeImageJpeg, byteCount: UInt32(data.count), sourceFilename: nil, caption: nil, albumMessageId: nil)
                        try attachmentStream.write(data)
                        thread.updateAvatar(with: attachmentStream)
                    }
                }
            }
        }
    }

    public static func join(_ channel: UInt64, on server: String) -> Promise<Void> {
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
            getOpenGroupServerPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { serverPublicKey in
                getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Void> in
                    let url = URL(string: "\(server)/channels/\(channel)/subscribe")!
                    let request = TSRequest(url: url, method: "POST", parameters: [:])
                    request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                    return OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey).done(on: DispatchQueue.global(qos: .default)) { _ -> Void in
                        SNLog("Joined channel with ID: \(channel) on server: \(server).")
                    }
                }
            }.handlingInvalidAuthTokenIfNeeded(for: server)
        }
    }

    public static func leave(_ channel: UInt64, on server: String) -> Promise<Void> {
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .default)) {
            getOpenGroupServerPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { serverPublicKey in
                getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Void> in
                    let url = URL(string: "\(server)/channels/\(channel)/subscribe")!
                    let request = TSRequest(url: url, method: "DELETE", parameters: [:])
                    request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                    return OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey).done(on: DispatchQueue.global(qos: .default)) { _ -> Void in
                        SNLog("Left channel with ID: \(channel) on server: \(server).")
                    }
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
        return getOpenGroupServerPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { serverPublicKey in
            OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey).map(on: DispatchQueue.global(qos: .default)) { _ in }
        }
    }

    // MARK: Moderators
    public static func getModerators(for channel: UInt64, on server: String) -> Promise<Set<String>> {
        return getOpenGroupServerPublicKey(for: server).then(on: DispatchQueue.global(qos: .default)) { serverPublicKey in
            getAuthToken(for: server).then(on: DispatchQueue.global(qos: .default)) { token -> Promise<Set<String>> in
                let url = URL(string: "\(server)/loki/v1/channel/\(channel)/get_moderators")!
                let request = TSRequest(url: url)
                request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
                return OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey).map(on: DispatchQueue.global(qos: .default)) { json in
                    guard let moderators = json["moderators"] as? [String] else {
                        SNLog("Couldn't parse moderators for open group channel with ID: \(channel) on server: \(server) from: \(json).")
                        throw Error.parsingFailed
                    }
                    let moderatorsAsSet = Set(moderators);
                    if self.moderators.keys.contains(server) {
                        self.moderators[server]![channel] = moderatorsAsSet
                    } else {
                        self.moderators[server] = [ channel : moderatorsAsSet ]
                    }
                    return moderatorsAsSet
                }
            }
        }.handlingInvalidAuthTokenIfNeeded(for: server)
    }

    @objc(isUserModerator:forChannel:onServer:)
    public static func isUserModerator(_ hexEncodedPublicString: String, for channel: UInt64, on server: String) -> Bool {
        return moderators[server]?[channel]?.contains(hexEncodedPublicString) ?? false
    }
}

// MARK: Error Handling
internal extension Promise {

    func handlingInvalidAuthTokenIfNeeded(for server: String) -> Promise<T> {
        return recover(on: DispatchQueue.global(qos: .userInitiated)) { error -> Promise<T> in
            if case OnionRequestAPI.Error.httpRequestFailedAtDestination(let statusCode, _) = error, statusCode == 401 || statusCode == 403 {
                SNLog("Auth token for: \(server) expired; dropping it.")
                let storage = SNMessagingKitConfiguration.shared.storage
                storage.with { transaction in
                    storage.removeAuthToken(for: server, using: transaction)
                }
            }
            throw error
        }
    }
}
