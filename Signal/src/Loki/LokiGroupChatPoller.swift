
@objc(LKGroupChatPoller)
public final class LokiGroupChatPoller : NSObject {
    private let group: LokiGroupChat
    private var pollForNewMessagesTimer: Timer? = nil
    private var pollForDeletedMessagesTimer: Timer? = nil
    private var pollForModerationPermissionTimer: Timer? = nil
    private var hasStarted = false
    
    private let pollForNewMessagesInterval: TimeInterval = 4
    private let pollForDeletedMessagesInterval: TimeInterval = 20
    private let pollForModerationPermissionInterval: TimeInterval = 10 * 60
    
    private let storage = OWSPrimaryStorage.shared()
    private let ourHexEncodedPubKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
    
    @objc(initForGroup:)
    public init(for group: LokiGroupChat) {
        self.group = group
        super.init()
    }
    
    @objc public func startIfNeeded() {
        if hasStarted { return }
        pollForNewMessagesTimer = Timer.scheduledTimer(withTimeInterval: pollForNewMessagesInterval, repeats: true) { [weak self] _ in self?.pollForNewMessages() }
        pollForNewMessages() // Perform initial update
        pollForDeletedMessagesTimer = Timer.scheduledTimer(withTimeInterval: pollForDeletedMessagesInterval, repeats: true) { [weak self] _ in self?.pollForDeletedMessages() }
        pollForModerationPermissionTimer = Timer.scheduledTimer(withTimeInterval: pollForModerationPermissionInterval, repeats: true) { [weak self] _ in self?.pollForModerationPermission() }
        hasStarted = true
    }
    
    @objc public func stop() {
        pollForNewMessagesTimer?.invalidate()
        pollForDeletedMessagesTimer?.invalidate()
        pollForModerationPermissionTimer?.invalidate()
        hasStarted = false
    }
    
    private func pollForNewMessages() {
        let group = self.group
        let _ = LokiGroupChatAPI.getMessages(for: group.serverID, on: group.server).done { [weak self] messages in
            guard let self = self else { return }
            messages.reversed().forEach { message in
                let senderHexEncodedPublicKey = message.hexEncodedPublicKey
                if (senderHexEncodedPublicKey != self.ourHexEncodedPubKey) {
                    self.handleIncomingMessage(message, group: group);
                } else {
                    self.handleOutgoingMessage(message, group: group)
                }
            }
        }
    }
    
    private func handleOutgoingMessage(_ message: LokiGroupMessage, group: LokiGroupChat) {
        // Any Outgoing message should have a message server id mapped to it
        guard let messageServerID = message.serverID else { return }
        
        var hasMessage = false
        storage.newDatabaseConnection().read { transaction in
            let id = self.storage.getIDForMessage(withServerID: UInt(messageServerID), in: transaction);
            hasMessage = id != nil
        }
        
        // Check if we already have a message for this server message
        guard !hasMessage, let groupID = group.id.data(using: .utf8) else { return }
        
        // Get the thread
        let groupThread = TSGroupThread.getOrCreateThread(withGroupId: groupID)
        
        // Save the message
        let message = TSOutgoingMessage(outgoingMessageWithTimestamp: message.timestamp, in: groupThread, messageBody: message.body, attachmentIds: [], expiresInSeconds: 0, expireStartedAt: 0, isVoiceMessage: false, groupMetaMessage: .deliver, quotedMessage: nil, contactShare: nil, linkPreview: nil)
        storage.newDatabaseConnection().readWrite { transaction in
            message.update(withSentRecipient: group.server, wasSentByUD: false, transaction: transaction)
            message.savePublicChatMessageID(messageServerID, with: transaction)
            
            guard let messageID = message.uniqueId else {
                owsFailDebug("[Loki] Outgoing public chat message should have a unique id set")
                return
            }
            self.storage.setIDForMessageWithServerID(UInt(messageServerID), to: messageID, in: transaction)
        }
    }
    
    private func handleIncomingMessage(_ message: LokiGroupMessage, group: LokiGroupChat) {
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
        x2.setBody(message.body)
        
        // Pass down the message server id
        if let messageServerID = message.serverID {
            let publicChatInfo = SSKProtoPublicChatInfo.builder()
            publicChatInfo.setServerID(messageServerID)
            x2.setPublicChatInfo(try! publicChatInfo.build())
        }
        
        let x3 = SSKProtoContent.builder()
        x3.setDataMessage(try! x2.build())
        let x4 = SSKProtoEnvelope.builder(type: .ciphertext, timestamp: message.timestamp)
        x4.setSource(senderDisplayName)
        x4.setSourceDevice(OWSDevicePrimaryDeviceId)
        x4.setContent(try! x3.build().serializedData())
        OWSPrimaryStorage.shared().dbReadWriteConnection.readWrite { transaction in
            SSKEnvironment.shared.messageManager.throws_processEnvelope(try! x4.build(), plaintextData: try! x3.build().serializedData(), wasReceivedByUD: false, transaction: transaction)
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
        let _ = LokiGroupChatAPI.userHasModerationPermission(for: group.serverID, on: group.server).done { [storage] isModerator in
            storage.dbReadWriteConnection.readWrite { transaction in
                storage.setIsModerator(isModerator, for: UInt(group.serverID), on: group.server, in: transaction)
            }
        }
    }
}
