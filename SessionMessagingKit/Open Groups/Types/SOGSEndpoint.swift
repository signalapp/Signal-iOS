// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public enum Endpoint: EndpointType {
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
        case roomDeleteMessages(String, sessionId: String)
        
        // Reactions
        
        case reactionDelete(String, id: Int64, emoji: String)
        case reaction(String, id: Int64, emoji: String)
        case reactors(String, id: Int64, emoji: String)
        
        // Pinning
        
        case roomPinMessage(String, id: Int64)
        case roomUnpinMessage(String, id: Int64)
        case roomUnpinAll(String)
        
        // Files
        
        case roomFile(String)
        case roomFileIndividual(String, String)
        
        // Inbox/Outbox (Message Requests)
        
        case inbox
        case inboxSince(id: Int64)
        case inboxFor(sessionId: String)
        
        case outbox
        case outboxSince(id: Int64)
        
        // Users
        
        case userBan(String)
        case userUnban(String)
        case userModerator(String)
        
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
                    
                case .roomDeleteMessages(let roomToken, let sessionId):
                    return "room/\(roomToken)/all/\(sessionId)"
                
                // Reactions
                
                case .reactionDelete(let roomToken, let messageId, let emoji):
                    return "room/\(roomToken)/reactions/\(messageId)/\(emoji)"
                
                case .reaction(let roomToken, let messageId, let emoji):
                    return "room/\(roomToken)/reaction/\(messageId)/\(emoji)"
                
                case .reactors(let roomToken, let messageId, let emoji):
                    return "room/\(roomToken)/reactors/\(messageId)/\(emoji)"
                    
                // Pinning
                    
                case .roomPinMessage(let roomToken, let messageId):
                    return "room/\(roomToken)/pin/\(messageId)"
                    
                case .roomUnpinMessage(let roomToken, let messageId):
                    return "room/\(roomToken)/unpin/\(messageId)"
                    
                case .roomUnpinAll(let roomToken):
                    return "room/\(roomToken)/unpin/all"
                    
                // Files
                
                case .roomFile(let roomToken): return "room/\(roomToken)/file"
                case .roomFileIndividual(let roomToken, let fileId): return "room/\(roomToken)/file/\(fileId)"
                    
                // Inbox/Outbox (Message Requests)
    
                case .inbox: return "inbox"
                case .inboxSince(let id): return "inbox/since/\(id)"
                case .inboxFor(let sessionId): return "inbox/\(sessionId)"
                    
                case .outbox: return "outbox"
                case .outboxSince(let id): return "outbox/since/\(id)"
                
                // Users
                
                case .userBan(let sessionId): return "user/\(sessionId)/ban"
                case .userUnban(let sessionId): return "user/\(sessionId)/unban"
                case .userModerator(let sessionId): return "user/\(sessionId)/moderator"
            }
        }
    }
}
