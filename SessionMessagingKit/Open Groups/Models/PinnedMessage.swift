// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct PinnedMessage: Codable {
        enum CodingKeys: String, CodingKey {
            case id
            case pinnedAt = "pinned_at"
            case pinnedBy = "pinned_by"
        }
    
        let id: Int64
        let pinnedAt: TimeInterval
        let pinnedBy: String
    }
}
