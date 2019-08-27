
private let kChatID = "PublicChatID"
private let kChatChannelID = "PublicChatChannelID"
private let kChatName = "PublicChatName"
private let kServerURL = "PublicChatServerURL"

@objc(LKGroupChatPoller)
public final class LokiGroupChatPoller : NSObject {
    private let groups: [[String: Any]]
    private var pollForNewMessagesTimer: Timer? = nil
    private var pollForDeletedMessagesTimer: Timer? = nil
    private var hasStarted = false
    
    private let pollForNewMessagesInterval: TimeInterval = 4
    private let pollForDeletedMessagesInterval: TimeInterval = 32 * 60
    
    @objc public init(groups: [[String: Any]]) {
        self.groups = groups
        super.init()
    }
    
    @objc public func startIfNeeded() {
        if hasStarted { return }
        pollForNewMessagesTimer = Timer.scheduledTimer(withTimeInterval: pollForNewMessagesInterval, repeats: true) { [weak self] _ in self?.pollForNewMessages() }
        pollForDeletedMessagesTimer = Timer.scheduledTimer(withTimeInterval: pollForDeletedMessagesInterval, repeats: true) { [weak self] _ in self?.pollForDeletedMessages() }
        hasStarted = true
    }
    
    @objc public func stop() {
        pollForNewMessagesTimer?.invalidate()
        pollForDeletedMessagesTimer?.invalidate()
        hasStarted = false
    }
    
    private func pollForNewMessages() {
        for group in groups {
            guard let channelID = group[kChatChannelID] as? UInt, let server = group[kServerURL] as? String else {
                Logger.info("[Loki] Failed to get channel id or server url from group: \(group)")
                return
            }
            
    LokiGroupChatAPI.getMessages(for: channelID, on: server).map { [weak self] messages in
                self?.handleMessages(messages: messages, group: group)
            }
        }
    }
    
    private func handleMessages(messages: [LokiGroupMessage], group: [String: Any]) -> Void {
        guard let groupID = group[kChatID] as? String, let groupName = group[kChatName] as? String else {
            Logger.info("[Loki] Failed to handle messages for group: \(group))")
            return
        }
        
        messages.reversed().forEach { message in
            let id = groupID.data(using: String.Encoding.utf8)!
            let x1 = SSKProtoGroupContext.builder(id: id, type: .deliver)
            x1.setName(groupName)
            let x2 = SSKProtoDataMessage.builder()
            x2.setTimestamp(message.timestamp)
            x2.setGroup(try! x1.build())
            x2.setBody(message.body)
            let x3 = SSKProtoContent.builder()
            x3.setDataMessage(try! x2.build())
            let x4 = SSKProtoEnvelope.builder(type: .ciphertext, timestamp: message.timestamp)
            let senderHexEncodedPublicKey = message.hexEncodedPublicKey
            let endIndex = senderHexEncodedPublicKey.endIndex
            let cutoffIndex = senderHexEncodedPublicKey.index(endIndex, offsetBy: -8)
            let senderDisplayName = "\(message.displayName) (...\(senderHexEncodedPublicKey[cutoffIndex..<endIndex]))"
            x4.setSource(senderDisplayName)
            x4.setSourceDevice(OWSDevicePrimaryDeviceId)
            x4.setContent(try! x3.build().serializedData())
            OWSPrimaryStorage.shared().dbReadWriteConnection.readWrite { transaction in
                SSKEnvironment.shared.messageManager.throws_processEnvelope(try! x4.build(), plaintextData: try! x3.build().serializedData(), wasReceivedByUD: false, transaction: transaction)
            }
        }
    }
    
    private func pollForDeletedMessages() {
        // TODO: Implement
    }
}
