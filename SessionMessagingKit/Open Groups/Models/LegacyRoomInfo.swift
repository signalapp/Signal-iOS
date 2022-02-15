// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct LegacyRoomInfo: Codable {
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case imageID = "image_id"
        }
        
        public let id: String
        public let name: String
        public let imageID: String?
    }
}
