// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPIV2 {
    public struct Room: Codable {
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
        }
        
        public let token: String
        public let created: TimeInterval
        public let name: String
        public let description: String?
        public let imageId: Int64?
        
        public let infoUpdates: Int64
        public let messageSequence: Int64
        public let activeUsers: Int64
        public let activeUsersCutoff: Int64
        public let pinnedMessages: [PinnedMessage]?
        
        public let admin: Bool
        public let globalAdmin: Bool
        public let admins: [String]
        public let hiddenAdmins: [String]?
        
        public let moderator: Bool
        public let globalModerator: Bool
        public let moderators: [String]
        public let hiddenModerators: [String]?
        
        public let read: Bool
        public let defaultRead: Bool
        public let write: Bool
        public let defaultWrite: Bool
        public let upload: Bool
        public let defaultUpload: Bool
    }
}

// MARK: - Decoding

extension OpenGroupAPIV2.Room {
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        self = OpenGroupAPIV2.Room(
            token: try container.decode(String.self, forKey: .token),
            created: try container.decode(TimeInterval.self, forKey: .created),
            name: try container.decode(String.self, forKey: .name),
            description: try? container.decode(String.self, forKey: .description),
            imageId: try? container.decode(Int64.self, forKey: .imageId),
            
            infoUpdates: try container.decode(Int64.self, forKey: .infoUpdates),
            messageSequence: try container.decode(Int64.self, forKey: .messageSequence),
            activeUsers: try container.decode(Int64.self, forKey: .activeUsers),
            activeUsersCutoff: try container.decode(Int64.self, forKey: .activeUsersCutoff),
            pinnedMessages: try? container.decode([OpenGroupAPIV2.PinnedMessage].self, forKey: .pinnedMessages),
            
            admin: ((try? container.decode(Bool.self, forKey: .admin)) ?? false),
            globalAdmin: ((try? container.decode(Bool.self, forKey: .globalAdmin)) ?? false),
            admins: try container.decode([String].self, forKey: .admins),
            hiddenAdmins: try? container.decode([String].self, forKey: .hiddenAdmins),
            
            moderator: ((try? container.decode(Bool.self, forKey: .moderator)) ?? false),
            globalModerator: ((try? container.decode(Bool.self, forKey: .globalModerator)) ?? false),
            moderators: try container.decode([String].self, forKey: .moderators),
            hiddenModerators: try? container.decode([String].self, forKey: .hiddenModerators),
            
            read: try container.decode(Bool.self, forKey: .read),
            defaultRead: ((try? container.decode(Bool.self, forKey: .defaultRead)) ?? false),
            write: try container.decode(Bool.self, forKey: .write),
            defaultWrite: ((try? container.decode(Bool.self, forKey: .defaultWrite)) ?? false),
            upload: try container.decode(Bool.self, forKey: .upload),
            defaultUpload: ((try? container.decode(Bool.self, forKey: .defaultUpload)) ?? false)
        )
    }
}

