// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension FileServerAPIV2 {
    struct VersionResponse: Codable {
        enum CodingKeys: String, CodingKey {
            case version = "version"
        }
        
        public let version: String
    }
}
