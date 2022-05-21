// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

/// Abstract base class for `VisibleMessage` and `ControlMessage`.
public class Message: Codable {
    public var id: String?
    public var threadId: String?
    public var sentTimestamp: UInt64?
    public var receivedTimestamp: UInt64?
    public var recipient: String?
    public var sender: String?
    public var groupPublicKey: String?
    public var openGroupServerMessageId: UInt64?
    public var openGroupServerTimestamp: UInt64?
    public var serverHash: String?

    public var ttl: UInt64 { 14 * 24 * 60 * 60 * 1000 }
    public var isSelfSendValid: Bool { false }

    // MARK: - Validation
    
    public var isValid: Bool {
        if let sentTimestamp = sentTimestamp { guard sentTimestamp > 0 else { return false } }
        if let receivedTimestamp = receivedTimestamp { guard receivedTimestamp > 0 else { return false } }
        return sender != nil && recipient != nil
    }
    
    // MARK: - Initialization
    
    public init(
        id: String? = nil,
        threadId: String? = nil,
        sentTimestamp: UInt64? = nil,
        receivedTimestamp: UInt64? = nil,
        recipient: String? = nil,
        sender: String? = nil,
        groupPublicKey: String? = nil,
        openGroupServerMessageId: UInt64? = nil,
        openGroupServerTimestamp: UInt64? = nil,
        serverHash: String? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.sentTimestamp = sentTimestamp
        self.receivedTimestamp = receivedTimestamp
        self.recipient = recipient
        self.sender = sender
        self.groupPublicKey = groupPublicKey
        self.openGroupServerMessageId = openGroupServerMessageId
        self.openGroupServerTimestamp = openGroupServerTimestamp
        self.serverHash = serverHash
    }

    // MARK: - Proto Conversion
    
    public class func fromProto(_ proto: SNProtoContent, sender: String) -> Self? {
        preconditionFailure("fromProto(_:sender:) is abstract and must be overridden.")
    }

    public func toProto(_ db: Database) -> SNProtoContent? {
        preconditionFailure("toProto(_:) is abstract and must be overridden.")
    }

    public func setGroupContextIfNeeded(_ db: Database, on dataMessage: SNProtoDataMessage.SNProtoDataMessageBuilder) throws {
        guard
            let threadId: String = threadId,
            (try? ClosedGroup.exists(db, id: threadId)) == true,
            let legacyGroupId: Data = "\(SMKLegacy.closedGroupIdPrefix)\(threadId)".data(using: .utf8)
        else { return }
        
        // Android needs a group context or it'll interpret the message as a one-to-one message
        let groupProto = SNProtoGroupContext.builder(id: legacyGroupId, type: .deliver)
        dataMessage.setGroup(try groupProto.build())
    }
}

// MARK: - Mutation

internal extension Message {
    func with(sentTimestamp: UInt64) -> Message {
        self.sentTimestamp = sentTimestamp
        return self
    }
}
