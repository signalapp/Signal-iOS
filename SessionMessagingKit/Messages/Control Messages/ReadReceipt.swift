// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public final class ReadReceipt: ControlMessage {
    private enum CodingKeys: String, CodingKey {
        case timestamps
    }
    
    public var timestamps: [UInt64]?

    // MARK: - Initialization
    
    internal init(timestamps: [UInt64]) {
        super.init()
        
        self.timestamps = timestamps
    }

    // MARK: - Validation
    
    public override var isValid: Bool {
        guard super.isValid else { return false }
        if let timestamps = timestamps, !timestamps.isEmpty { return true }
        return false
    }
    
    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        timestamps = try? container.decode([UInt64].self, forKey: .timestamps)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(timestamps, forKey: .timestamps)
    }

    // MARK: - Proto Conversion
    
    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> ReadReceipt? {
        guard let receiptProto = proto.receiptMessage, receiptProto.type == .read else { return nil }
        let timestamps = receiptProto.timestamp
        guard !timestamps.isEmpty else { return nil }
        return ReadReceipt(timestamps: timestamps)
    }

    public override func toProto(_ db: Database) -> SNProtoContent? {
        guard let timestamps = timestamps else {
            SNLog("Couldn't construct read receipt proto from: \(self).")
            return nil
        }
        let receiptProto = SNProtoReceiptMessage.builder(type: .read)
        receiptProto.setTimestamp(timestamps)
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setReceiptMessage(try receiptProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct read receipt proto from: \(self).")
            return nil
        }
    }
    
    // MARK: - Description
    
    public var description: String {
        """
        ReadReceipt(
            timestamps: \(timestamps?.description ?? "null")
        )
        """
    }
}
