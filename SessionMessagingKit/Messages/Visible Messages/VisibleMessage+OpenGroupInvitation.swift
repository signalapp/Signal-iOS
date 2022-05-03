// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public extension VisibleMessage {
    struct OpenGroupInvitation: Codable {
        public let name: String?
        public let url: String?

        public init(name: String, url: String) {
            self.name = name
            self.url = url
        }

        // MARK: - Proto Conversion

        public static func fromProto(_ proto: SNProtoDataMessageOpenGroupInvitation) -> OpenGroupInvitation? {
            let url = proto.url
            let name = proto.name
            return OpenGroupInvitation(name: name, url: url)
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

public extension VisibleMessage.OpenGroupInvitation {
    static func from(_ db: Database, linkPreview: LinkPreview) -> VisibleMessage.OpenGroupInvitation? {
        guard let name: String = linkPreview.title else { return nil }
        
        return VisibleMessage.OpenGroupInvitation(
            name: name,
            url: linkPreview.url
        )
    }
}
