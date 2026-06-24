//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Represents a Release Note that this client has already fetched and processed.
public class StoredReleaseNote: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "StoredReleaseNote"

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case uniqueId
        case interactionId
        case ctaId
        case ctaText
    }

    public var uniqueId: String

    // interactionId can be nil for blocked thread, which doesn't store a TSInteraction
    public var interactionId: Int64?

    public var ctaId: String?
    public var ctaText: String?

    public init(uniqueId: String, interactionId: Int64?, ctaId: String?, ctaText: String?) {
        self.uniqueId = uniqueId
        self.interactionId = interactionId
        self.ctaId = ctaId
        self.ctaText = ctaText
    }

    public static let persistenceConflictPolicy: PersistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .ignore,
    )

    // MARK: - Codable

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
        interactionId = try container.decodeIfPresent(Int64.self, forKey: .interactionId)
        ctaId = try container.decodeIfPresent(String.self, forKey: .ctaId)
        ctaText = try container.decodeIfPresent(String.self, forKey: .ctaText)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encodeIfPresent(interactionId, forKey: .interactionId)
        try container.encodeIfPresent(ctaId, forKey: .ctaId)
        try container.encodeIfPresent(ctaText, forKey: .ctaText)
    }
}
