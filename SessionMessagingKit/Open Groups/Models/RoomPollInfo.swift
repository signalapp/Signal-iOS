// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    /// This only contains ephemeral data
    public struct RoomPollInfo: Codable {
        enum CodingKeys: String, CodingKey {
            case token
            case activeUsers = "active_users"
            
            case admin
            case globalAdmin = "global_admin"
            
            case moderator
            case globalModerator = "global_moderator"
            
            case read
            case defaultRead = "default_read"
            case write
            case defaultWrite = "default_write"
            case upload
            case defaultUpload = "default_upload"
            
            case details
        }
        
        public let token: String?
        public let activeUsers: Int64?
        
        public let admin: Bool?
        public let globalAdmin: Bool?
        
        public let moderator: Bool?
        public let globalModerator: Bool?
        
        public let read: Bool?
        public let defaultRead: Bool?
        public let write: Bool?
        public let defaultWrite: Bool?
        public let upload: Bool?
        public let defaultUpload: Bool?
        
        /// Only populated and different if the `info_updates` counter differs from the provided `info_updated` value
        public let details: Room?
    }
}

// MARK: - Convenience

extension OpenGroupAPI.RoomPollInfo {
    init(room: OpenGroupAPI.Room) {
        self.init(
            token: room.token,
            activeUsers: room.activeUsers,
            admin: room.admin,
            globalAdmin: room.globalAdmin,
            moderator: room.moderator,
            globalModerator: room.globalModerator,
            read: room.read,
            defaultRead: room.defaultRead,
            write: room.write,
            defaultWrite: room.defaultWrite,
            upload: room.upload,
            defaultUpload: room.defaultUpload,
            details: nil
        )
    }
}
