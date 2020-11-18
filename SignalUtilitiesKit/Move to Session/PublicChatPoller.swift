import PromiseKit

@objc(LKPublicChatPoller)
public final class PublicChatPoller : NSObject {
    private let publicChat: OpenGroup
    private var pollForNewMessagesTimer: Timer? = nil
    private var pollForDeletedMessagesTimer: Timer? = nil
    private var pollForModeratorsTimer: Timer? = nil
    private var pollForDisplayNamesTimer: Timer? = nil
    private var hasStarted = false
    private var isPolling = false
    
    // MARK: Settings
    private let pollForNewMessagesInterval: TimeInterval = 4
    private let pollForDeletedMessagesInterval: TimeInterval = 60
    private let pollForModeratorsInterval: TimeInterval = 10 * 60
    private let pollForDisplayNamesInterval: TimeInterval = 60
    
    // MARK: Lifecycle
    @objc(initForPublicChat:)
    public init(for publicChat: OpenGroup) {
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
        guard !self.isPolling else { return Promise.value(()) }
        self.isPolling = true
        let publicChat = self.publicChat
        let userPublicKey = getUserHexEncodedPublicKey()
        return OpenGroupAPI.getMessages(for: publicChat.channel, on: publicChat.server).done(on: DispatchQueue.global(qos: .default)) { messages in
            self.isPolling = false
            let storage = OWSPrimaryStorage.shared()
            // Sorting the messages by timestamp before importing them fixes an issue where messages that quote older messages can't find those older messages
            messages.sorted { $0.serverTimestamp < $1.serverTimestamp }.forEach { message in
                let senderPublicKey = message.senderPublicKey
                var wasSentByCurrentUser = (senderPublicKey == getUserHexEncodedPublicKey())
                func generateDisplayName(from rawDisplayName: String) -> String {
                    let endIndex = senderPublicKey.endIndex
                    let cutoffIndex = senderPublicKey.index(endIndex, offsetBy: -8)
                    return "\(rawDisplayName) (...\(senderPublicKey[cutoffIndex..<endIndex]))"
                }
                let senderDisplayName = UserDisplayNameUtilities.getPublicChatDisplayName(for: senderPublicKey, in: publicChat.channel, on: publicChat.server) ?? generateDisplayName(from: NSLocalizedString("Anonymous", comment: ""))
                let id = LKGroupUtilities.getEncodedOpenGroupIDAsData(publicChat.id)
                let groupContext = SNProtoGroupContext.builder(id: id, type: .deliver)
                groupContext.setName(publicChat.displayName)
                let dataMessage = SNProtoDataMessage.builder()
                let attachments: [SNProtoAttachmentPointer] = message.attachments.compactMap { attachment in
                    guard attachment.kind == .attachment else { return nil }
                    let result = SNProtoAttachmentPointer.builder(id: attachment.serverID)
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
                    let signalLinkPreview = SNProtoDataMessagePreview.builder(url: linkPreview.linkPreviewURL!)
                    signalLinkPreview.setTitle(linkPreview.linkPreviewTitle!)
                    let attachment = SNProtoAttachmentPointer.builder(id: linkPreview.serverID)
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
                let profile = SNProtoDataMessageLokiProfile.builder()
                profile.setDisplayName(message.displayName)
                if let profilePicture = message.profilePicture {
                    profile.setProfilePicture(profilePicture.url)
                    dataMessage.setProfileKey(profilePicture.profileKey)
                }
                dataMessage.setProfile(try! profile.build())
                dataMessage.setTimestamp(message.timestamp)
                dataMessage.setGroup(try! groupContext.build())
                if let quote = message.quote {
                    let signalQuote = SNProtoDataMessageQuote.builder(id: quote.quotedMessageTimestamp, author: quote.quoteePublicKey)
                    signalQuote.setText(quote.quotedMessageBody)
                    dataMessage.setQuote(try! signalQuote.build())
                }
                let body = (message.body == message.timestamp.description) ? "" : message.body // Workaround for the fact that the back-end doesn't accept messages without a body
                dataMessage.setBody(body)
                if let messageServerID = message.serverID {
                    let publicChatInfo = SNProtoPublicChatInfo.builder()
                    publicChatInfo.setServerID(messageServerID)
                    dataMessage.setPublicChatInfo(try! publicChatInfo.build())
                }
                let content = SNProtoContent.builder()
                if !wasSentByCurrentUser {
                    content.setDataMessage(try! dataMessage.build())
                } else {
                    let syncMessageSentBuilder = SNProtoSyncMessageSent.builder()
                    syncMessageSentBuilder.setMessage(try! dataMessage.build())
                    syncMessageSentBuilder.setDestination(userPublicKey)
                    syncMessageSentBuilder.setTimestamp(message.timestamp)
                    let syncMessageSent = try! syncMessageSentBuilder.build()
                    let syncMessageBuilder = SNProtoSyncMessage.builder()
                    syncMessageBuilder.setSent(syncMessageSent)
                    content.setSyncMessage(try! syncMessageBuilder.build())
                }
                let envelope = SNProtoEnvelope.builder(type: .ciphertext, timestamp: message.timestamp)
                envelope.setSource(senderPublicKey)
                envelope.setSourceDevice(1)
                envelope.setContent(try! content.build().serializedData())
                envelope.setServerTimestamp(message.serverTimestamp)
                Storage.writeSync { transaction in
                    transaction.setObject(senderDisplayName, forKey: senderPublicKey, inCollection: publicChat.id)
                    let messageServerID = message.serverID
                    let job = MessageReceiveJob(data: try! envelope.buildSerializedData(), messageServerID: messageServerID)
                    Storage.write { transaction in
                        SessionMessagingKit.JobQueue.shared.add(job, using: transaction)
                    }
                }
            }
        }
    }
    
    private func pollForDeletedMessages() {
        let publicChat = self.publicChat
        let _ = OpenGroupAPI.getDeletedMessageServerIDs(for: publicChat.channel, on: publicChat.server).done(on: DispatchQueue.global(qos: .default)) { deletedMessageServerIDs in
            Storage.writeSync { transaction in
                let deletedMessageIDs = deletedMessageServerIDs.compactMap { OWSPrimaryStorage.shared().getIDForMessage(withServerID: UInt($0), in: transaction) }
                deletedMessageIDs.forEach { messageID in
                    TSMessage.fetch(uniqueId: messageID)?.remove(with: transaction)
                }
            }
        }
    }
    
    private func pollForModerators() {
        let _ = OpenGroupAPI.getModerators(for: publicChat.channel, on: publicChat.server)
    }
    
    private func pollForDisplayNames() {
        let _ = OpenGroupAPI.getDisplayNames(for: publicChat.channel, on: publicChat.server)
    }
}
