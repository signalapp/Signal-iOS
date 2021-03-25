
public struct OpenGroupMessageV2 {
    public let serverID: Int64?
    public let sender: String?
    public let sentTimestamp: UInt64
    /// The serialized protobuf in base64 encoding.
    public let base64EncodedData: String
    /// When sending a message, the sender signs the serialized protobuf with their private key so that
    /// a receiving user can verify that the message wasn't tampered with.
    public let base64EncodedSignature: String?

    public func sign() -> OpenGroupMessageV2? {
        let userKeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair()!
        let data = Data(base64Encoded: base64EncodedData)!
        guard let signature = try? Ed25519.sign(data, with: userKeyPair) else {
            SNLog("Failed to sign open group message.")
            return nil
        }
        return OpenGroupMessageV2(serverID: serverID, sender: sender, sentTimestamp: sentTimestamp,
            base64EncodedData: base64EncodedData, base64EncodedSignature: signature.base64EncodedString())
    }

    public func toJSON() -> JSON? {
        var result: JSON = [ "data" : base64EncodedData, "timestamp" : sentTimestamp ]
        if let serverID = serverID { result["server_id"] = serverID }
        if let sender = sender { result["public_key"] = sender }
        if let base64EncodedSignature = base64EncodedSignature { result["signature"] = base64EncodedSignature }
        return result
    }

    public static func fromJSON(_ json: JSON) -> OpenGroupMessageV2? {
        guard let base64EncodedData = json["data"] as? String, let sentTimestamp = json["timestamp"] as? UInt64 else { return nil }
        let serverID = json["server_id"] as? Int64
        let sender = json["public_key"] as? String
        let base64EncodedSignature = json["signature"] as? String
        return OpenGroupMessageV2(serverID: serverID, sender: sender, sentTimestamp: sentTimestamp, base64EncodedData: base64EncodedData, base64EncodedSignature: base64EncodedSignature)
    }
}
