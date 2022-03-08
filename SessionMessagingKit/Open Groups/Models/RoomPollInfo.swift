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
            case defaultAccessible = "default_accessible"
            case write
            case defaultWrite = "default_write"
            case upload
            case defaultUpload = "default_upload"
            
            case details
        }
        
        /// The room token as used in a URL, e.g. "sudoku"
        public let token: String
        
        /// Number of recently active users in the room over a recent time period (as given in the active_users_cutoff value)
        ///
        /// Users are considered "active" if they have accessed the room (checking for new messages, etc.) at least once in the given period
        ///
        /// **Note:** changes to this field do not update the room's info_updates value
        public let activeUsers: Int64
        
        /// This flag is `true` if the current user has admin permissions in the room
        public let admin: Bool
        
        /// This flag is `true` if the current user is a global admin
        ///
        /// This is not exclusive of `globalModerator`/`moderator`/`admin` (a global admin will have all four set to `true`)
        public let globalAdmin: Bool
        
        /// This flag is `true` if the current user has moderator permissions in the room
        public let moderator: Bool
        
        /// This flag is `true` if the current user is a global moderator
        ///
        /// This is not exclusive of `moderator` (a global moderator will have both flags set to `true`)
        public let globalModerator: Bool
        
        ///  This flag indicates whether the **current** user has permission to read the room's messages
        ///
        /// **Note:** If this value is `false` the user only has access the room metadata
        public let read: Bool
        
        /// This field indicates whether new users have read permissions in the room
        ///
        /// It is included in the response only if the requesting user has moderator or admin permissions
        public let defaultRead: Bool?
        
        /// This field indicates whether new users have access permissions in the room
        ///
        /// It is included in the response only if the requesting user has moderator or admin permissions
        public let defaultAccessible: Bool?
        
        ///  This flag indicates whether the **current** user has permission to post messages in the room
        public let write: Bool
        
        /// This field indicates whether new users have write permissions in the room
        ///
        /// It is included in the response only if the requesting user has moderator or admin permissions
        public let defaultWrite: Bool?
        
        ///  This flag indicates whether the **current** user has permission to upload files to the room
        public let upload: Bool
        
        /// This field indicates whether new users have upload permissions in the room
        ///
        /// It is included in the response only if the requesting user has moderator or admin permissions
        public let defaultUpload: Bool?
        
        /// The full room metadata (as would be returned by the `/rooms/{roomToken}` endpoint)
        ///
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
            defaultAccessible: room.defaultAccessible,
            write: room.write,
            defaultWrite: room.defaultWrite,
            upload: room.upload,
            defaultUpload: room.defaultUpload,
            details: room
        )
    }
}

// MARK: - Decoding

extension OpenGroupAPI.RoomPollInfo {
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        self = OpenGroupAPI.RoomPollInfo(
            token: try container.decode(String.self, forKey: .token),
            activeUsers: try container.decode(Int64.self, forKey: .activeUsers),
            
            admin: ((try? container.decode(Bool.self, forKey: .admin)) ?? false),
            globalAdmin: ((try? container.decode(Bool.self, forKey: .globalAdmin)) ?? false),
            
            moderator: ((try? container.decode(Bool.self, forKey: .moderator)) ?? false),
            globalModerator: ((try? container.decode(Bool.self, forKey: .globalModerator)) ?? false),
            
            read: try container.decode(Bool.self, forKey: .read),
            defaultRead: try? container.decode(Bool.self, forKey: .defaultRead),
            defaultAccessible: try? container.decode(Bool.self, forKey: .defaultAccessible),
            write: try container.decode(Bool.self, forKey: .write),
            defaultWrite: try? container.decode(Bool.self, forKey: .defaultWrite),
            upload: try container.decode(Bool.self, forKey: .upload),
            defaultUpload: try? container.decode(Bool.self, forKey: .defaultUpload),
        
            details: try? container.decode(OpenGroupAPI.Room.self, forKey: .details)
        )
    }
}
