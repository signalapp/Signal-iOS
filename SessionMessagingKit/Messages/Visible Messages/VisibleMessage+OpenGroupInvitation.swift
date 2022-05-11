// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public extension VisibleMessage {
    struct VMOpenGroupInvitation: Codable {
        public let name: String?
        public let url: String?
        
        // MARK: - Initialization

        public init(name: String, url: String) {
            self.name = name
            self.url = url
        }

        // MARK: - Proto Conversion

        public static func fromProto(_ proto: SNProtoDataMessageOpenGroupInvitation) -> VMOpenGroupInvitation? {
            return VMOpenGroupInvitation(
                name: proto.name,
                url: proto.url
            )
        }

        public func toProto() -> SNProtoDataMessageOpenGroupInvitation? {
            guard let url = url, let name = name else {
                SNLog("Couldn't construct open group invitation proto from: \(self).")
                return nil
            }
            let openGroupInvitationProto = SNProtoDataMessageOpenGroupInvitation.builder(url: url, name: name)
            do {
                return try openGroupInvitationProto.build()
            } catch {
                SNLog("Couldn't construct open group invitation proto from: \(self).")
                return nil
            }
        }
        
        // MARK: - Description
        
        public var description: String {
            """
            OpenGroupInvitation(
                name: \(name ?? "null"),
                url: \(url ?? "null")
            )
            """
        }
    }
}

// MARK: - Database Type Conversion

public extension VisibleMessage.VMOpenGroupInvitation {
    static func from(_ db: Database, linkPreview: LinkPreview) -> VisibleMessage.VMOpenGroupInvitation? {
        guard let name: String = linkPreview.title else { return nil }
        
        return VisibleMessage.VMOpenGroupInvitation(
            name: name,
            url: linkPreview.url
        )
    }
}
