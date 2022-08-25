// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public extension VisibleMessage {
    struct VMReaction: Codable {
        /// This is the timestamp (in milliseconds since epoch) when the interaction this reaction belongs to was sent
        public var timestamp: UInt64
        
        /// This is the public key of the sender of the interaction this reaction belongs to
        public var publicKey: String
        
        /// This is the emoji for the reaction
        public var emoji: String
        
        /// This is the behaviour for the reaction
        public var kind: Kind
        
        public var isValid: Bool { true }
        
        // MARK: - Kind
        
        public enum Kind: Int, Codable {
            case react
            case remove
            
            var description: String {
                switch self {
                    case .react: return "react"
                    case .remove: return "remove"
                }
            }
            
            // MARK: - Initialization
            
            init(protoAction: SNProtoDataMessageReaction.SNProtoDataMessageReactionAction) {
                switch protoAction {
                    case .react: self = .react
                    case .remove: self = .remove
                }
            }
            
            // MARK: - Proto Conversion
            
            func toProto() -> SNProtoDataMessageReaction.SNProtoDataMessageReactionAction {
                switch self {
                    case .react: return .react
                    case .remove: return .remove
                }
            }
        }
        
        // MARK: - Initialization

        public init(timestamp: UInt64, publicKey: String, emoji: String, kind: Kind) {
            self.timestamp = timestamp
            self.publicKey = publicKey
            self.emoji = emoji
            self.kind = kind
        }

        // MARK: - Proto Conversion
        
        public static func fromProto(_ proto: SNProtoDataMessageReaction) -> VMReaction? {
            guard let emoji: String = proto.emoji else { return nil }
            
            return VMReaction(
                timestamp: proto.id,
                publicKey: proto.author,
                emoji: emoji,
                kind: Kind(protoAction: proto.action)
            )
        }

        public func toProto() -> SNProtoDataMessageReaction? {
            let reactionProto = SNProtoDataMessageReaction.builder(
                id: self.timestamp,
                author: self.publicKey,
                action: self.kind.toProto()
            )
            reactionProto.setEmoji(self.emoji)
            
            do {
                return try reactionProto.build()
            } catch {
                SNLog("Couldn't construct quote proto from: \(self).")
                return nil
            }
        }
        
        // MARK: - Description
        
        public var description: String {
            """
            Reaction(
                timestamp: \(timestamp),
                publicKey: \(publicKey),
                emoji: \(emoji),
                kind: \(kind.description)
            )
            """
        }
    }
}
