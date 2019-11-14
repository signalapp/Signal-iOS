
@objc(LKPublicChatPoller)
public final class LokiPublicChatPoller : NSObject {
    private let publicChat: LokiPublicChat
    private var pollForNewMessagesTimer: Timer? = nil
    private var pollForDeletedMessagesTimer: Timer? = nil
    private var pollForModeratorsTimer: Timer? = nil
    private var hasStarted = false
    private let userHexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
    
    // MARK: Settings
    private let pollForNewMessagesInterval: TimeInterval = 4
    private let pollForDeletedMessagesInterval: TimeInterval = 20
    private let pollForModeratorsInterval: TimeInterval = 10 * 60
    
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
        // Perform initial updates
        pollForNewMessages()
        pollForDeletedMessages()
        pollForModerators()
        hasStarted = true
    }
    
    @objc public func stop() {
        pollForNewMessagesTimer?.invalidate()
        pollForDeletedMessagesTimer?.invalidate()
        pollForModeratorsTimer?.invalidate()
        hasStarted = false
    }
    
    // MARK: Polling
    private func pollForNewMessages() {
        // Prepare
        let publicChat = self.publicChat
        let userHexEncodedPublicKey = self.userHexEncodedPublicKey
        // Processing logic for incoming messages
        func processIncomingMessage(_ message: LokiPublicChatMessage) {
            let storage = OWSPrimaryStorage.shared()
            var senderHexEncodedPublicKey = ""
            storage.dbReadConnection.read { transaction in
                senderHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: message.hexEncodedPublicKey, in: transaction) ?? message.hexEncodedPublicKey
            }
            let endIndex = senderHexEncodedPublicKey.endIndex
            let cutoffIndex = senderHexEncodedPublicKey.index(endIndex, offsetBy: -8)
            // FIXME: The display name code below relies on LokiStorageAPI.getDeviceLinks(...) getting and storing display names, which it shouldn't be doing.
            let rawDisplayName = DisplayNameUtilities.getPublicChatDisplayName(for: senderHexEncodedPublicKey, in: publicChat.channel, on: publicChat.server) ?? message.displayName
            let senderDisplayName = "\(rawDisplayName) (...\(senderHexEncodedPublicKey[cutoffIndex..<endIndex]))"
            let id = publicChat.idAsData
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
            content.setDataMessage(try! dataMessage.build())
            let envelope = SSKProtoEnvelope.builder(type: .ciphertext, timestamp: message.timestamp)
            envelope.setSource(senderHexEncodedPublicKey)
            envelope.setSourceDevice(OWSDevicePrimaryDeviceId)
            envelope.setContent(try! content.build().serializedData())
            storage.dbReadWriteConnection.readWrite { transaction in
                transaction.setObject(senderDisplayName, forKey: senderHexEncodedPublicKey, inCollection: publicChat.id)
                SSKEnvironment.shared.messageManager.throws_processEnvelope(try! envelope.build(), plaintextData: try! content.build().serializedData(), wasReceivedByUD: false, transaction: transaction)
            }
        }
        // Processing logic for outgoing messages
        func processOutgoingMessage(_ message: LokiPublicChatMessage) {
            guard let messageServerID = message.serverID else { return }
            let storage = OWSPrimaryStorage.shared()
            var isDuplicate = false
            storage.dbReadConnection.read { transaction in
                let id = storage.getIDForMessage(withServerID: UInt(messageServerID), in: transaction)
                isDuplicate = id != nil
            }
            guard !isDuplicate else { return }
            let groupID = publicChat.idAsData
            let thread = TSGroupThread.getOrCreateThread(withGroupId: groupID)
            let signalQuote: TSQuotedMessage?
            if let quote = message.quote {
                signalQuote = TSQuotedMessage(timestamp: quote.quotedMessageTimestamp, authorId: quote.quoteeHexEncodedPublicKey, body: quote.quotedMessageBody, quotedAttachmentsForSending: [])
            } else {
                signalQuote = nil
            }
            var attachmentIDs: [String] = []
            // TODO: Restore attachments
            let signalLinkPreview: OWSLinkPreview?
            if let linkPreview = message.attachments.first(where: { $0.kind == .linkPreview }) {
                let attachment = TSAttachmentPointer(serverId: linkPreview.serverID, encryptionKey: nil, byteCount: UInt32(linkPreview.size), contentType: linkPreview.contentType, sourceFilename: linkPreview.fileName, caption: linkPreview.caption, albumMessageId: nil)
                attachment.save()
                signalLinkPreview = OWSLinkPreview(urlString: linkPreview.linkPreviewURL!, title: linkPreview.linkPreviewTitle!, imageAttachmentId: attachment.uniqueId!, isDirectAttachment: false)
            } else {
                signalLinkPreview = nil
            }
            let body = (message.body == message.timestamp.description) ? "" : message.body // Workaround for the fact that the back-end doesn't accept messages without a body
            let message = TSOutgoingMessage(outgoingMessageWithTimestamp: message.timestamp, in: thread, messageBody: body, attachmentIds: NSMutableArray(array: attachmentIDs), expiresInSeconds: 0,
                expireStartedAt: 0, isVoiceMessage: false, groupMetaMessage: .deliver, quotedMessage: signalQuote, contactShare: nil, linkPreview: signalLinkPreview)
            storage.dbReadWriteConnection.readWrite { transaction in
                message.update(withSentRecipient: publicChat.server, wasSentByUD: false, transaction: transaction)
                message.saveGroupChatServerID(messageServerID, in: transaction)
                guard let messageID = message.uniqueId else { return print("[Loki] Failed to save public chat message.") }
                storage.setIDForMessageWithServerID(UInt(messageServerID), to: messageID, in: transaction)
            }
            if let linkPreviewURL = OWSLinkPreview.previewUrl(forMessageBodyText: message.body, selectedRange: nil) {
                message.generateLinkPreviewIfNeeded(fromURL: linkPreviewURL)
            }
        }
        // Poll
        let _ = LokiPublicChatAPI.getMessages(for: publicChat.channel, on: publicChat.server).done(on: DispatchQueue.global()) { messages in
            func proceed() {
                messages.forEach { message in
                    var wasSentByCurrentUser = false
                    OWSPrimaryStorage.shared().dbReadConnection.read { transaction in
                        wasSentByCurrentUser = LokiDatabaseUtilities.isUserLinkedDevice(message.hexEncodedPublicKey, transaction: transaction)
                    }
                    if !wasSentByCurrentUser {
                        processIncomingMessage(message)
                    } else {
                        processOutgoingMessage(message)
                    }
                }
            }
            let uniqueHexEncodedPublicKeys = Set(messages.map { $0.hexEncodedPublicKey })
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
                    LokiStorageAPI.getDeviceLinks(associatedWith: hexEncodedPublicKeysToUpdate).done(on: DispatchQueue.global()) { _ in
                        proceed()
                        hexEncodedPublicKeysToUpdate.forEach {
                            LokiAPI.lastDeviceLinkUpdate[$0] = Date()
                        }
                    }.catch(on: DispatchQueue.global()) { error in
                        if case LokiDotNetAPI.Error.parsingFailed = error {
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
}
