// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPIV2 {
    public struct SendMessageRequest: Codable {
        enum CodingKeys: String, CodingKey {
            case data
            case signature
            case whisperTo = "whisper_to"
            case whisperMods = "whisper_mods"
            case fileIds = "files"
        }
        
        let data: Data
        let signature: Data
        let whisperTo: String?
        let whisperMods: Bool
        let fileIds: [Int64]?
        
        // MARK: - Initialization
        
        init(
            data: Data,
            signature: Data,
            whisperTo: String? = nil,
            whisperMods: Bool = false,
            fileIds: [Int64]? = nil
        ) {
            self.data = data
            self.signature = signature
            self.whisperTo = whisperTo
            self.whisperMods = whisperMods
            self.fileIds = fileIds
        }
        
        // MARK: - Encodable
        
        public func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(data.base64EncodedString(), forKey: .data)
            try container.encode(signature.base64EncodedString(), forKey: .signature)
            try container.encodeIfPresent(whisperTo, forKey: .whisperTo)
            try container.encode(whisperMods, forKey: .whisperMods)
            try container.encodeIfPresent(fileIds, forKey: .fileIds)
        }
        
        // MARK: - Signing
        
        public static func sign(message: Data, for idType: IdPrefix, with publicKey: String) -> (data: Data, signature: Data)? {
            guard let userKeyPair: ECKeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else {
                return nil
            }
            guard let targetKeyPair: ECKeyPair = try? userKeyPair.convert(to: idType, with: publicKey) else {
                return nil
            }
            
            guard let signature = try? Ed25519.sign(message, with: targetKeyPair) else {
                SNLog("Failed to sign open group message.")
                return nil
            }
            
            return (message, signature)
        }
    }
}
