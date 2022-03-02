// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public enum Endpoint: Hashable {
        // Utility
        
        case onion
        case batch
        case sequence
        case capabilities
        
        // Rooms
        
        case rooms
        case room(String)
        case roomPollInfo(String, Int64)
        
        // Messages
        
        case roomMessage(String)
        case roomMessageIndividual(String, id: Int64)
        case roomMessagesRecent(String)
        case roomMessagesBefore(String, id: Int64)
        case roomMessagesSince(String, seqNo: Int64)
        
        // Pinning
        
        case roomPinMessage(String, id: Int64)
        case roomUnpinMessage(String, id: Int64)
        case roomUnpinAll(String)
        
        // Files
        
        case roomFile(String)
        case roomFileJson(String)
        case roomFileIndividual(String, Int64)
        case roomFileIndividualJson(String, Int64)
        
        // Inbox/Outbox (Message Requests)
        
        case inbox
        case inboxSince(id: Int64)
        case inboxFor(sessionId: String)
        
        case outbox
        case outboxSince(id: Int64)
        
        // Users
        
        case userBan(String)
        case userUnban(String)
        case userPermission(String)
        case userModerator(String)
        case userDeleteMessages(String)
        
        // Legacy endpoints (to be deprecated and removed)
        
        @available(*, deprecated, message: "Use v4 endpoint") case legacyFiles
        @available(*, deprecated, message: "Use v4 endpoint") case legacyFile(UInt64)
        
        @available(*, deprecated, message: "Use v4 endpoint") case legacyMessages
        @available(*, deprecated, message: "Use v4 endpoint") case legacyMessagesForServer(Int64)
        @available(*, deprecated, message: "Use v4 endpoint") case legacyDeletedMessages
        
        @available(*, deprecated, message: "Use v4 endpoint") case legacyModerators
        
        @available(*, deprecated, message: "Use v4 endpoint") case legacyBlockList
        @available(*, deprecated, message: "Use v4 endpoint") case legacyBlockListIndividual(String)
        @available(*, deprecated, message: "Use v4 endpoint") case legacyBanAndDeleteAll
        
        @available(*, deprecated, message: "Use v4 endpoint") case legacyCompactPoll(legacyAuth: Bool)
        @available(*, deprecated, message: "Use request signing") case legacyAuthToken(legacyAuth: Bool)
        @available(*, deprecated, message: "Use request signing") case legacyAuthTokenChallenge(legacyAuth: Bool)
        @available(*, deprecated, message: "Use request signing") case legacyAuthTokenClaim(legacyAuth: Bool)
        
        @available(*, deprecated, message: "Use v4 endpoint") case legacyRooms
        @available(*, deprecated, message: "Use v4 endpoint") case legacyRoomInfo(String)
        @available(*, deprecated, message: "Use v4 endpoint") case legacyRoomImage(String)
        @available(*, deprecated, message: "Use v4 endpoint") case legacyMemberCount(legacyAuth: Bool)
        
        var path: String {
            switch self {
                // Utility
                
                case .onion: return "oxen/v4/lsrpc"
                case .batch: return "batch"
                case .sequence: return "sequence"
                case .capabilities: return "capabilities"
                    
                // Rooms
                    
                case .rooms: return "rooms"
                case .room(let roomToken): return "room/\(roomToken)"
                case .roomPollInfo(let roomToken, let infoUpdated): return "room/\(roomToken)/pollInfo/\(infoUpdated)"
                    
                // Messages
                
                case .roomMessage(let roomToken):
                    return "room/\(roomToken)/message"
                    
                case .roomMessageIndividual(let roomToken, let messageId):
                    return "room/\(roomToken)/message/\(messageId)"
                
                case .roomMessagesRecent(let roomToken):
                    return "room/\(roomToken)/messages/recent"
                    
                case .roomMessagesBefore(let roomToken, let messageId):
                    return "room/\(roomToken)/messages/before/\(messageId)"
                    
                case .roomMessagesSince(let roomToken, let seqNo):
                    return "room/\(roomToken)/messages/since/\(seqNo)"
                    
                // Pinning
                    
                case .roomPinMessage(let roomToken, let messageId):
                    return "room/\(roomToken)/pin/\(messageId)"
                    
                case .roomUnpinMessage(let roomToken, let messageId):
                    return "room/\(roomToken)/unpin/\(messageId)"
                    
                case .roomUnpinAll(let roomToken):
                    return "room/\(roomToken)/unpin/all"
                    
                // Files
                
                case .roomFile(let roomToken): return "room/\(roomToken)/file"
                case .roomFileJson(let roomToken): return "room/\(roomToken)/fileJSON"
                case .roomFileIndividual(let roomToken, let fileId):
                    // Note: The 'fileName' value is ignored by the server and is only used to distinguish
                    // this from the 'Json' variant
                    let fileName: String = ""
                    return "room/\(roomToken)/file/\(fileId)/\(fileName)"
                    
                case .roomFileIndividualJson(let roomToken, let fileId):
                    return "room/\(roomToken)/file/\(fileId)"
                    
                // Inbox/Outbox (Message Requests)
    
                case .inbox: return "inbox"
                case .inboxSince(let id): return "inbox/since/\(id)"
                case .inboxFor(let sessionId): return "inbox/\(sessionId)"
                    
                case .outbox: return "outbox"
                case .outboxSince(let id): return "outbox/since/\(id)"
                
                // Users
                
                case .userBan(let sessionId): return "user/\(sessionId)/ban"
                case .userUnban(let sessionId): return "user/\(sessionId)/unban"
                case .userPermission(let sessionId): return "user/\(sessionId)/permission"
                case .userModerator(let sessionId): return "user/\(sessionId)/moderator"
                case .userDeleteMessages(let sessionId): return "user/\(sessionId)/deleteMessages"
                
                // Legacy endpoints (to be deprecated and removed)
                // TODO: Look for a nicer way to prepend 'legacy'? (OnionRequestAPI messes with this but the new auth needs it to be correct...)
                    
                    
                case .legacyFiles: return "legacy/files"
                case .legacyFile(let fileId): return "legacy/files/\(fileId)"
                
                case .legacyMessages: return "legacy/messages"
                case .legacyMessagesForServer(let serverId): return "legacy/messages/\(serverId)"
                case .legacyDeletedMessages: return "legacy/deleted_messages"
                    
                case .legacyModerators: return "legacy/moderators"
                    
                case .legacyBlockList: return "legacy/block_list"
                case .legacyBlockListIndividual(let publicKey): return "legacy/block_list/\(publicKey)"
                case .legacyBanAndDeleteAll: return "legacy/ban_and_delete_all"
                
                case .legacyCompactPoll(let useLegacyAuth):
                    return "\(useLegacyAuth ? "" : "legacy/")compact_poll"
                    
                case .legacyAuthToken(let useLegacyAuth):
                    return "\(useLegacyAuth ? "" : "legacy/")auth_token"
                    
                case .legacyAuthTokenChallenge(let useLegacyAuth):
                    return "\(useLegacyAuth ? "" : "legacy/")auth_token_challenge"
                    
                case .legacyAuthTokenClaim(let useLegacyAuth):
                    return "\(useLegacyAuth ? "" : "legacy/")claim_auth_token"
                    
                case .legacyRooms: return "legacy/rooms"
                case .legacyRoomInfo(let roomName): return "legacy/rooms/\(roomName)"
                case .legacyRoomImage(let roomName): return "legacy/rooms/\(roomName)/image"
                    
                case .legacyMemberCount(let useLegacyAuth):
                    return "\(useLegacyAuth ? "" : "legacy/")member_count"
            }
        }
        
        var useLegacyAuth: Bool {
            switch self {
                // File upload/download should use legacy auth
                case .legacyFiles, .legacyFile, .legacyMessages,
                    .legacyMessagesForServer, .legacyDeletedMessages,
                    .legacyModerators, .legacyBlockList,
                    .legacyBlockListIndividual, .legacyBanAndDeleteAll:
                    return true
                    
                case .legacyCompactPoll(let useLegacyAuth),
                    .legacyAuthToken(let useLegacyAuth),
                    .legacyAuthTokenChallenge(let useLegacyAuth),
                    .legacyAuthTokenClaim(let useLegacyAuth),
                    .legacyMemberCount(let useLegacyAuth):
                    return useLegacyAuth
                    
                case .legacyRooms, .legacyRoomInfo, .legacyRoomImage:
                    return true
                
                default: return false
            }
        }
    }
}
