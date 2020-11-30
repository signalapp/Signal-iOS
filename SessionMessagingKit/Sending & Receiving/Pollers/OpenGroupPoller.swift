import PromiseKit

@objc(LKOpenGroupPoller)
public final class OpenGroupPoller : NSObject {
    private let openGroup: OpenGroup
    private var pollForNewMessagesTimer: Timer? = nil
    private var pollForDeletedMessagesTimer: Timer? = nil
    private var pollForModeratorsTimer: Timer? = nil
    private var hasStarted = false
    private var isPolling = false
    
    // MARK: Settings
    private let pollForNewMessagesInterval: TimeInterval = 4
    private let pollForDeletedMessagesInterval: TimeInterval = 60
    private let pollForModeratorsInterval: TimeInterval = 10 * 60

    // MARK: Lifecycle
    @objc(initForOpenGroup:)
    public init(for openGroup: OpenGroup) {
        self.openGroup = openGroup
        super.init()
    }
    
    @objc public func startIfNeeded() {
        if hasStarted { return }
        DispatchQueue.main.async { [weak self] in // Timers don't do well on background queues
            guard let strongSelf = self else { return }
            strongSelf.pollForNewMessagesTimer = Timer.scheduledTimer(withTimeInterval: strongSelf.pollForNewMessagesInterval, repeats: true) { _ in self?.pollForNewMessages() }
            strongSelf.pollForDeletedMessagesTimer = Timer.scheduledTimer(withTimeInterval: strongSelf.pollForDeletedMessagesInterval, repeats: true) { _ in self?.pollForDeletedMessages() }
            strongSelf.pollForModeratorsTimer = Timer.scheduledTimer(withTimeInterval: strongSelf.pollForModeratorsInterval, repeats: true) { _ in self?.pollForModerators() }
            // Perform initial updates
            strongSelf.pollForNewMessages()
            strongSelf.pollForDeletedMessages()
            strongSelf.pollForModerators()
            strongSelf.hasStarted = true
        }
    }
    
    @objc public func stop() {
        pollForNewMessagesTimer?.invalidate()
        pollForDeletedMessagesTimer?.invalidate()
        pollForModeratorsTimer?.invalidate()
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
        let openGroup = self.openGroup
        let userPublicKey = getUserHexEncodedPublicKey()
        return OpenGroupAPI.getMessages(for: openGroup.channel, on: openGroup.server).done(on: DispatchQueue.global(qos: .default)) { messages in
            self.isPolling = false
            // Sorting the messages by timestamp before importing them fixes an issue where messages that quote older messages can't find those older messages
            messages.sorted { $0.serverTimestamp < $1.serverTimestamp }.forEach { message in
                let senderPublicKey = message.senderPublicKey
                let wasSentByCurrentUser = (senderPublicKey == getUserHexEncodedPublicKey())
                func generateDisplayName(from rawDisplayName: String) -> String {
                    let endIndex = senderPublicKey.endIndex
                    let cutoffIndex = senderPublicKey.index(endIndex, offsetBy: -8)
                    return "\(rawDisplayName) (...\(senderPublicKey[cutoffIndex..<endIndex]))"
                }
                let senderDisplayName = UserDisplayNameUtilities.getPublicChatDisplayName(for: senderPublicKey, in: openGroup.channel, on: openGroup.server)
                    ?? generateDisplayName(from: NSLocalizedString("Anonymous", comment: ""))
                let id = LKGroupUtilities.getEncodedOpenGroupIDAsData(openGroup.id)
                // Main message
                let dataMessageProto = SNProtoDataMessage.builder()
                let body = (message.body == message.timestamp.description) ? "" : message.body // The back-end doesn't accept messages without a body so we use this as a workaround
                dataMessageProto.setBody(body)
                dataMessageProto.setTimestamp(message.timestamp)
                // Attachments
                let attachments: [SNProtoAttachmentPointer] = message.attachments.compactMap { attachment in
                    guard attachment.kind == .attachment else { return nil }
                    let attachmentProto = SNProtoAttachmentPointer.builder(id: attachment.serverID)
                    attachmentProto.setContentType(attachment.contentType)
                    attachmentProto.setSize(UInt32(attachment.size))
                    attachmentProto.setFileName(attachment.fileName)
                    attachmentProto.setFlags(UInt32(attachment.flags))
                    attachmentProto.setWidth(UInt32(attachment.width))
                    attachmentProto.setHeight(UInt32(attachment.height))
                    if let caption = attachment.caption { attachmentProto.setCaption(caption) }
                    attachmentProto.setUrl(attachment.url)
                    return try! attachmentProto.build()
                }
                dataMessageProto.setAttachments(attachments)
                // Link preview
                if let linkPreview = message.attachments.first(where: { $0.kind == .linkPreview }) {
                    let linkPreviewProto = SNProtoDataMessagePreview.builder(url: linkPreview.linkPreviewURL!)
                    linkPreviewProto.setTitle(linkPreview.linkPreviewTitle!)
                    let attachmentProto = SNProtoAttachmentPointer.builder(id: linkPreview.serverID)
                    attachmentProto.setContentType(linkPreview.contentType)
                    attachmentProto.setSize(UInt32(linkPreview.size))
                    attachmentProto.setFileName(linkPreview.fileName)
                    attachmentProto.setFlags(UInt32(linkPreview.flags))
                    attachmentProto.setWidth(UInt32(linkPreview.width))
                    attachmentProto.setHeight(UInt32(linkPreview.height))
                    if let caption = linkPreview.caption { attachmentProto.setCaption(caption) }
                    attachmentProto.setUrl(linkPreview.url)
                    linkPreviewProto.setImage(try! attachmentProto.build())
                    dataMessageProto.setPreview([ try! linkPreviewProto.build() ])
                }
                // Quote
                if let quote = message.quote {
                    let quoteProto = SNProtoDataMessageQuote.builder(id: quote.quotedMessageTimestamp, author: quote.quoteePublicKey)
                    if let quotedMessageBody = quote.quotedMessageBody { quoteProto.setText(quotedMessageBody) }
                    dataMessageProto.setQuote(try! quoteProto.build())
                }
                // Profile
                let profileProto = SNProtoDataMessageLokiProfile.builder()
                profileProto.setDisplayName(message.displayName)
                if let profilePicture = message.profilePicture {
                    profileProto.setProfilePicture(profilePicture.url)
                    dataMessageProto.setProfileKey(profilePicture.profileKey)
                }
                dataMessageProto.setProfile(try! profileProto.build())
                // Open group info
                if let messageServerID = message.serverID {
                    let openGroupProto = SNProtoPublicChatInfo.builder()
                    openGroupProto.setServerID(messageServerID)
                    dataMessageProto.setPublicChatInfo(try! openGroupProto.build())
                }
                // Signal group context
                let groupProto = SNProtoGroupContext.builder(id: id, type: .deliver)
                groupProto.setName(openGroup.displayName)
                dataMessageProto.setGroup(try! groupProto.build())
                // Content
                let content = SNProtoContent.builder()
                if !wasSentByCurrentUser { // Incoming message
                    content.setDataMessage(try! dataMessageProto.build())
                } else { // Outgoing message
                    // FIXME: This needs to be updated as we removed sync message handling
                    let syncMessageSentBuilder = SNProtoSyncMessageSent.builder()
                    syncMessageSentBuilder.setMessage(try! dataMessageProto.build())
                    syncMessageSentBuilder.setDestination(userPublicKey)
                    syncMessageSentBuilder.setTimestamp(message.timestamp)
                    let syncMessageSent = try! syncMessageSentBuilder.build()
                    let syncMessageBuilder = SNProtoSyncMessage.builder()
                    syncMessageBuilder.setSent(syncMessageSent)
                    content.setSyncMessage(try! syncMessageBuilder.build())
                }
                // Envelope
                let envelope = SNProtoEnvelope.builder(type: .unidentifiedSender, timestamp: message.timestamp)
                envelope.setSource(senderPublicKey)
                envelope.setSourceDevice(1)
                envelope.setContent(try! content.build().serializedData())
                envelope.setServerTimestamp(message.serverTimestamp)
                Storage.write { transaction in
                    Storage.shared.setOpenGroupDisplayName(to: senderDisplayName, for: senderPublicKey, inOpenGroupWithID: openGroup.id, using: transaction)
                    let messageServerID = message.serverID
                    let job = MessageReceiveJob(data: try! envelope.buildSerializedData(), openGroupMessageServerID: messageServerID, openGroupID: openGroup.id)
                    SessionMessagingKit.JobQueue.shared.add(job, using: transaction)
                }
            }
        }
    }
    
    private func pollForDeletedMessages() {
        let openGroup = self.openGroup
        let _ = OpenGroupAPI.getDeletedMessageServerIDs(for: openGroup.channel, on: openGroup.server).done(on: DispatchQueue.global(qos: .default)) { deletedMessageServerIDs in
            let deletedMessageIDs = deletedMessageServerIDs.compactMap { Storage.shared.getIDForMessage(withServerID: UInt64($0)) }
            Storage.writeSync { transaction in
                deletedMessageIDs.forEach { messageID in
                    TSMessage.fetch(uniqueId: String(messageID))?.remove(with: transaction)
                }
            }
        }
    }
    
    private func pollForModerators() {
        let _ = OpenGroupAPI.getModerators(for: openGroup.channel, on: openGroup.server)
    }
}
