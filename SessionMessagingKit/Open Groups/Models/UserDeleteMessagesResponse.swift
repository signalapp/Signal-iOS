// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPIV2 {
    public struct UserDeleteMessagesResponse: Codable {
        enum CodingKeys: String, CodingKey {
            case id
            case messagesDeleted = "messages_deleted"
        }
        
        let id: String
        let messagesDeleted: Int64
    }
}
