// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    struct LegacyDeletedMessagesResponse: Codable {
        enum CodingKeys: String, CodingKey {
            case deletions = "ids"
        }
        
        let deletions: [LegacyDeletion]
    }
}
