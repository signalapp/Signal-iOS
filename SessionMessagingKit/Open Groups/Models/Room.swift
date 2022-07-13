// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct Room: Codable, Equatable {
        enum CodingKeys: String, CodingKey {
            case token
            case name
            case roomDescription = "description"
            case infoUpdates = "info_updates"
            case messageSequence = "message_sequence"
            case created
            
            case activeUsers = "active_users"
            case activeUsersCutoff = "active_users_cutoff"
            case imageId = "image_id"
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
            case defaultAccessible = "default_accessible"
            case write
            case defaultWrite = "default_write"
            case upload
            case defaultUpload = "default_upload"
        }
        
        /// The room token as used in a URL, e.g. "sudoku"
        public let token: String
        
        /// The room name typically shown to users, e.g. "Sodoku Solvers"
        public let name: String
        
        /// Text description of the room, e.g. "All the best sodoku discussion!"
        public let roomDescription: String?
        
        /// Monotonic integer counter that increases whenever the room's metadata changes
        public let infoUpdates: Int64
        
        /// Monotonic room post counter that increases each time a message is posted, edited, or deleted in this room
        ///
        /// Note that changes to this field do not imply an update the room's info_updates value, nor vice versa
        public let messageSequence: Int64
        
        /// Unix timestamp (as a float) of the room creation time. Note that unlike earlier versions of SOGS, this is a proper
        /// seconds-since-epoch unix timestamp, not a javascript-style millisecond value
        public let created: TimeInterval
        
        /// Number of recently active users in the room over a recent time period (as given in the active_users_cutoff value)
        ///
        /// Users are considered "active" if they have accessed the room (checking for new messages, etc.) at least once in the given period
        ///
        /// **Note:** changes to this field do not update the room's info_updates value
        public let activeUsers: Int64
        
        /// The length of time (in seconds) of the active_users period. Defaults to a week (604800), but the open group administrator can configure it
        public let activeUsersCutoff: Int64
        
        /// File ID of an uploaded file containing the room's image
        ///
        /// Omitted if there is no image
        public let imageId: String?
        
        /// Array of pinned message information (omitted entirely if there are no pinned messages)
        public let pinnedMessages: [PinnedMessage]?
        
        /// This flag is `true` if the current user has admin permissions in the room
        public let admin: Bool
        
        /// This flag is `true` if the current user is a global admin
        ///
        /// This is not exclusive of `globalModerator`/`moderator`/`admin` (a global admin will have all four set to `true`)
        public let globalAdmin: Bool
        
        /// Array of Session IDs of the room's publicly viewable moderators
        ///
        /// This does not include room moderator nor hidden admins
        public let admins: [String]
        
        /// Array of Session IDs of the room's publicly hidden admins
        ///
        /// This field is only included if the requesting user has moderator or admin permissions, and is omitted if empty
        public let hiddenAdmins: [String]?
        
        /// This flag is `true` if the current user has moderator permissions in the room
        public let moderator: Bool
        
        /// This flag is `true` if the current user is a global moderator
        ///
        /// This is not exclusive of `moderator` (a global moderator will have both flags set to `true`)
        public let globalModerator: Bool
        
        /// Array of Session IDs of the room's publicly viewable moderators
        ///
        /// This does not include room administrators nor hidden moderators
        public let moderators: [String]
        
        /// Array of Session IDs of the room's publicly hidden moderators
        ///
        /// This field is only included if the requesting user has moderator or admin permissions, and is omitted if empty
        public let hiddenModerators: [String]?
        
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
    }
}

// MARK: - Decoding

extension OpenGroupAPI.Room {
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        // This logic is to future-proof the transition from int-based to string-based image ids
        let maybeImageId: String? = (
            ((try? container.decode(Int64.self, forKey: .imageId)).map { "\($0)" }) ??
            (try? container.decode(String.self, forKey: .imageId))
        )
        
        self = OpenGroupAPI.Room(
            token: try container.decode(String.self, forKey: .token),
            name: try container.decode(String.self, forKey: .name),
            roomDescription: try? container.decode(String.self, forKey: .roomDescription),
            infoUpdates: try container.decode(Int64.self, forKey: .infoUpdates),
            messageSequence: try container.decode(Int64.self, forKey: .messageSequence),
            created: try container.decode(TimeInterval.self, forKey: .created),
            
            activeUsers: try container.decode(Int64.self, forKey: .activeUsers),
            activeUsersCutoff: try container.decode(Int64.self, forKey: .activeUsersCutoff),
            imageId: maybeImageId,
            pinnedMessages: try? container.decode([OpenGroupAPI.PinnedMessage].self, forKey: .pinnedMessages),
            
            admin: ((try? container.decode(Bool.self, forKey: .admin)) ?? false),
            globalAdmin: ((try? container.decode(Bool.self, forKey: .globalAdmin)) ?? false),
            admins: try container.decode([String].self, forKey: .admins),
            hiddenAdmins: try? container.decode([String].self, forKey: .hiddenAdmins),
            
            moderator: ((try? container.decode(Bool.self, forKey: .moderator)) ?? false),
            globalModerator: ((try? container.decode(Bool.self, forKey: .globalModerator)) ?? false),
            moderators: try container.decode([String].self, forKey: .moderators),
            hiddenModerators: try? container.decode([String].self, forKey: .hiddenModerators),
            
            read: try container.decode(Bool.self, forKey: .read),
            defaultRead: try? container.decode(Bool.self, forKey: .defaultRead),
            defaultAccessible: try? container.decode(Bool.self, forKey: .defaultAccessible),
            write: try container.decode(Bool.self, forKey: .write),
            defaultWrite: try? container.decode(Bool.self, forKey: .defaultWrite),
            upload: try container.decode(Bool.self, forKey: .upload),
            defaultUpload: try? container.decode(Bool.self, forKey: .defaultUpload)
        )
    }
}
