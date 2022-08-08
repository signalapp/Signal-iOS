// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Reaction: Codable, Equatable, Hashable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "reaction" }
    internal static let profileForeignKey = ForeignKey([Columns.authorId], to: [Profile.Columns.id])
    internal static let interactionForeignKey = ForeignKey([Columns.interactionId], to: [Interaction.Columns.id])
    private static let profile = hasOne(Profile.self, using: profileForeignKey)
    internal static let interaction = belongsTo(Interaction.self, using: interactionForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case interactionId
        case serverHash
        case timestampMs
        case authorId
        case emoji
        case count
        case sortId
    }
    
    /// The id for the interaction this reaction belongs to
    public let interactionId: Int64
    
    /// The server hash for this reaction in the swarm
    ///
    /// **Note:** This value will be `null` for reactions in open groups
    public let serverHash: String?
    
    /// When the reaction was created in milliseconds since epoch
    public let timestampMs: Int64
    
    /// The id for the user who made this reaction
    public let authorId: String
    
    /// The emoji for this reaction
    public let emoji: String
    
    /// The number of times this emoji was used
    ///
    /// **Note:** This value will always be `1` for 1-1 messages and closed groups, but will be either `0` or
    /// the total number of emoji's used in open groups (this allows us to `SUM` this column to get the official total
    /// regardless of the type of conversation)
    public let count: Int64
    
    /// The first timestamp that an emoji is added
    public let sortId: Int64
    
    // MARK: - Relationships
         
    public var interaction: QueryInterfaceRequest<Interaction> {
        request(for: Reaction.interaction)
    }
    
    public var profile: QueryInterfaceRequest<Profile> {
        request(for: Reaction.profile)
    }
    
    // MARK: - Initialization
    
    public init(
        interactionId: Int64,
        serverHash: String?,
        timestampMs: Int64,
        authorId: String,
        emoji: String,
        count: Int64,
        sortId: Int64
    ) {
        self.interactionId = interactionId
        self.serverHash = serverHash
        self.timestampMs = timestampMs
        self.authorId = authorId
        self.emoji = emoji
        self.count = count
        self.sortId = sortId
    }
}

// MARK: - Mutation

public extension Reaction {
    func with(
        interactionId: Int64? = nil,
        serverHash: String? = nil,
        authorId: String? = nil,
        count: Int64? = nil,
        sortId: Int64? = nil
    ) -> Reaction {
        return Reaction(
            interactionId: (interactionId ?? self.interactionId),
            serverHash: (serverHash ?? self.serverHash),
            timestampMs: self.timestampMs,
            authorId: (authorId ?? self.authorId),
            emoji: self.emoji,
            count: (count ?? self.count),
            sortId: (sortId ?? self.sortId)
        )
    }
}

// MARK: - SortId

public extension Reaction {
    static func getSortId(
        _ db: Database,
        interactionId: Int64,
        emoji: String
    ) -> Int64 {
        if let existingSortId: Int64 = try? Reaction
            .select(Columns.sortId)
            .filter(Columns.interactionId == interactionId)
            .filter(Columns.emoji == emoji)
            .asRequest(of: Int64.self)
            .fetchOne(db)
        {
            return existingSortId
        }
        
        if let existingLargestSortId: Int64 = try? Reaction
            .select(max(Columns.sortId))
            .filter(Columns.interactionId == interactionId)
            .asRequest(of: Int64.self)
            .fetchOne(db)
        {
            return existingLargestSortId + 1
        }
        
        return 0
    }
}
