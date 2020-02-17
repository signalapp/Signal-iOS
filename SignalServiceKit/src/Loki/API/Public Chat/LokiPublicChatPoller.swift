import PromiseKit

@objc(LKPublicChatPoller)
public final class LokiPublicChatPoller : NSObject {
    private let publicChat: LokiPublicChat
    private var pollForNewMessagesTimer: Timer? = nil
    private var pollForDeletedMessagesTimer: Timer? = nil
    private var pollForModeratorsTimer: Timer? = nil
    private var pollForDisplayNamesTimer: Timer? = nil
    private var hasStarted = false
    private let userHexEncodedPublicKey = getUserHexEncodedPublicKey()
    
    // MARK: Settings
    private let pollForNewMessagesInterval: TimeInterval = 4
    private let pollForDeletedMessagesInterval: TimeInterval = 20
    private let pollForModeratorsInterval: TimeInterval = 10 * 60
    private let pollForDisplayNamesInterval: TimeInterval = 60
    
    // MARK: Lifecycle
    @objc(initForPublicChat:)
    public init(for publicChat: LokiPublicChat) {
        self.publicChat = publicChat
        super.init()
    }
    
    @objc public func startIfNeeded() {
        if hasStarted { return }
        pollForNewMessagesTimer = Timer.scheduledTimer(withTimeInterval: pollForNewMessagesInterval, repeats: true) { [weak self] _ in self?.pollForNewMessages() }
        pollForDeletedMessagesTimer = Timer.scheduledTimer(withTimeInterval: pollForDeletedMessagesInterval, repeats: true) { [weak self] _ in self?.pollForDeletedMessages() }
        pollForModeratorsTimer = Timer.scheduledTimer(withTimeInterval: pollForModeratorsInterval, repeats: true) { [weak self] _ in self?.pollForModerators() }
        pollForDisplayNamesTimer = Timer.scheduledTimer(withTimeInterval: pollForDisplayNamesInterval, repeats: true) { [weak self] _ in self?.pollForDisplayNames() }
        // Perform initial updates
        pollForNewMessages()
        pollForDeletedMessages()
        pollForModerators()
        pollForDisplayNames()
        hasStarted = true
    }
    
    @objc public func stop() {
        pollForNewMessagesTimer?.invalidate()
        pollForDeletedMessagesTimer?.invalidate()
        pollForModeratorsTimer?.invalidate()
        pollForDisplayNamesTimer?.invalidate()
        hasStarted = false
    }
    
    // MARK: Polling
    @objc(pollForNewMessages)
    public func objc_pollForNewMessages() -> AnyPromise {
        AnyPromise.from(pollForNewMessages())
    }
    
    public func pollForNewMessages() -> Promise<Void> {
        let publicChat = self.publicChat
        let userHexEncodedPublicKey = self.userHexEncodedPublicKey
        return LokiPublicChatAPI.getMessages(for: publicChat.channel, on: publicChat.server).done(on: DispatchQueue.global()) { messages in
            let uniqueHexEncodedPublicKeys = Set(messages.map { $0.hexEncodedPublicKey })
            func proceed() {
                let storage = OWSPrimaryStorage.shared()
                var newDisplayNameUpdatees: Set<String> = []
                storage.dbReadConnection.read { transaction in
                    newDisplayNameUpdatees = Set(uniqueHexEncodedPublicKeys.filter { storage.getMasterHexEncodedPublicKey(for: $0, in: transaction) != $0 }.compactMap { storage.getMasterHexEncodedPublicKey(for: $0, in: transaction) })
                }
                if !newDisplayNameUpdatees.isEmpty {
                    let displayNameUpdatees = LokiPublicChatAPI.displayNameUpdatees[publicChat.id] ?? []
                    LokiPublicChatAPI.displayNameUpdatees[publicChat.id] = displayNameUpdatees.union(newDisplayNameUpdatees)
                }
                // Sorting the messages by timestamp before importing them fixes an issue where messages that quote older messages can't find those older messages
                messages.sorted { $0.timestamp < $1.timestamp }.forEach { message in
                    var wasSentByCurrentUser = false
                    OWSPrimaryStorage.shared().dbReadConnection.read { transaction in
                        wasSentByCurrentUser = LokiDatabaseUtilities.isUserLinkedDevice(message.hexEncodedPublicKey, transaction: transaction)
                    }
                    var masterHexEncodedPublicKey: String? = nil
                    storage.dbReadConnection.read { transaction in
                        masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: message.hexEncodedPublicKey, in: transaction)
                    }
                    let senderHexEncodedPublicKey = masterHexEncodedPublicKey ?? message.hexEncodedPublicKey
                    func generateDisplayName(from rawDisplayName: String) -> String {
                        let endIndex = senderHexEncodedPublicKey.endIndex
                        let cutoffIndex = senderHexEncodedPublicKey.index(endIndex, offsetBy: -8)
                        return "\(rawDisplayName) (...\(senderHexEncodedPublicKey[cutoffIndex..<endIndex]))"
                    }
                    var senderDisplayName = ""
                    if let masterHexEncodedPublicKey = masterHexEncodedPublicKey {
                        senderDisplayName = UserDisplayNameUtilities.getPublicChatDisplayName(for: senderHexEncodedPublicKey, in: publicChat.channel, on: publicChat.server) ?? generateDisplayName(from: NSLocalizedString("Anonymous", comment: ""))
                    } else {
                        senderDisplayName = generateDisplayName(from: message.displayName)
                    }
                    let id = LKGroupUtilities.getEncodedOpenGroupIDAsData(publicChat.id)
                    let groupContext = SSKProtoGroupContext.builder(id: id, type: .deliver)
                    groupContext.setName(publicChat.displayName)
                    let dataMessage = SSKProtoDataMessage.builder()
                    let attachments: [SSKProtoAttachmentPointer] = message.attachments.compactMap { attachment in
                        guard attachment.kind == .attachment else { return nil }
                        let result = SSKProtoAttachmentPointer.builder(id: attachment.serverID)
                        result.setContentType(attachment.contentType)
                        result.setSize(UInt32(attachment.size))
                        result.setFileName(attachment.fileName)
                        result.setFlags(UInt32(attachment.flags))
                        result.setWidth(UInt32(attachment.width))
                        result.setHeight(UInt32(attachment.height))
                        if let caption = attachment.caption {
                            result.setCaption(caption)
                        }
                        result.setUrl(attachment.url)
                        return try! result.build()
                    }
                    dataMessage.setAttachments(attachments)
                    if let linkPreview = message.attachments.first(where: { $0.kind == .linkPreview }) {
                        let signalLinkPreview = SSKProtoDataMessagePreview.builder(url: linkPreview.linkPreviewURL!)
                        signalLinkPreview.setTitle(linkPreview.linkPreviewTitle!)
                        let attachment = SSKProtoAttachmentPointer.builder(id: linkPreview.serverID)
                        attachment.setContentType(linkPreview.contentType)
                        attachment.setSize(UInt32(linkPreview.size))
                        attachment.setFileName(linkPreview.fileName)
                        attachment.setFlags(UInt32(linkPreview.flags))
                        attachment.setWidth(UInt32(linkPreview.width))
                        attachment.setHeight(UInt32(linkPreview.height))
                        if let caption = linkPreview.caption {
                            attachment.setCaption(caption)
                        }
                        attachment.setUrl(linkPreview.url)
                        signalLinkPreview.setImage(try! attachment.build())
                        dataMessage.setPreview([ try! signalLinkPreview.build() ])
                    }
                    let profile = SSKProtoDataMessageLokiProfile.builder()
                    profile.setDisplayName(message.displayName)
                    if let profilePicture = message.profilePicture {
                        profile.setProfilePicture(profilePicture.url)
                        dataMessage.setProfileKey(profilePicture.profileKey)
                    }
                    dataMessage.setProfile(try! profile.build())
                    dataMessage.setTimestamp(message.timestamp)
                    dataMessage.setGroup(try! groupContext.build())
                    if let quote = message.quote {
                        let signalQuote = SSKProtoDataMessageQuote.builder(id: quote.quotedMessageTimestamp, author: quote.quoteeHexEncodedPublicKey)
                        signalQuote.setText(quote.quotedMessageBody)
                        dataMessage.setQuote(try! signalQuote.build())
                    }
                    let body = (message.body == message.timestamp.description) ? "" : message.body // Workaround for the fact that the back-end doesn't accept messages without a body
                    dataMessage.setBody(body)
                    if let messageServerID = message.serverID {
                        let publicChatInfo = SSKProtoPublicChatInfo.builder()
                        publicChatInfo.setServerID(messageServerID)
                        dataMessage.setPublicChatInfo(try! publicChatInfo.build())
                    }
                    let content = SSKProtoContent.builder()
                    if !wasSentByCurrentUser {
                        content.setDataMessage(try! dataMessage.build())
                    } else {
                        let syncMessageSentBuilder = SSKProtoSyncMessageSent.builder()
                        syncMessageSentBuilder.setMessage(try! dataMessage.build())
                        syncMessageSentBuilder.setDestination(userHexEncodedPublicKey)
                        syncMessageSentBuilder.setTimestamp(message.timestamp)
                        let syncMessageSent = try! syncMessageSentBuilder.build()
                        let syncMessageBuilder = SSKProtoSyncMessage.builder()
                        syncMessageBuilder.setSent(syncMessageSent)
                        content.setSyncMessage(try! syncMessageBuilder.build())
                    }
                    let envelope = SSKProtoEnvelope.builder(type: .ciphertext, timestamp: message.timestamp)
                    envelope.setSource(senderHexEncodedPublicKey)
                    envelope.setSourceDevice(OWSDevicePrimaryDeviceId)
                    envelope.setContent(try! content.build().serializedData())
                    storage.dbReadWriteConnection.readWrite { transaction in
                        transaction.setObject(senderDisplayName, forKey: senderHexEncodedPublicKey, inCollection: publicChat.id)
                        let messageServerID = message.serverID
                        SSKEnvironment.shared.messageManager.throws_processEnvelope(try! envelope.build(), plaintextData: try! content.build().serializedData(), wasReceivedByUD: false, transaction: transaction, serverID: messageServerID ?? 0)
                        // If we got a message from our master device then we should use its profile picture
                        if let profilePicture = message.profilePicture, masterHexEncodedPublicKey == message.hexEncodedPublicKey {
                            if (message.displayName.count > 0) {
                                SSKEnvironment.shared.profileManager.updateProfileForContact(withID: masterHexEncodedPublicKey!, displayName: message.displayName, with: transaction)
                            }
                            SSKEnvironment.shared.profileManager.updateService(withProfileName: message.displayName, avatarUrl: profilePicture.url)
                            SSKEnvironment.shared.profileManager.setProfileKeyData(profilePicture.profileKey, forRecipientId: masterHexEncodedPublicKey!, avatarURL: profilePicture.url)
                        }
                    }
                }
            }
            let hexEncodedPublicKeysToUpdate = uniqueHexEncodedPublicKeys.filter { hexEncodedPublicKey in
                let timeSinceLastUpdate: TimeInterval
                if let lastDeviceLinkUpdate = LokiAPI.lastDeviceLinkUpdate[hexEncodedPublicKey] {
                    timeSinceLastUpdate = Date().timeIntervalSince(lastDeviceLinkUpdate)
                } else {
                    timeSinceLastUpdate = .infinity
                }
                return timeSinceLastUpdate > LokiAPI.deviceLinkUpdateInterval
            }
            if !hexEncodedPublicKeysToUpdate.isEmpty {
                let storage = OWSPrimaryStorage.shared()
                storage.dbReadConnection.read { transaction in
                    LokiFileServerAPI.getDeviceLinks(associatedWith: hexEncodedPublicKeysToUpdate).done(on: DispatchQueue.global()) { _ in
                        proceed()
                        hexEncodedPublicKeysToUpdate.forEach {
                            LokiAPI.lastDeviceLinkUpdate[$0] = Date()
                        }
                    }.catch(on: DispatchQueue.global()) { error in
                        if (error as? LokiDotNetAPI.LokiDotNetAPIError) == LokiDotNetAPI.LokiDotNetAPIError.parsingFailed {
                            // Don't immediately re-fetch in case of failure due to a parsing error
                            hexEncodedPublicKeysToUpdate.forEach {
                                LokiAPI.lastDeviceLinkUpdate[$0] = Date()
                            }
                        }
                        proceed()
                    }
                }
            } else {
                proceed()
            }
        }
    }
    
    private func pollForDeletedMessages() {
        let publicChat = self.publicChat
        let _ = LokiPublicChatAPI.getDeletedMessageServerIDs(for: publicChat.channel, on: publicChat.server).done(on: DispatchQueue.global()) { deletedMessageServerIDs in
            let storage = OWSPrimaryStorage.shared()
            storage.dbReadWriteConnection.readWrite { transaction in
                let deletedMessageIDs = deletedMessageServerIDs.compactMap { storage.getIDForMessage(withServerID: UInt($0), in: transaction) }
                deletedMessageIDs.forEach { messageID in
                    TSMessage.fetch(uniqueId: messageID)?.remove(with: transaction)
                }
            }
        }
    }
    
    private func pollForModerators() {
        let _ = LokiPublicChatAPI.getModerators(for: publicChat.channel, on: publicChat.server)
    }
    
    private func pollForDisplayNames() {
        let _ = LokiPublicChatAPI.getDisplayNames(for: publicChat.channel, on: publicChat.server)
    }
}
