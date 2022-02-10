// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPIV2 {
    public struct RoomInfo: Codable {
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
