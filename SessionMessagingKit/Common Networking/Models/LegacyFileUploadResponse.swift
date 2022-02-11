// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

struct LegacyFileUploadResponse: Codable {
    enum CodingKeys: String, CodingKey {
        case fileId = "result"
    }
    
    public let fileId: UInt64
}
