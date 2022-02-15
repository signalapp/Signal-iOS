// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct LegacyCompactPollResponse: Codable {
        public struct Result: Codable {
            enum CodingKeys: String, CodingKey {
                case room = "room_id"
                case statusCode = "status_code"
                case messages
                case deletions
                case moderators
            }
            
            public let room: String
            public let statusCode: UInt
            public let messages: [LegacyOpenGroupMessageV2]?
            public let deletions: [LegacyDeletion]?
            public let moderators: [String]?
        }
        
        public let results: [Result]
    }
}
