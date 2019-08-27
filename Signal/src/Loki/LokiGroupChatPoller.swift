import FeedKit

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
    
    private lazy var pollForDeletedMessagesInterval: TimeInterval = {
        switch group.kind {
        case .publicChat(_): return 32 * 60
        case .rss(_): preconditionFailure()
        }
    }()
    
    @objc(initForGroup:)
    public init(for group: LokiGroupChat) {
        self.group = group
        super.init()
    }
    
    @objc public func startIfNeeded() {
        if hasStarted { return }
        pollForNewMessagesTimer = Timer.scheduledTimer(withTimeInterval: pollForNewMessagesInterval, repeats: true) { [weak self] _ in self?.pollForNewMessages() }
        pollForNewMessages() // Perform initial update
        if group.isPublicChat {
            pollForDeletedMessagesTimer = Timer.scheduledTimer(withTimeInterval: pollForDeletedMessagesInterval, repeats: true) { [weak self] _ in self?.pollForDeletedMessages() }
        }
        hasStarted = true
    }
    
    @objc public func stop() {
        pollForNewMessagesTimer?.invalidate()
        pollForDeletedMessagesTimer?.invalidate()
        hasStarted = false
    }
    
    private func pollForNewMessages() {
        let group = self.group
        func parseGroupMessage(body: String, timestamp: UInt64, senderDisplayName: String) {
            let id = group.id.data(using: String.Encoding.utf8)!
            let x1 = SSKProtoGroupContext.builder(id: id, type: .deliver)
            x1.setName(group.displayName)
            let x2 = SSKProtoDataMessage.builder()
            x2.setTimestamp(timestamp)
            x2.setGroup(try! x1.build())
            x2.setBody(body)
            let x3 = SSKProtoContent.builder()
            x3.setDataMessage(try! x2.build())
            let x4 = SSKProtoEnvelope.builder(type: .ciphertext, timestamp: timestamp)
            x4.setSource(senderDisplayName)
            x4.setSourceDevice(OWSDevicePrimaryDeviceId)
            x4.setContent(try! x3.build().serializedData())
            OWSPrimaryStorage.shared().dbReadWriteConnection.readWrite { transaction in
                SSKEnvironment.shared.messageManager.throws_processEnvelope(try! x4.build(), plaintextData: try! x3.build().serializedData(), wasReceivedByUD: false, transaction: transaction)
            }
        }
        switch group.kind {
        case .publicChat(let id):
            let _ = LokiGroupChatAPI.getMessages(for: id, on: group.server).done { messages in
                messages.reversed().forEach { message in
                    let senderHexEncodedPublicKey = message.hexEncodedPublicKey
                    let endIndex = senderHexEncodedPublicKey.endIndex
                    let cutoffIndex = senderHexEncodedPublicKey.index(endIndex, offsetBy: -8)
                    let senderDisplayName = "\(message.displayName) (...\(senderHexEncodedPublicKey[cutoffIndex..<endIndex]))"
                    parseGroupMessage(body: message.body, timestamp: message.timestamp, senderDisplayName: senderDisplayName)
                }
            }
        case .rss(_):
            let url = URL(string: group.server)!
            FeedParser(URL: url).parseAsync { wrapper in
                guard case .rss(let feed) = wrapper, let items = feed.items else { return print("[Loki] Failed to parse RSS feed for: \(group.server)") }
                items.reversed().forEach { item in
                    guard let title = item.title, let description = item.description, let date = item.pubDate else { return }
                    let timestamp = UInt64(date.timeIntervalSince1970 * 1000)
                    let body = "\(title) ... \(description)"
                    parseGroupMessage(body: body, timestamp: timestamp, senderDisplayName: NSLocalizedString("Loki", comment: ""))
                }
            }
            
        }
    }
    
    private func pollForDeletedMessages() {
        // TODO: Implement
    }
}
