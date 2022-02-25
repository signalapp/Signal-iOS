// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct SendDirectMessageRequest: Codable {
        let message: Data
        
        // MARK: - Encodable
        
        public func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(message.base64EncodedString(), forKey: .message)
        }
    }
}
