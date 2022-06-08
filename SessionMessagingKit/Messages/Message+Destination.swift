// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public extension Message {
    enum Destination: Codable {
        case contact(publicKey: String)
        case closedGroup(groupPublicKey: String)
        case legacyOpenGroup(channel: UInt64, server: String)
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
                    if SessionId.Prefix(from: thread.contactSessionID()) == .blinded {
                        guard let server: String = thread.originalOpenGroupServer, let publicKey: String = thread.originalOpenGroupPublicKey else {
                            preconditionFailure("Attempting to send message to blinded id without the Open Group information")
                        }
                        
                        return .openGroupInbox(
                            server: server,
                            openGroupPublicKey: publicKey,
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
                    
                    return .openGroup(roomToken: openGroup.room, server: openGroup.server, fileIds: fileIds)
            }
        }
    }
}
