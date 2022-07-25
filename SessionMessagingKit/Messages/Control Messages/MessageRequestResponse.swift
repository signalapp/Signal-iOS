// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public final class MessageRequestResponse: ControlMessage {
    private enum CodingKeys: String, CodingKey {
        case isApproved
    }
    
    public var isApproved: Bool
    
    // MARK: - Initialization
    
    public init(
        isApproved: Bool,
        sentTimestampMs: UInt64? = nil
    ) {
        self.isApproved = isApproved
        
        super.init(
            sentTimestamp: sentTimestampMs
        )
    }
    
    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        isApproved = try container.decode(Bool.self, forKey: .isApproved)
        
        try super.init(from: decoder)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(isApproved, forKey: .isApproved)
    }
    
    // MARK: - Proto Conversion

    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> MessageRequestResponse? {
        guard let messageRequestResponseProto = proto.messageRequestResponse else { return nil }
        
        return MessageRequestResponse(isApproved: messageRequestResponseProto.isApproved)
    }

    public override func toProto(_ db: Database) -> SNProtoContent? {
        let messageRequestResponseProto = SNProtoMessageRequestResponse.builder(isApproved: isApproved)
        let contentProto = SNProtoContent.builder()
        
        do {
            contentProto.setMessageRequestResponse(try messageRequestResponseProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct unsend request proto from: \(self).")
            return nil
        }
    }
    
    // MARK: - Description
    
    public var description: String {
        """
        MessageRequestResponse(
            isApproved: \(isApproved)
        )
        """
    }
}
