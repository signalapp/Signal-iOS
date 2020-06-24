
@objc(LKClosedGroupUpdateMessage)
internal final class ClosedGroupUpdateMessage : TSOutgoingMessage {
    private let name: String
    private let id: String
    private let sharedSecret: String
    private let senderKey: String
    private let members: Set<String>

    @objc internal override var ttl: UInt32 { return UInt32(TTLUtilities.getTTL(for: .closedGroupUpdate)) }

    @objc internal override func shouldBeSaved() -> Bool { return false }
    @objc internal override func shouldSyncTranscript() -> Bool { return false }

    @objc internal init(thread: TSThread, name: String, id: String, sharedSecret: String, senderKey: String, members: Set<String>) {
        self.name = name
        self.id = id
        self.sharedSecret = sharedSecret
        self.senderKey = senderKey
        self.members = members
        super.init(outgoingMessageWithTimestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageBody: "Closed group created",
            attachmentIds: NSMutableArray(), expiresInSeconds: 0, expireStartedAt: 0, isVoiceMessage: false,
            groupMetaMessage: .new, quotedMessage: nil, contactShare: nil, linkPreview: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(thread:name:id:secretKey:senderKey:members:) instead.")
    }

    required init(dictionary: [String:Any]) throws {
        preconditionFailure("Use init(thread:name:id:secretKey:senderKey:members:) instead.")
    }

    @objc internal override func dataMessageBuilder() -> Any? {
        guard let builder = super.dataMessageBuilder() as? SSKProtoDataMessage.SSKProtoDataMessageBuilder else { return nil }
        let closedGroupUpdate = SSKProtoDataMessageClosedGroupUpdate.builder(name: name, groupID: id, sharedSecret: sharedSecret, senderKey: senderKey)
        closedGroupUpdate.setMembers([String](members))
        do {
            builder.setClosedGroupUpdate(try closedGroupUpdate.build())
        } catch {
            owsFailDebug("Failed to build closed group update due to error: \(error).")
            return nil
        }
        return builder
    }
}
