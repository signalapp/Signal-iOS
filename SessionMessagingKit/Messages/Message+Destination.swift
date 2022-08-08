// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public extension Message {
    enum Destination: Codable {
        case contact(publicKey: String)
        case closedGroup(groupPublicKey: String)
        case openGroup(
            roomToken: String,
            server: String,
            whisperTo: String? = nil,
            whisperMods: Bool = false,
            fileIds: [String]? = nil
        )
        case openGroupInbox(server: String, openGroupPublicKey: String, blindedPublicKey: String)

        static func from(
            _ db: Database,
            thread: SessionThread,
            fileIds: [String]? = nil
        ) throws -> Message.Destination {
            switch thread.variant {
                case .contact:
                    if SessionId.Prefix(from: thread.id) == .blinded {
                        guard let lookup: BlindedIdLookup = try? BlindedIdLookup.fetchOne(db, id: thread.id) else {
                            preconditionFailure("Attempting to send message to blinded id without the Open Group information")
                        }
                        
                        return .openGroupInbox(
                            server: lookup.openGroupServer,
                            openGroupPublicKey: lookup.openGroupPublicKey,
                            blindedPublicKey: thread.id
                        )
                    }
                    
                    return .contact(publicKey: thread.id)
                
                case .closedGroup:
                    return .closedGroup(groupPublicKey: thread.id)
                
                case .openGroup:
                    guard let openGroup: OpenGroup = try thread.openGroup.fetchOne(db) else {
                        throw StorageError.objectNotFound
                    }
                    
                    return .openGroup(roomToken: openGroup.roomToken, server: openGroup.server, fileIds: fileIds)
            }
        }
        
        func with(fileIds: [String]) -> Message.Destination {
            // Only Open Group messages support receiving the 'fileIds'
            switch self {
                case .openGroup(let roomToken, let server, let whisperTo, let whisperMods, _):
                    return .openGroup(
                        roomToken: roomToken,
                        server: server,
                        whisperTo: whisperTo,
                        whisperMods: whisperMods,
                        fileIds: fileIds
                    )
                    
                default: return self
            }
        }
    }
}
