// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    /// This only contains ephemeral data
    public struct RoomPollInfo: Codable {
        enum CodingKeys: String, CodingKey {
            case token
            case created
            case name
            case description
            case imageId = "image_id"
            
            case infoUpdates = "info_updates"
            case messageSequence = "message_sequence"
            case activeUsers = "active_users"
            case activeUsersCutoff = "active_users_cutoff"
            case pinnedMessages = "pinned_messages"
            
            case admin
            case globalAdmin = "global_admin"
            case admins
            case hiddenAdmins = "hidden_admins"
            
            case moderator
            case globalModerator = "global_moderator"
            case moderators
            case hiddenModerators = "hidden_moderators"
            
            case read
            case defaultRead = "default_read"
            case write
            case defaultWrite = "default_write"
            case upload
            case defaultUpload = "default_upload"
            
            case details
        }
        
        public let token: String?
        public let created: TimeInterval?
        public let name: String?
        public let description: String?
        public let imageId: Int64?
        
        public let infoUpdates: Int64?
        public let messageSequence: Int64?
        public let activeUsers: Int64?
        public let activeUsersCutoff: Int64?
        public let pinnedMessages: [PinnedMessage]?
        
        public let admin: Bool?
        public let globalAdmin: Bool?
        public let admins: [String]?
        public let hiddenAdmins: [String]?
        
        public let moderator: Bool?
        public let globalModerator: Bool?
        public let moderators: [String]?
        public let hiddenModerators: [String]?
        
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
            created: room.created,
            name: room.name,
            description: room.description,
            imageId: room.imageId,
            infoUpdates: room.infoUpdates,
            messageSequence: room.messageSequence,
            activeUsers: room.activeUsers,
            activeUsersCutoff: room.activeUsersCutoff,
            pinnedMessages: room.pinnedMessages,
            admin: room.admin,
            globalAdmin: room.globalAdmin,
            admins: room.admins,
            hiddenAdmins: room.hiddenAdmins,
            moderator: room.moderator,
            globalModerator: room.globalModerator,
            moderators: room.moderators,
            hiddenModerators: room.hiddenModerators,
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
