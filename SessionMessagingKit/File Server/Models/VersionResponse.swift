// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension FileServerAPI {
    struct VersionResponse: Codable {
        enum CodingKeys: String, CodingKey {
            case version = "version"
        }
        
        public let version: String
    }
}
