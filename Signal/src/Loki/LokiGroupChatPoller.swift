
@objc(LKGroupChatPoller)
public final class LokiGroupChatPoller : NSObject {
    private let group: LokiGroupChat
    private var pollForNewMessagesTimer: Timer? = nil
    private var pollForDeletedMessagesTimer: Timer? = nil
    private var pollForModerationPermissionTimer: Timer? = nil
    private var hasStarted = false
    private let userHexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
    
    // MARK: Settings
    private let pollForNewMessagesInterval: TimeInterval = 4
    private let pollForDeletedMessagesInterval: TimeInterval = 20
    private let pollForModerationPermissionInterval: TimeInterval = 10 * 60
    
    // MARK: Lifecycle
    @objc(initForGroup:)
    public init(for group: LokiGroupChat) {
        self.group = group
        super.init()
    }
    
    @objc public func startIfNeeded() {
        if hasStarted { return }
        pollForNewMessagesTimer = Timer.scheduledTimer(withTimeInterval: pollForNewMessagesInterval, repeats: true) { [weak self] _ in self?.pollForNewMessages() }
        pollForDeletedMessagesTimer = Timer.scheduledTimer(withTimeInterval: pollForDeletedMessagesInterval, repeats: true) { [weak self] _ in self?.pollForDeletedMessages() }
        pollForModerationPermissionTimer = Timer.scheduledTimer(withTimeInterval: pollForModerationPermissionInterval, repeats: true) { [weak self] _ in self?.pollForModerationPermission() }
        // Perform initial updates
        pollForNewMessages()
        pollForDeletedMessages()
        pollForModerationPermission()
        hasStarted = true
    }
    
    @objc public func stop() {
        pollForNewMessagesTimer?.invalidate()
        pollForDeletedMessagesTimer?.invalidate()
        pollForModerationPermissionTimer?.invalidate()
        hasStarted = false
    }
    
    // MARK: Polling
    private func pollForNewMessages() {
        // Prepare
        let group = self.group
        let userHexEncodedPublicKey = self.userHexEncodedPublicKey
        // Processing logic for incoming messages
        func processIncomingMessage(_ message: LokiGroupMessage) {
            let senderHexEncodedPublicKey = message.hexEncodedPublicKey
            let endIndex = senderHexEncodedPublicKey.endIndex
            let cutoffIndex = senderHexEncodedPublicKey.index(endIndex, offsetBy: -8)
            let senderDisplayName = "\(message.displayName) (...\(senderHexEncodedPublicKey[cutoffIndex..<endIndex]))"
            let id = group.id.data(using: String.Encoding.utf8)!
            let x1 = SSKProtoGroupContext.builder(id: id, type: .deliver)
            x1.setName(group.displayName)
            let x2 = SSKProtoDataMessage.builder()
            x2.setTimestamp(message.timestamp)
            x2.setGroup(try! x1.build())
            if let quote = message.quote {
                let x5 = SSKProtoDataMessageQuote.builder(id: quote.quotedMessageTimestamp, author: quote.quoteeHexEncodedPublicKey)
                x5.setText(quote.quotedMessageBody)
                x2.setQuote(try! x5.build())
            }
            x2.setBody(message.body)
            if let messageServerID = message.serverID {
                let publicChatInfo = SSKProtoPublicChatInfo.builder()
                publicChatInfo.setServerID(messageServerID)
                x2.setPublicChatInfo(try! publicChatInfo.build())
            }
            let x3 = SSKProtoContent.builder()
            x3.setDataMessage(try! x2.build())
            let x4 = SSKProtoEnvelope.builder(type: .ciphertext, timestamp: message.timestamp)
            x4.setSource(senderHexEncodedPublicKey)
            x4.setSourceDevice(OWSDevicePrimaryDeviceId)
            x4.setContent(try! x3.build().serializedData())
            let storage = OWSPrimaryStorage.shared()
            storage.dbReadWriteConnection.readWrite { transaction in
                transaction.setObject(senderDisplayName, forKey: senderHexEncodedPublicKey, inCollection: group.id)
                SSKEnvironment.shared.messageManager.throws_processEnvelope(try! x4.build(), plaintextData: try! x3.build().serializedData(), wasReceivedByUD: false, transaction: transaction)
            }
        }
        // Processing logic for outgoing messages
        func processOutgoingMessage(_ message: LokiGroupMessage) {
            guard let messageServerID = message.serverID else { return }
            let storage = OWSPrimaryStorage.shared()
            var isDuplicate = false
            storage.dbReadConnection.read { transaction in
                let id = storage.getIDForMessage(withServerID: UInt(messageServerID), in: transaction)
                isDuplicate = id != nil
            }
            guard !isDuplicate else { return }
            guard let groupID = group.id.data(using: .utf8) else { return }
            let thread = TSGroupThread.getOrCreateThread(withGroupId: groupID)
            let message = TSOutgoingMessage(outgoingMessageWithTimestamp: message.timestamp, in: thread, messageBody: message.body, attachmentIds: [], expiresInSeconds: 0,
                expireStartedAt: 0, isVoiceMessage: false, groupMetaMessage: .deliver, quotedMessage: nil, contactShare: nil, linkPreview: nil)
            storage.dbReadWriteConnection.readWrite { transaction in
                message.update(withSentRecipient: group.server, wasSentByUD: false, transaction: transaction)
                message.saveGroupChatMessageID(messageServerID, in: transaction)
                guard let messageID = message.uniqueId else { return print("[Loki] Failed to save group message.") }
                storage.setIDForMessageWithServerID(UInt(messageServerID), to: messageID, in: transaction)
            }
            if let url = OWSLinkPreview.previewUrl(forMessageBodyText: message.body, selectedRange: nil) {
                let _ = OWSLinkPreview.tryToBuildPreviewInfo(previewUrl: url).done { linkPreviewDraft in
                    OWSPrimaryStorage.shared().dbReadWriteConnection.readWrite { transaction in
                        guard let linkPreview = try? OWSLinkPreview.buildValidatedLinkPreview(fromInfo: linkPreviewDraft, transaction: transaction) else { return }
                        message.linkPreview = linkPreview
                        message.save(with: transaction)
                    }
                }
            }
        }
        // Poll
        let _ = LokiGroupChatAPI.getMessages(for: group.serverID, on: group.server).done(on: .main) { messages in
            messages.reversed().forEach { message in
                if message.hexEncodedPublicKey != userHexEncodedPublicKey {
                    processIncomingMessage(message)
                } else {
                    processOutgoingMessage(message)
                }
            }
        }
    }
    
    private func pollForDeletedMessages() {
        let group = self.group
        let _ = LokiGroupChatAPI.getDeletedMessageServerIDs(for: group.serverID, on: group.server).done { deletedMessageServerIDs in
            let storage = OWSPrimaryStorage.shared()
            storage.dbReadWriteConnection.readWrite { transaction in
                let deletedMessageIDs = deletedMessageServerIDs.compactMap { storage.getIDForMessage(withServerID: UInt($0), in: transaction) }
                deletedMessageIDs.forEach { messageID in
                    TSMessage.fetch(uniqueId: messageID)?.remove(with: transaction)
                }
            }
        }
    }
    
    private func pollForModerationPermission() {
        let group = self.group
        let _ = LokiGroupChatAPI.userHasModerationPermission(for: group.serverID, on: group.server).done { isModerator in
            let storage = OWSPrimaryStorage.shared()
            storage.dbReadWriteConnection.readWrite { transaction in
                storage.setIsModerator(isModerator, for: UInt(group.serverID), on: group.server, in: transaction)
            }
        }
    }
}
