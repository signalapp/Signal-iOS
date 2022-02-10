// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPIV2 {
    public struct CompactPollResponse: Codable {
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
            public let messages: [OpenGroupMessageV2]?
            public let deletions: [Deletion]?
            public let moderators: [String]?
        }
        
        public let results: [Result]
    }
}
