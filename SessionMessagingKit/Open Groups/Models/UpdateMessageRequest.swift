// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct UpdateMessageRequest: Codable {
        let data: Data
        let signature: Data
        
        // MARK: - Encodable
        
        public func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(data.base64EncodedString(), forKey: .data)
            try container.encode(signature.base64EncodedString(), forKey: .signature)
        }
    }
}
