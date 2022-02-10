// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPIV2 {
    struct CompactPollBody: Codable {
        struct Room: Codable {
            enum CodingKeys: String, CodingKey {
                case id = "room_id"
                case fromMessageServerId = "from_message_server_id"
                case fromDeletionServerId = "from_deletion_server_id"
                
                // TODO: Remove this legacy value
                case legacyAuthToken = "auth_token"
            }
            
            let id: String
            let fromMessageServerId: Int64?
            let fromDeletionServerId: Int64?
            
            // TODO: This is a legacy value
            let legacyAuthToken: String?
        }
        
        let requests: [Room]
    }
}
