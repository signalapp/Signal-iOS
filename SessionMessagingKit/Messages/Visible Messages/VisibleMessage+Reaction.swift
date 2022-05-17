
public extension VisibleMessage {
    
    @objc(SNReaction)
    class Reaction : NSObject, NSCoding {
        public var timestamp: UInt64?
        public var publicKey: String?
        public var emoji: String?
        public var kind: Kind?
        
        // MARK: Kind
        public enum Kind : Int, CustomStringConvertible {
            case react, remove

            static func fromProto(_ proto: SNProtoDataMessageReaction.SNProtoDataMessageReactionAction) -> Kind {
                switch proto {
                case .react: return .react
                case .remove: return .remove
                }
            }

            func toProto() -> SNProtoDataMessageReaction.SNProtoDataMessageReactionAction {
                switch self {
                case .react: return .react
                case .remove: return .remove
                }
            }
            
            public var description: String {
                switch self {
                case .react: return "react"
                case .remove: return "remove"
                }
            }
        }
        
        // MARK: Validation
        public var isValid: Bool { timestamp != nil && publicKey != nil }

        // MARK: Initialization
        public override init() { super.init() }
        
        internal init(timestamp: UInt64, publicKey: String, emoji: String?, kind: Kind?) {
            self.timestamp = timestamp
            self.publicKey = publicKey
            self.emoji = emoji
            self.kind = kind
        }

        // MARK: Coding
        public required init?(coder: NSCoder) {
            if let timestamp = coder.decodeObject(forKey: "timestamp") as! UInt64? { self.timestamp = timestamp }
            if let publicKey = coder.decodeObject(forKey: "authorId") as! String? { self.publicKey = publicKey }
            if let emoji = coder.decodeObject(forKey: "emoji") as! String? { self.emoji = emoji }
            if let rawKind = coder.decodeObject(forKey: "action") as! Int? { self.kind = Kind(rawValue: rawKind) }
        }

        public func encode(with coder: NSCoder) {
            coder.encode(timestamp, forKey: "timestamp")
            coder.encode(publicKey, forKey: "authorId")
            coder.encode(emoji, forKey: "emoji")
            coder.encode(kind?.rawValue, forKey: "action")
        }

        // MARK: Proto Conversion
        public static func fromProto(_ proto: SNProtoDataMessageReaction) -> Reaction? {
            let timestamp = proto.id
            let publicKey = proto.author
            let emoji = proto.emoji
            let kind = Kind.fromProto(proto.action)
            return Reaction(timestamp: timestamp, publicKey: publicKey, emoji: emoji, kind: kind)
        }

        public func toProto() -> SNProtoDataMessageReaction? {
            preconditionFailure("Use toProto(using:) instead.")
        }

        public func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoDataMessageReaction? {
            guard let timestamp = timestamp, let publicKey = publicKey, let kind = kind else {
                SNLog("Couldn't construct reaction proto from: \(self).")
                return nil
            }
            let reactionProto = SNProtoDataMessageReaction.builder(id: timestamp, author: publicKey, action: kind.toProto())
            if let emoji = emoji { reactionProto.setEmoji(emoji) }
            do {
                return try reactionProto.build()
            } catch {
                SNLog("Couldn't construct quote proto from: \(self).")
                return nil
            }
        }
        
        // MARK: Description
        public override var description: String {
            """
            Reaction(
                timestamp: \(timestamp?.description ?? "null"),
                publicKey: \(publicKey ?? "null"),
                emoji: \(emoji ?? "null"),
                kind: \(kind?.description ?? "null")
            )
            """
        }
    }
}
