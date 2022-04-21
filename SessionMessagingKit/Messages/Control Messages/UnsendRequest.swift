// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

@objc(SNUnsendRequest)
public final class UnsendRequest: ControlMessage {
    private enum CodingKeys: String, CodingKey {
        case timestamp
        case author
    }
    
    public var timestamp: UInt64?
    public var author: String?
    
    public override var isSelfSendValid: Bool { true }
    
    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid else { return false }
        return timestamp != nil && author != nil
    }
    
    // MARK: Initialization
    public override init() { super.init() }

    internal init(timestamp: UInt64, author: String) {
        super.init()
        self.timestamp = timestamp
        self.author = author
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let timestamp = coder.decodeObject(forKey: "timestamp") as! UInt64? { self.timestamp = timestamp }
        if let author = coder.decodeObject(forKey: "author") as! String? { self.author = author }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(timestamp, forKey: "timestamp")
        coder.encode(author, forKey: "author")
    }
    
    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        timestamp = try? container.decode(UInt64.self, forKey: .timestamp)
        author = try? container.decode(String.self, forKey: .author)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(author, forKey: .author)
    }
    
    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> UnsendRequest? {
        guard let unsendRequestProto = proto.unsendRequest else { return nil }
        let timestamp = unsendRequestProto.timestamp
        let author = unsendRequestProto.author
        return UnsendRequest(timestamp: timestamp, author: author)
    }

    public override func toProto(_ db: Database) -> SNProtoContent? {
        guard let timestamp = timestamp, let author = author else {
            SNLog("Couldn't construct unsend request proto from: \(self).")
            return nil
        }
        let unsendRequestProto = SNProtoUnsendRequest.builder(timestamp: timestamp, author: author)
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setUnsendRequest(try unsendRequestProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct unsend request proto from: \(self).")
            return nil
        }
    }
    
    // MARK: Description
    public override var description: String {
        """
        UnsendRequest(
            timestamp: \(timestamp?.description ?? "null")
            author: \(author?.description ?? "null")
        )
        """
    }
}
