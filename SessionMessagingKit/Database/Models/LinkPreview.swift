// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct LinkPreview: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "linkPreview" }
    internal static let interactionForeignKey = ForeignKey(
        [Columns.url],
        to: [Interaction.Columns.linkPreviewUrl]
    )
    internal static let interactions = hasMany(Interaction.self, using: Interaction.linkPreviewForeignKey)
    
    /// We want to cache url previews to the nearest 100,000 seconds (~28 hours - simpler than 86,400) to ensure the user isn't shown a preview that is too stale
    internal static let timstampResolution: Double = 100000
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case url
        case timestamp
        case variant
        case title
    }
    
    public enum Variant: Int, Codable, DatabaseValueConvertible {
        case standard
        case openGroupInvitation
    }
    
    /// The url for the link preview
    public let url: String
    
    /// The number of seconds since epoch rounded down to the nearest 100,000 seconds (~day) - This
    /// allows us to optimise against duplicate urls without having “stale” data last too long
    public let timestamp: TimeInterval
    
    /// The type of link preview
    public let variant: Variant
    
    /// The title for the link
    public let title: String?
}

// MARK: - Convenience

public extension LinkPreview {
    static func timestampFor(sentTimestampMs: Double) -> TimeInterval {
        // We want to round the timestamp down to the nearest 100,000 seconds (~28 hours - simpler than 86,400) to optimise
        // LinkPreview storage without having too stale data
        return (floor(sentTimestampMs / 1000 / LinkPreview.timstampResolution) * LinkPreview.timstampResolution)
    }
}
