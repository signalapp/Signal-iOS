// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct PinnedMessage: Codable, Equatable {
        enum CodingKeys: String, CodingKey {
            case id
            case pinnedAt = "pinned_at"
            case pinnedBy = "pinned_by"
        }
    
        /// The numeric message id
        let id: Int64
        
        /// The unix timestamp when the message was pinned
        let pinnedAt: TimeInterval
        
        /// The session ID of the admin who pinned this message (which is not necessarily the same as the author of the message)
        let pinnedBy: String
    }
}
