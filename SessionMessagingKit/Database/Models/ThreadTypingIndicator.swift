// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

/// This record is created for an incoming typing indicator message
///
/// **Note:** Currently we only support typing indicator on contact thread (one-to-one), to support groups we would need
/// to change the structure of this table (since it’s primary key is the threadId)
public struct ThreadTypingIndicator: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "threadTypingIndicator" }
    internal static let threadForeignKey = ForeignKey([Columns.threadId], to: [SessionThread.Columns.id])
    private static let thread = belongsTo(SessionThread.self, using: threadForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case threadId
        case timestampMs
    }
    
    public let threadId: String
    public let timestampMs: Int64
    
    // MARK: - Relationships
         
    public var thread: QueryInterfaceRequest<SessionThread> {
        request(for: ThreadTypingIndicator.thread)
    }
}
