
@objc(LKGroupChatPoller)
public final class LokiGroupChatPoller : NSObject {
    private let group: LokiGroupChat
    private var pollForNewMessagesTimer: Timer? = nil
    private var pollForDeletedMessagesTimer: Timer? = nil
    private var hasStarted = false
    
    private lazy var pollForNewMessagesInterval: TimeInterval = {
        switch group.kind {
        case .publicChat(_): return 4
        case .rss(_): return 8 * 60
        }
    }()
    
    private let pollForDeletedMessagesInterval: TimeInterval = 32 * 60
    
    @objc(initForGroup:)
    public init(for group: LokiGroupChat) {
        self.group = group
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
        let group = self.group
        switch group.kind {
        case .publicChat(let id):
            let _ = LokiGroupChatAPI.getMessages(for: id, on: group.server).done { messages in
                messages.reversed().forEach { message in
                    let id = group.id.data(using: String.Encoding.utf8)!
                    let x1 = SSKProtoGroupContext.builder(id: id, type: .deliver)
                    x1.setName(group.displayName)
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
        case .rss(let customID): break // TODO: Implement
        }
    }
    
    private func pollForDeletedMessages() {
        // TODO: Implement
    }
}
