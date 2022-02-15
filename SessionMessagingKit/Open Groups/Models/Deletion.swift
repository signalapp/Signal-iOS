// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct Deletion: Codable {
        enum CodingKeys: String, CodingKey {
            case id
            case deletedMessageID = "deleted_message_id"
        }
        
        let id: Int64
        let deletedMessageID: Int64
        
        public static func from(_ json: JSON) -> Deletion? {
            guard let id = json["id"] as? Int64, let deletedMessageID = json["deleted_message_id"] as? Int64 else {
                return nil
            }
            
            return Deletion(id: id, deletedMessageID: deletedMessageID)
        }
    }
}
