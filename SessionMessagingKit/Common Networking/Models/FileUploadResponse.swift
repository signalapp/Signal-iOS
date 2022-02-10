// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

struct FileUploadResponse: Codable {
    enum CodingKeys: String, CodingKey {
        case fileId = "result"
    }
    
    public let fileId: UInt64
}
