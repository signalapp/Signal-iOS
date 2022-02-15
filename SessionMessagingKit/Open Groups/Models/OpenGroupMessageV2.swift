import Foundation
import SessionUtilitiesKit

public struct OpenGroupMessageV2: Codable {
    enum CodingKeys: String, CodingKey {
        case serverID = "server_id"
        case sender = "public_key"
        case sentTimestamp = "timestamp"
        case base64EncodedData = "data"
        case base64EncodedSignature = "signature"
    }
    
    public let serverID: Int64?
    public let sender: String?
    public let sentTimestamp: UInt64
    /// The serialized protobuf in base64 encoding.
    public let base64EncodedData: String
    /// When sending a message, the sender signs the serialized protobuf with their private key so that
    /// a receiving user can verify that the message wasn't tampered with.
    public let base64EncodedSignature: String?

    public func sign(with publicKey: String) -> OpenGroupMessageV2? {
        guard let userKeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else { return nil }
        guard let data = Data(base64Encoded: base64EncodedData) else { return nil }
        guard let signature = try? Ed25519.sign(data, with: userKeyPair) else {
            SNLog("Failed to sign open group message.")
            return nil
        }
        
        return OpenGroupMessageV2(
            serverID: serverID,
            sender: sender,
            sentTimestamp: sentTimestamp,
            base64EncodedData: base64EncodedData,
            base64EncodedSignature: signature.base64EncodedString()
        )
    }
}

// MARK: - Decoder

extension OpenGroupMessageV2 {
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
    
        let sender: String = try container.decode(String.self, forKey: .sender)
        let base64EncodedData: String = try container.decode(String.self, forKey: .base64EncodedData)
        let base64EncodedSignature: String = try container.decode(String.self, forKey: .base64EncodedSignature)
        
        // Validate the message signature
        guard let data = Data(base64Encoded: base64EncodedData), let signature = Data(base64Encoded: base64EncodedSignature) else {
            throw OpenGroupAPI.Error.parsingFailed
        }
        
        let publicKey = Data(hex: sender.removingIdPrefixIfNeeded())
        let isValid = (try? Ed25519.verifySignature(signature, publicKey: publicKey, data: data)) ?? false
        
        guard isValid else {
            SNLog("Ignoring message with invalid signature.")
            throw OpenGroupAPI.Error.parsingFailed
        }
        
        self = OpenGroupMessageV2(
            serverID: try? container.decode(Int64.self, forKey: .serverID),
            sender: sender,
            sentTimestamp: try container.decode(UInt64.self, forKey: .sentTimestamp),
            base64EncodedData: base64EncodedData,
            base64EncodedSignature: base64EncodedSignature
        )
    }
}
