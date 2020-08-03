import PromiseKit

@objc(LKPublicChatPoller)
public final class PublicChatPoller : NSObject {
    private let publicChat: PublicChat
    private var pollForNewMessagesTimer: Timer? = nil
    private var pollForDeletedMessagesTimer: Timer? = nil
    private var pollForModeratorsTimer: Timer? = nil
    private var pollForDisplayNamesTimer: Timer? = nil
    private var hasStarted = false
    
    // MARK: Settings
    private let pollForNewMessagesInterval: TimeInterval = 4
    private let pollForDeletedMessagesInterval: TimeInterval = 60
    private let pollForModeratorsInterval: TimeInterval = 10 * 60
    private let pollForDisplayNamesInterval: TimeInterval = 60
    
    // MARK: Lifecycle
    @objc(initForPublicChat:)
    public init(for publicChat: PublicChat) {
        self.publicChat = publicChat
        super.init()
    }
    
    @objc public func startIfNeeded() {
        if hasStarted { return }
        DispatchQueue.main.async { [weak self] in // Timers don't do well on background queues
            guard let strongSelf = self else { return }
            strongSelf.pollForNewMessagesTimer = Timer.scheduledTimer(withTimeInterval: strongSelf.pollForNewMessagesInterval, repeats: true) { _ in self?.pollForNewMessages() }
            strongSelf.pollForDeletedMessagesTimer = Timer.scheduledTimer(withTimeInterval: strongSelf.pollForDeletedMessagesInterval, repeats: true) { _ in self?.pollForDeletedMessages() }
            strongSelf.pollForModeratorsTimer = Timer.scheduledTimer(withTimeInterval: strongSelf.pollForModeratorsInterval, repeats: true) { _ in self?.pollForModerators() }
            strongSelf.pollForDisplayNamesTimer = Timer.scheduledTimer(withTimeInterval: strongSelf.pollForDisplayNamesInterval, repeats: true) { _ in self?.pollForDisplayNames() }
            // Perform initial updates
            strongSelf.pollForNewMessages()
            strongSelf.pollForDeletedMessages()
            strongSelf.pollForModerators()
            strongSelf.pollForDisplayNames()
            strongSelf.hasStarted = true
        }
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
        let userPublicKey = getUserHexEncodedPublicKey()
        return PublicChatAPI.getMessages(for: publicChat.channel, on: publicChat.server).done(on: DispatchQueue.global(qos: .default)) { messages in
            let uniquePublicKeys = Set(messages.map { $0.senderPublicKey })
            func proceed() {
                let storage = OWSPrimaryStorage.shared()
                var newDisplayNameUpdatees: Set<String> = []
                /*
                storage.dbReadConnection.read { transaction in
                    newDisplayNameUpdatees = Set(uniquePublicKeys.filter { storage.getMasterHexEncodedPublicKey(for: $0, in: transaction) != $0 }.compactMap { storage.getMasterHexEncodedPublicKey(for: $0, in: transaction) })
                }
                 */
                if !newDisplayNameUpdatees.isEmpty {
                    let displayNameUpdatees = PublicChatAPI.displayNameUpdatees[publicChat.id] ?? []
                    PublicChatAPI.displayNameUpdatees[publicChat.id] = displayNameUpdatees.union(newDisplayNameUpdatees)
                }
                // Sorting the messages by timestamp before importing them fixes an issue where messages that quote older messages can't find those older messages
                messages.sorted { $0.timestamp < $1.timestamp }.forEach { message in
                    var wasSentByCurrentUser = false
                    OWSPrimaryStorage.shared().dbReadConnection.read { transaction in
                        wasSentByCurrentUser = LokiDatabaseUtilities.isUserLinkedDevice(message.senderPublicKey, transaction: transaction)
                    }
                    var masterPublicKey: String? = nil
                    storage.dbReadConnection.read { transaction in
                        masterPublicKey = storage.getMasterHexEncodedPublicKey(for: message.senderPublicKey, in: transaction)
                    }
                    let senderPublicKey = masterPublicKey ?? message.senderPublicKey
                    func generateDisplayName(from rawDisplayName: String) -> String {
                        let endIndex = senderPublicKey.endIndex
                        let cutoffIndex = senderPublicKey.index(endIndex, offsetBy: -8)
                        return "\(rawDisplayName) (...\(senderPublicKey[cutoffIndex..<endIndex]))"
                    }
                    var senderDisplayName = ""
                    if let masterHexEncodedPublicKey = masterPublicKey {
                        senderDisplayName = UserDisplayNameUtilities.getPublicChatDisplayName(for: senderPublicKey, in: publicChat.channel, on: publicChat.server) ?? generateDisplayName(from: NSLocalizedString("Anonymous", comment: ""))
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
                        let signalQuote = SSKProtoDataMessageQuote.builder(id: quote.quotedMessageTimestamp, author: quote.quoteePublicKey)
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
                        // The line below is necessary to make it so that when a user sends a message in an open group and then
                        // deletes and re-joins the open group without closing the app in between, the message isn't ignored.
                        SyncMessagesProtocol.dropFromSyncMessageTimestampCache(message.timestamp, for: senderPublicKey)
                        let syncMessageSentBuilder = SSKProtoSyncMessageSent.builder()
                        syncMessageSentBuilder.setMessage(try! dataMessage.build())
                        syncMessageSentBuilder.setDestination(userPublicKey)
                        syncMessageSentBuilder.setTimestamp(message.timestamp)
                        let syncMessageSent = try! syncMessageSentBuilder.build()
                        let syncMessageBuilder = SSKProtoSyncMessage.builder()
                        syncMessageBuilder.setSent(syncMessageSent)
                        content.setSyncMessage(try! syncMessageBuilder.build())
                    }
                    let envelope = SSKProtoEnvelope.builder(type: .ciphertext, timestamp: message.timestamp)
                    envelope.setSource(senderPublicKey)
                    envelope.setSourceDevice(OWSDevicePrimaryDeviceId)
                    envelope.setContent(try! content.build().serializedData())
                    try! Storage.writeSync { transaction in
                        transaction.setObject(senderDisplayName, forKey: senderPublicKey, inCollection: publicChat.id)
                        let messageServerID = message.serverID
                        SSKEnvironment.shared.messageManager.throws_processEnvelope(try! envelope.build(), plaintextData: try! content.build().serializedData(), wasReceivedByUD: false, transaction: transaction, serverID: messageServerID ?? 0)
                        // If we got a message from our master device then we should use its profile picture
                        if let profilePicture = message.profilePicture, masterPublicKey == message.senderPublicKey {
                            if (message.displayName.count > 0) {
                                SSKEnvironment.shared.profileManager.updateProfileForContact(withID: masterPublicKey!, displayName: message.displayName, with: transaction)
                            }
                            SSKEnvironment.shared.profileManager.updateService(withProfileName: message.displayName, avatarURL: profilePicture.url)
                            SSKEnvironment.shared.profileManager.setProfileKeyData(profilePicture.profileKey, forRecipientId: masterPublicKey!, avatarURL: profilePicture.url)
                        }
                    }
                }
            }
            /*
            let hexEncodedPublicKeysToUpdate = uniquePublicKeys.filter { hexEncodedPublicKey in
                let timeSinceLastUpdate: TimeInterval
                if let lastDeviceLinkUpdate = MultiDeviceProtocol.lastDeviceLinkUpdate[hexEncodedPublicKey] {
                    timeSinceLastUpdate = Date().timeIntervalSince(lastDeviceLinkUpdate)
                } else {
                    timeSinceLastUpdate = .infinity
                }
                return timeSinceLastUpdate > MultiDeviceProtocol.deviceLinkUpdateInterval
            }
            if !hexEncodedPublicKeysToUpdate.isEmpty {
                FileServerAPI.getDeviceLinks(associatedWith: hexEncodedPublicKeysToUpdate).done(on: DispatchQueue.global(qos: .default)) { _ in
                    proceed()
                    hexEncodedPublicKeysToUpdate.forEach {
                        MultiDeviceProtocol.lastDeviceLinkUpdate[$0] = Date() // TODO: Doing this from a global queue seems a bit iffy
                    }
                }.catch(on: DispatchQueue.global(qos: .default)) { error in
                    if (error as? DotNetAPI.DotNetAPIError) == DotNetAPI.DotNetAPIError.parsingFailed {
                        // Don't immediately re-fetch in case of failure due to a parsing error
                        hexEncodedPublicKeysToUpdate.forEach {
                            MultiDeviceProtocol.lastDeviceLinkUpdate[$0] = Date() // TODO: Doing this from a global queue seems a bit iffy
                        }
                    }
                    proceed()
                }
            } else {
             */
                DispatchQueue.global(qos: .default).async {
                    proceed()
                }
            /*
            }
             */
        }
    }
    
    private func pollForDeletedMessages() {
        let publicChat = self.publicChat
        let _ = PublicChatAPI.getDeletedMessageServerIDs(for: publicChat.channel, on: publicChat.server).done(on: DispatchQueue.global(qos: .default)) { deletedMessageServerIDs in
            try! Storage.writeSync { transaction in
                let deletedMessageIDs = deletedMessageServerIDs.compactMap { OWSPrimaryStorage.shared().getIDForMessage(withServerID: UInt($0), in: transaction) }
                deletedMessageIDs.forEach { messageID in
                    TSMessage.fetch(uniqueId: messageID)?.remove(with: transaction)
                }
            }
        }
    }
    
    private func pollForModerators() {
        let _ = PublicChatAPI.getModerators(for: publicChat.channel, on: publicChat.server)
    }
    
    private func pollForDisplayNames() {
        let _ = PublicChatAPI.getDisplayNames(for: publicChat.channel, on: publicChat.server)
    }
}
