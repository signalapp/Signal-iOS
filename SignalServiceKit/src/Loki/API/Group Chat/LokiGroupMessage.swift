import PromiseKit

@objc(LKGroupMessage)
public final class LokiGroupMessage : NSObject {
    public let serverID: UInt64?
    public let hexEncodedPublicKey: String
    public let displayName: String
    public let body: String
    /// - Note: Expressed as milliseconds since 00:00:00 UTC on 1 January 1970.
    public let timestamp: UInt64
    public let type: String
    public let quote: Quote?
    public let signature: Signature?
    
    @objc(serverID)
    public var objc_serverID: UInt64 { return serverID ?? 0 }
    
    // MARK: Settings
    private let signatureVersion: UInt64 = 1
    
    // MARK: Types
    public struct Quote {
        public let quotedMessageTimestamp: UInt64
        public let quoteeHexEncodedPublicKey: String
        public let quotedMessageBody: String
        public let quotedMessageServerID: UInt64?
    }
    
    public struct Signature {
        public let data: Data
        public let version: UInt64
    }
    
    // MARK: Initialization
    public init(serverID: UInt64?, hexEncodedPublicKey: String, displayName: String, body: String, type: String, timestamp: UInt64, quote: Quote?, signature: Signature?) {
        self.serverID = serverID
        self.hexEncodedPublicKey = hexEncodedPublicKey
        self.displayName = displayName
        self.body = body
        self.type = type
        self.timestamp = timestamp
        self.quote = quote
        self.signature = signature
        super.init()
    }
    
    @objc public convenience init(hexEncodedPublicKey: String, displayName: String, body: String, type: String, timestamp: UInt64, quotedMessageTimestamp: UInt64, quoteeHexEncodedPublicKey: String?, quotedMessageBody: String?, quotedMessageServerID: UInt64, signatureData: Data?, signatureVersion: UInt64) {
        let quote: Quote?
        if quotedMessageTimestamp != 0, let quoteeHexEncodedPublicKey = quoteeHexEncodedPublicKey, let quotedMessageBody = quotedMessageBody {
            let quotedMessageServerID = (quotedMessageServerID != 0) ? quotedMessageServerID : nil
            quote = Quote(quotedMessageTimestamp: quotedMessageTimestamp, quoteeHexEncodedPublicKey: quoteeHexEncodedPublicKey, quotedMessageBody: quotedMessageBody, quotedMessageServerID: quotedMessageServerID)
        } else {
            quote = nil
        }
        let signature: Signature?
        if let signatureData = signatureData, signatureVersion != 0 {
            signature = Signature(data: signatureData, version: signatureVersion)
        } else {
            signature = nil
        }
        self.init(serverID: nil, hexEncodedPublicKey: hexEncodedPublicKey, displayName: displayName, body: body, type: type, timestamp: timestamp, quote: quote, signature: signature)
    }
    
    // MARK: Crypto
    internal func sign(with privateKey: Data) -> LokiGroupMessage? {
        guard let data = getValidationData(for: signatureVersion) else {
            print("[Loki] Failed to sign group chat message.")
            return nil
        }
        let userKeyPair = OWSIdentityManager.shared().identityKeyPair()!
        guard let signatureData = try? Ed25519.sign(data, with: userKeyPair) else {
            print("[Loki] Failed to sign group chat message.")
            return nil
        }
        let signature = Signature(data: signatureData, version: signatureVersion)
        return LokiGroupMessage(serverID: serverID, hexEncodedPublicKey: hexEncodedPublicKey, displayName: displayName, body: body, type: type, timestamp: timestamp, quote: quote, signature: signature)
    }
    
    internal func hasValidSignature() -> Bool {
        guard let signature = signature else { return false }
        guard let data = getValidationData(for: signature.version) else { return false }
        return (try? Ed25519.verifySignature(signature.data, publicKey: Data(hex: hexEncodedPublicKey), data: data)) ?? false
    }
    
    // MARK: JSON
    internal func toJSON() -> JSON {
        var value: JSON = [ "timestamp" : timestamp ]
        if let quote = quote {
            value["quote"] = [ "id" : quote.quotedMessageTimestamp, "author" : quote.quoteeHexEncodedPublicKey, "text" : quote.quotedMessageBody ]
        }
        if let signature = signature {
            value["sig"] = signature.data.toHexString()
            value["sigver"] = signature.version
        }
        let annotation: JSON = [ "type" : type, "value" : value ]
        var result: JSON = [ "text" : body, "annotations": [ annotation ] ]
        if let quotedMessageServerID = quote?.quotedMessageServerID {
            result["reply_to"] = quotedMessageServerID
        }
        return result
    }
    
    // MARK: Convenience
    private func getValidationData(for signatureVersion: UInt64) -> Data? {
        var string = "\(body.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))\(timestamp)"
        if let quote = quote {
            string += "\(quote.quotedMessageTimestamp)\(quote.quoteeHexEncodedPublicKey)\(quote.quotedMessageBody.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))"
            if let quotedMessageServerID = quote.quotedMessageServerID {
                string += "\(quotedMessageServerID)"
            }
        }
        string += "\(signatureVersion)"
        return string.data(using: String.Encoding.utf8)
    }
}
