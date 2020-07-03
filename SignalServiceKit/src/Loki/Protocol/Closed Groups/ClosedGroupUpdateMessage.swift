
@objc(LKClosedGroupUpdateMessage)
internal final class ClosedGroupUpdateMessage : TSOutgoingMessage {
    private let kind: Kind

    // MARK: Settings
    @objc internal override var ttl: UInt32 { return UInt32(TTLUtilities.getTTL(for: .closedGroupUpdate)) }

    @objc internal override func shouldBeSaved() -> Bool { return false }
    @objc internal override func shouldSyncTranscript() -> Bool { return false }

    // MARK: Kind
    internal enum Kind {
        case new(groupPublicKey: Data, name: String, groupPrivateKey: Data, chainKeys: [Data], members: [String], admins: [String])
        case info(groupPublicKey: Data, name: String, chainKeys: [Data], members: [String], admins: [String])
        case chainKey(groupPublicKey: Data, chainKey: Data)
    }

    // MARK: Initialization
    internal init(thread: TSThread, kind: Kind) {
        self.kind = kind
        super.init(outgoingMessageWithTimestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageBody: "",
            attachmentIds: NSMutableArray(), expiresInSeconds: 0, expireStartedAt: 0, isVoiceMessage: false,
            groupMetaMessage: .unspecified, quotedMessage: nil, contactShare: nil, linkPreview: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(thread:kind:) instead.")
    }

    required init(dictionary: [String:Any]) throws {
        preconditionFailure("Use init(thread:kind:) instead.")
    }

    // MARK: Building
    @objc internal override func dataMessageBuilder() -> Any? {
        guard let builder = super.dataMessageBuilder() as? SSKProtoDataMessage.SSKProtoDataMessageBuilder else { return nil }
        do {
            let closedGroupUpdate: SSKProtoDataMessageClosedGroupUpdate.SSKProtoDataMessageClosedGroupUpdateBuilder
            switch kind {
            case .new(let groupPublicKey, let name, let groupPrivateKey, let chainKeys, let members, let admins):
                closedGroupUpdate = SSKProtoDataMessageClosedGroupUpdate.builder(groupPublicKey: groupPublicKey, type: .new)
                closedGroupUpdate.setName(name)
                closedGroupUpdate.setGroupPrivateKey(groupPrivateKey)
                closedGroupUpdate.setChainKeys(chainKeys)
                closedGroupUpdate.setMembers(members)
                closedGroupUpdate.setAdmins(admins)
            case .info(let groupPublicKey, let name, let chainKeys, let members, let admins):
                closedGroupUpdate = SSKProtoDataMessageClosedGroupUpdate.builder(groupPublicKey: groupPublicKey, type: .info)
                closedGroupUpdate.setName(name)
                closedGroupUpdate.setChainKeys(chainKeys)
                closedGroupUpdate.setMembers(members)
                closedGroupUpdate.setAdmins(admins)
            case .chainKey(let groupPublicKey, let chainKey):
                closedGroupUpdate = SSKProtoDataMessageClosedGroupUpdate.builder(groupPublicKey: groupPublicKey, type: .chainKey)
                closedGroupUpdate.setChainKeys([ chainKey ])
            }
            builder.setClosedGroupUpdate(try closedGroupUpdate.build())
        } catch {
            owsFailDebug("Failed to build closed group update due to error: \(error).")
            return nil
        }
        return builder
    }
}
