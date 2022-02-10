// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

enum Endpoint {
    case files
    case file(UInt64)
    
    case messages
    case messagesForServer(Int64)
    case deletedMessages
    
    case moderators
    
    case blockList
    case blockListIndividual(String)
    case banAndDeleteAll
    
    case rooms
    case roomInfo(String)
    case roomImage(String)
    
    // Legacy endpoints (to be deprecated and removed)
    case legacyCompactPoll(legacyAuth: Bool)
    case legacyAuthToken(legacyAuth: Bool)
    case legacyAuthTokenChallenge(legacyAuth: Bool)
    case legacyAuthTokenClaim(legacyAuth: Bool)
    case legacyMemberCount(legacyAuth: Bool)
    
    var path: String {
        switch self {
            case .files: return "files"
            case .file(let fileId): return "files/\(fileId)"
            
            case .messages: return "messages"
            case .messagesForServer(let serverId): return "messages/\(serverId)"
            case .deletedMessages: return "deleted_messages"
                
            case .moderators: return "moderators"
                
            case .blockList: return "block_list"
            case .blockListIndividual(let publicKey): return "block_list/\(publicKey)"
            case .banAndDeleteAll: return "ban_and_delete_all"
                
            case .rooms: return "rooms"
            case .roomInfo(let roomName): return "rooms/\(roomName)"
            case .roomImage(let roomName): return "rooms/\(roomName)/image"
            
            // Legacy endpoints (to be deprecated and removed)
            // TODO: Look for a nicer way to prepend 'legacy'? (OnionRequestAPI messes with this but the new auth needs it to be correct...)
            case .legacyCompactPoll(let useLegacyAuth):
                return "\(useLegacyAuth ? "" : "legacy/")compact_poll"
                
            case .legacyAuthToken(let useLegacyAuth):
                return "\(useLegacyAuth ? "" : "legacy/")auth_token"
                
            case .legacyAuthTokenChallenge(let useLegacyAuth):
                return "\(useLegacyAuth ? "" : "legacy/")auth_token_challenge"
                
            case .legacyAuthTokenClaim(let useLegacyAuth):
                return "\(useLegacyAuth ? "" : "legacy/")claim_auth_token"
                
            case .legacyMemberCount(let useLegacyAuth):
                return "\(useLegacyAuth ? "" : "legacy/")member_count"
        }
    }
    
    var useLegacyAuth: Bool {
        switch self {
            // File upload/download should use legacy auth
            case .files, .file: return true
                
            case .legacyCompactPoll(let useLegacyAuth),
                .legacyAuthToken(let useLegacyAuth),
                .legacyAuthTokenChallenge(let useLegacyAuth),
                .legacyAuthTokenClaim(let useLegacyAuth),
                .legacyMemberCount(let useLegacyAuth):
                return useLegacyAuth
            
            default: return false
        }
    }
}
