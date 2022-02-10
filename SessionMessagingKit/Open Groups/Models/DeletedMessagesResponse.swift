// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPIV2 {
    struct DeletedMessagesResponse: Codable {
        enum CodingKeys: String, CodingKey {
            case deletions = "ids"
        }
        
        let deletions: [Deletion]
    }
}
