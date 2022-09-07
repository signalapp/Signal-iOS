// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public final class ExpirationTimerUpdate: ControlMessage {
    private enum CodingKeys: String, CodingKey {
        case syncTarget
        case duration
    }
    
    /// In the case of a sync message, the public key of the person the message was targeted at.
    ///
    /// - Note: `nil` if this isn't a sync message.
    public var syncTarget: String?
    public var duration: UInt32?

    public override var isSelfSendValid: Bool { true }

    // MARK: - Initialization
    
    public init(syncTarget: String?, duration: UInt32) {
        super.init()
        
        self.syncTarget = syncTarget
        self.duration = duration
    }

    // MARK: - Validation
    
    public override var isValid: Bool {
        guard super.isValid else { return false }
        return duration != nil
    }
    
    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        syncTarget = try? container.decode(String.self, forKey: .syncTarget)
        duration = try? container.decode(UInt32.self, forKey: .duration)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(syncTarget, forKey: .syncTarget)
        try container.encodeIfPresent(duration, forKey: .duration)
    }

    // MARK: - Proto Conversion
    
    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> ExpirationTimerUpdate? {
        guard let dataMessageProto = proto.dataMessage else { return nil }
        
        let isExpirationTimerUpdate = (dataMessageProto.flags & UInt32(SNProtoDataMessage.SNProtoDataMessageFlags.expirationTimerUpdate.rawValue)) != 0
        guard isExpirationTimerUpdate else { return nil }
        
        return ExpirationTimerUpdate(
            syncTarget: dataMessageProto.syncTarget,
            duration: dataMessageProto.expireTimer
        )
    }

    public override func toProto(_ db: Database) -> SNProtoContent? {
        guard let duration = duration else {
            SNLog("Couldn't construct expiration timer update proto from: \(self).")
            return nil
        }
        let dataMessageProto = SNProtoDataMessage.builder()
        dataMessageProto.setFlags(UInt32(SNProtoDataMessage.SNProtoDataMessageFlags.expirationTimerUpdate.rawValue))
        dataMessageProto.setExpireTimer(duration)
        if let syncTarget = syncTarget { dataMessageProto.setSyncTarget(syncTarget) }
        // Group context
        do {
            try setGroupContextIfNeeded(db, on: dataMessageProto)
        } catch {
            SNLog("Couldn't construct expiration timer update proto from: \(self).")
            return nil
        }
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setDataMessage(try dataMessageProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct expiration timer update proto from: \(self).")
            return nil
        }
    }
    
    // MARK: - Description
    
    public var description: String {
        """
        ExpirationTimerUpdate(
            syncTarget: \(syncTarget ?? "null"),
            duration: \(duration?.description ?? "null")
        )
        """
    }
}
