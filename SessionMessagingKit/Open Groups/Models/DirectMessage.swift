// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct DirectMessage: Codable {
        enum CodingKeys: String, CodingKey {
            case id
            case sender
            case expires = "expires_at"
            case base64EncodedData = "data"
        }
        
        public let id: Int64
        public let sender: String
        public let expires: TimeInterval
        public let base64EncodedData: String
    }
}
