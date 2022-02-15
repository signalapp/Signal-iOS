// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct FileResponse: Codable {
        enum CodingKeys: String, CodingKey {
            case fileName = "filename"
            case size
            case uploaded
            case expires
        }
        
        let fileName: String?
        let size: Int64
        let uploaded: TimeInterval
        let expires: TimeInterval?
    }
}
