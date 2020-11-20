import SessionUtilitiesKit

public extension VisibleMessage {

    @objc(SNQuote)
    class Quote : NSObject, NSCoding {
        public var timestamp: UInt64?
        public var publicKey: String?
        public var text: String?

        public var isValid: Bool { timestamp != nil && publicKey != nil && text != nil }

        public override init() { super.init() }
        
        internal init(timestamp: UInt64, publicKey: String, text: String) {
            self.timestamp = timestamp
            self.publicKey = publicKey
            self.text = text
        }

        public required init?(coder: NSCoder) {
            if let timestamp = coder.decodeObject(forKey: "timestamp") as! UInt64? { self.timestamp = timestamp }
            if let publicKey = coder.decodeObject(forKey: "authorId") as! String? { self.publicKey = publicKey }
            if let text = coder.decodeObject(forKey: "body") as! String? { self.text = text }
        }

        public func encode(with coder: NSCoder) {
            coder.encode(timestamp, forKey: "timestamp")
            coder.encode(publicKey, forKey: "authorId")
            coder.encode(text, forKey: "body")
        }

        public static func fromProto(_ proto: SNProtoDataMessageQuote) -> Quote? {
            let timestamp = proto.id
            let publicKey = proto.author
            guard let text = proto.text else { return nil }
            return Quote(timestamp: timestamp, publicKey: publicKey, text: text)
        }

        public func toProto() -> SNProtoDataMessageQuote? {
            guard let timestamp = timestamp, let publicKey = publicKey, let text = text else {
                SNLog("Couldn't construct quote proto from: \(self).")
                return nil
            }
            let quoteProto = SNProtoDataMessageQuote.builder(id: timestamp, author: publicKey)
            quoteProto.setText(text)
            do {
                return try quoteProto.build()
            } catch {
                SNLog("Couldn't construct quote proto from: \(self).")
                return nil
            }
        }
    }
}
