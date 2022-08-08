// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public final class TypingIndicator: ControlMessage {
    private enum CodingKeys: String, CodingKey {
        case kind
    }
    
    public var kind: Kind?

    public override var ttl: UInt64 { 20 * 1000 }

    // MARK: - Kind
    
    public enum Kind: Int, Codable, CustomStringConvertible {
        case started, stopped

        static func fromProto(_ proto: SNProtoTypingMessage.SNProtoTypingMessageAction) -> Kind {
            switch proto {
                case .started: return .started
                case .stopped: return .stopped
            }
        }

        func toProto() -> SNProtoTypingMessage.SNProtoTypingMessageAction {
            switch self {
                case .started: return .started
                case .stopped: return .stopped
            }
        }
        
        public var description: String {
            switch self {
                case .started: return "started"
                case .stopped: return "stopped"
            }
        }
    }

    // MARK: - Validation
    
    public override var isValid: Bool {
        guard super.isValid else { return false }
        return kind != nil
    }

    // MARK: - Initialization

    internal init(kind: Kind) {
        super.init()
        
        self.kind = kind
    }
    
    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        kind = try? container.decode(Kind.self, forKey: .kind)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(kind, forKey: .kind)
    }

    // MARK: - Proto Conversion
    
    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> TypingIndicator? {
        guard let typingIndicatorProto = proto.typingMessage else { return nil }
        let kind = Kind.fromProto(typingIndicatorProto.action)
        return TypingIndicator(kind: kind)
    }

    public override func toProto(_ db: Database) -> SNProtoContent? {
        guard let timestamp = sentTimestamp, let kind = kind else {
            SNLog("Couldn't construct typing indicator proto from: \(self).")
            return nil
        }
        let typingIndicatorProto = SNProtoTypingMessage.builder(timestamp: timestamp, action: kind.toProto())
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setTypingMessage(try typingIndicatorProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct typing indicator proto from: \(self).")
            return nil
        }
    }
    
    // MARK: - Description
    
    public var description: String {
        """
        TypingIndicator(
            kind: \(kind?.description ?? "null")
        )
        """
    }
}
