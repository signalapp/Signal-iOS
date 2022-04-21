// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public extension Message {
    enum Destination: Codable {
        case contact(publicKey: String)
        case closedGroup(groupPublicKey: String)
        case openGroup(channel: UInt64, server: String)
        case openGroupV2(room: String, server: String)

        static func from(_ db: Database, thread: SessionThread) throws -> Message.Destination {
            switch thread.variant {
                case .contact: return .contact(publicKey: thread.id)
                case .closedGroup: return .closedGroup(groupPublicKey: thread.id)
                case .openGroup:
                    guard let openGroup: OpenGroup = try thread.openGroup.fetchOne(db) else {
                        throw GRDBStorageError.objectNotFound
                    }
                    
                    return .openGroupV2(room: openGroup.room, server: openGroup.server)
            }
        }
    }
}
