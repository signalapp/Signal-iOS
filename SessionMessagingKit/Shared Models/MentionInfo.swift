// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import GRDB
import SessionUtilitiesKit

public struct MentionInfo: FetchableRecord, Decodable {
    fileprivate static let threadVariantKey: SQL = SQL(stringLiteral: CodingKeys.threadVariant.stringValue)
    fileprivate static let openGroupServerKey: SQL = SQL(stringLiteral: CodingKeys.openGroupServer.stringValue)
    fileprivate static let openGroupRoomTokenKey: SQL = SQL(stringLiteral: CodingKeys.openGroupRoomToken.stringValue)
    
    fileprivate static let profileString: String = CodingKeys.profile.stringValue
    
    public let profile: Profile
    public let threadVariant: SessionThread.Variant
    public let openGroupServer: String?
    public let openGroupRoomToken: String?
}

public extension MentionInfo {
    static func query(
        userPublicKey: String,
        threadId: String,
        threadVariant: SessionThread.Variant,
        targetPrefix: SessionId.Prefix,
        pattern: FTS5Pattern?
    ) -> AdaptedFetchRequest<SQLRequest<MentionInfo>>? {
        guard threadVariant != .contact || userPublicKey != threadId else { return nil }
        
        let profile: TypedTableAlias<Profile> = TypedTableAlias()
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        let openGroup: TypedTableAlias<OpenGroup> = TypedTableAlias()
        
        let prefixLiteral: SQL = SQL(stringLiteral: "\(targetPrefix.rawValue)%")
        let profileFullTextSearch: SQL = SQL(stringLiteral: Profile.fullTextSearchTableName)
        
        /// **Note:** The `\(MentionInfo.profileKey).*` value **MUST** be first
        let limitSQL: SQL? = (threadVariant == .openGroup ? SQL("LIMIT 20") : nil)
        
        let request: SQLRequest<MentionInfo> = {
            guard let pattern: FTS5Pattern = pattern else {
                let finalLimitSQL: SQL = (limitSQL ?? "")
                
                return """
                    SELECT
                        \(Profile.self).*,
                        MAX(\(interaction[.timestampMs])),  -- Want the newest interaction (for sorting)
                        \(SQL("\(threadVariant) AS \(MentionInfo.threadVariantKey)")),
                        \(openGroup[.server]) AS \(MentionInfo.openGroupServerKey),
                        \(openGroup[.roomToken]) AS \(MentionInfo.openGroupRoomTokenKey)
                    
                    FROM \(Profile.self)
                    JOIN \(Interaction.self) ON (
                        \(SQL("\(interaction[.threadId]) = \(threadId)")) AND
                        \(interaction[.authorId]) = \(profile[.id])
                    )
                    LEFT JOIN \(OpenGroup.self) ON \(SQL("\(openGroup[.threadId]) = \(threadId)"))
                
                    WHERE (
                        \(SQL("\(profile[.id]) != \(userPublicKey)")) AND (
                            \(SQL("\(threadVariant) != \(SessionThread.Variant.openGroup)")) OR
                            \(SQL("\(profile[.id]) LIKE '\(prefixLiteral)'"))
                        )
                    )
                    GROUP BY \(profile[.id])
                    ORDER BY \(interaction[.timestampMs].desc)
                    \(finalLimitSQL)
                """
            }
            
            // If we do have a search patern then use FTS
            let matchLiteral: SQL = SQL(stringLiteral: "\(Profile.Columns.nickname.name):\(pattern.rawPattern) OR \(Profile.Columns.name.name):\(pattern.rawPattern)")
            let finalLimitSQL: SQL = (limitSQL ?? "")
            
            return """
                SELECT
                    \(Profile.self).*,
                    MAX(\(interaction[.timestampMs])),  -- Want the newest interaction (for sorting)
                    \(SQL("\(threadVariant) AS \(MentionInfo.threadVariantKey)")),
                    \(openGroup[.server]) AS \(MentionInfo.openGroupServerKey),
                    \(openGroup[.roomToken]) AS \(MentionInfo.openGroupRoomTokenKey)
                
                FROM \(profileFullTextSearch)
                JOIN \(Profile.self) ON (
                    \(Profile.self).rowid = \(profileFullTextSearch).rowid AND
                    \(SQL("\(profile[.id]) != \(userPublicKey)")) AND (
                        \(SQL("\(threadVariant) != \(SessionThread.Variant.openGroup)")) OR
                        \(SQL("\(profile[.id]) LIKE '\(prefixLiteral)'"))
                    )
                )
                JOIN \(Interaction.self) ON (
                    \(SQL("\(interaction[.threadId]) = \(threadId)")) AND
                    \(interaction[.authorId]) = \(profile[.id])
                )
                LEFT JOIN \(OpenGroup.self) ON \(SQL("\(openGroup[.threadId]) = \(threadId)"))
            
                WHERE \(profileFullTextSearch) MATCH '\(matchLiteral)'
                GROUP BY \(profile[.id])
                ORDER BY \(interaction[.timestampMs].desc)
                \(finalLimitSQL)
            """
        }()
        
        return request.adapted { db in
            let adapters = try splittingRowAdapters(columnCounts: [
                Profile.numberOfSelectedColumns(db)
            ])
            
            return ScopeAdapter([
                MentionInfo.profileString: adapters[0]
            ])
        }
    }
}
