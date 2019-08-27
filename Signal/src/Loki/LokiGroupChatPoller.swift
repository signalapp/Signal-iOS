
@objc(LKGroupChatPoller)
public final class LokiGroupChatPoller : NSObject {
    private let group: UInt
    private var timer: Timer? = nil
    private var hasStarted = false
    
    private let pollInterval: TimeInterval = 4
    
    @objc public init(group: UInt) {
        self.group = group
        super.init()
    }
    
    @objc public func startIfNeeded() {
        if hasStarted { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in self?.poll() }
        hasStarted = true
    }
    
    @objc public func stop() {
        timer?.invalidate()
        hasStarted = false
    }
    
    private func poll() {
        let group = self.group
        let _ = LokiGroupChatAPI.getMessages(for: group, on: LokiGroupChatAPI.publicChatServer).map { messages in
            messages.reversed().map { message in
                let id = "\(LokiGroupChatAPI.publicChatServer).\(group)".data(using: String.Encoding.utf8)!
                let x1 = SSKProtoGroupContext.builder(id: id, type: .deliver)
                x1.setName(NSLocalizedString("Loki Public Chat", comment: ""))
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
    }
}
