// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import WebRTC
import SessionUtilitiesKit

/// See https://developer.mozilla.org/en-US/docs/Web/API/RTCSessionDescription for more information.
public final class CallMessage: ControlMessage {
    private enum CodingKeys: String, CodingKey {
        case uuid
        case kind
        case sdps
    }
    
    public var uuid: String
    public var kind: Kind
    
    /// See https://developer.mozilla.org/en-US/docs/Glossary/SDP for more information.
    public var sdps: [String]
        
    public override var isSelfSendValid: Bool {
        switch kind {
            case .answer, .endCall: return true
            default: return false
        }
    }
    
    // MARK: - Kind
    
    /// **Note:** Multiple ICE candidates may be batched together for performance
    public enum Kind: Codable, CustomStringConvertible {
        private enum CodingKeys: String, CodingKey {
            case description
            case sdpMLineIndexes
            case sdpMids
        }
        
        case preOffer
        case offer
        case answer
        case provisionalAnswer
        case iceCandidates(sdpMLineIndexes: [UInt32], sdpMids: [String])
        case endCall
        
        public var description: String {
            switch self {
                case .preOffer: return "preOffer"
                case .offer: return "offer"
                case .answer: return "answer"
                case .provisionalAnswer: return "provisionalAnswer"
                case .iceCandidates(_, _): return "iceCandidates"
                case .endCall: return "endCall"
            }
        }
        
        public init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            
            // Compare the descriptions to find the appropriate case
            let description: String = try container.decode(String.self, forKey: .description)
            
            switch description {
                case Kind.preOffer.description: self = .preOffer
                case Kind.offer.description: self = .offer
                case Kind.answer.description: self = .answer
                case Kind.provisionalAnswer.description: self = .provisionalAnswer
                    
                case Kind.iceCandidates(sdpMLineIndexes: [], sdpMids: []).description:
                    self = .iceCandidates(
                        sdpMLineIndexes: try container.decode([UInt32].self, forKey: .sdpMLineIndexes),
                        sdpMids: try container.decode([String].self, forKey: .sdpMids)
                    )
                
                case Kind.endCall.description: self = .endCall
                    
                default: fatalError("Invalid case when trying to decode ClosedGroupControlMessage.Kind")
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(description, forKey: .description)
            
            // Note: If you modify the below make sure to update the above 'init(from:)' method
            switch self {
                case .preOffer: break                   // Only 'description'
                case .offer: break                      // Only 'description'
                case .answer: break                     // Only 'description'
                case .provisionalAnswer: break          // Only 'description'
                case .iceCandidates(let sdpMLineIndexes, let sdpMids):
                    try container.encode(sdpMLineIndexes, forKey: .sdpMLineIndexes)
                    try container.encode(sdpMids, forKey: .sdpMids)
                    
                case .endCall: break                    // Only 'description'
            }
        }
    }
    
    // MARK: - Initialization
    
    public init(
        uuid: String,
        kind: Kind,
        sdps: [String],
        sentTimestampMs: UInt64? = nil
    ) {
        self.uuid = uuid
        self.kind = kind
        self.sdps = sdps
        
        super.init(sentTimestamp: sentTimestampMs)
    }

    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        self.uuid = try container.decode(String.self, forKey: .uuid)
        self.kind = try container.decode(Kind.self, forKey: .kind)
        self.sdps = try container.decode([String].self, forKey: .sdps)
        
        try super.init(from: decoder)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(uuid, forKey: .uuid)
        try container.encode(kind, forKey: .kind)
        try container.encode(sdps, forKey: .sdps)
    }
    
    // MARK: - Proto Conversion
    
    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> CallMessage? {
        guard let callMessageProto = proto.callMessage else { return nil }
        
        let kind: Kind
        
        switch callMessageProto.type {
            case .preOffer: kind = .preOffer
            case .offer: kind = .offer
            case .answer: kind = .answer
            case .provisionalAnswer: kind = .provisionalAnswer
            case .iceCandidates:
                kind = .iceCandidates(
                    sdpMLineIndexes: callMessageProto.sdpMlineIndexes,
                    sdpMids: callMessageProto.sdpMids
                )
                
            case .endCall: kind = .endCall
        }
        
        let sdps = callMessageProto.sdps
        let uuid = callMessageProto.uuid
        
        return CallMessage(
            uuid: uuid,
            kind: kind,
            sdps: sdps
        )
    }
    
    public override func toProto(_ db: Database) -> SNProtoContent? {
        let type: SNProtoCallMessage.SNProtoCallMessageType
        
        switch kind {
            case .preOffer: type = .preOffer
            case .offer: type = .offer
            case .answer: type = .answer
            case .provisionalAnswer: type = .provisionalAnswer
            case .iceCandidates(_, _): type = .iceCandidates
            case .endCall: type = .endCall
        }
        
        let callMessageProto = SNProtoCallMessage.builder(type: type, uuid: uuid)
        if !sdps.isEmpty {
            callMessageProto.setSdps(sdps)
        }
        
        if case let .iceCandidates(sdpMLineIndexes, sdpMids) = kind {
            callMessageProto.setSdpMlineIndexes(sdpMLineIndexes)
            callMessageProto.setSdpMids(sdpMids)
        }
        
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setCallMessage(try callMessageProto.build())
            
            return try contentProto.build()
        }
        catch {
            SNLog("Couldn't construct call message proto from: \(self).")
            return nil
        }
    }
    
    // MARK: - Description
    
    public var description: String {
        """
        CallMessage(
            uuid: \(uuid),
            kind: \(kind.description),
            sdps: \(sdps.description)
        )
        """
    }
}

// MARK: - Convenience

public extension CallMessage {
    struct MessageInfo: Codable {
        public enum State: Codable {
            case incoming
            case outgoing
            case missed
            case permissionDenied
            case unknown
        }
        
        public let state: State
        
        // MARK: - Initialization
        
        public init(state: State) {
            self.state = state
        }
        
        // MARK: - Content
        
        func previewText(threadContactDisplayName: String) -> String {
            switch state {
                case .incoming:
                    return String(
                        format: "call_incoming".localized(),
                        threadContactDisplayName
                    )
                    
                case .outgoing:
                    return String(
                        format: "call_outgoing".localized(),
                        threadContactDisplayName
                    )
                    
                case .missed, .permissionDenied:
                    return String(
                        format: "call_missed".localized(),
                        threadContactDisplayName
                    )
                
                // TODO: We should do better here
                case .unknown: return ""
            }
        }
    }
}
