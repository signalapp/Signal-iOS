// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct ClosedGroupKeyPair: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "closedGroupKeyPair" }
    internal static let closedGroupForeignKey = ForeignKey(
        [Columns.threadId],
        to: [ClosedGroup.Columns.threadId]
    )
    private static let closedGroup = belongsTo(ClosedGroup.self, using: closedGroupForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case threadId
        case publicKey
        case secretKey
        case receivedTimestamp
    }
    
    public let threadId: String
    public let publicKey: Data
    public let secretKey: Data
    public let receivedTimestamp: TimeInterval
    
    // MARK: - Relationships
    
    public var closedGroup: QueryInterfaceRequest<ClosedGroup> {
        request(for: ClosedGroupKeyPair.closedGroup)
    }
    
    // MARK: - Initialization
    
    public init(
        threadId: String,
        publicKey: Data,
        secretKey: Data,
        receivedTimestamp: TimeInterval
    ) {
        self.threadId = threadId
        self.publicKey = publicKey
        self.secretKey = secretKey
        self.receivedTimestamp = receivedTimestamp
    }
}

// MARK: - GRDB Interactions

public extension ClosedGroupKeyPair {
    static func fetchLatestKeyPair(_ db: Database, threadId: String) throws -> ClosedGroupKeyPair? {
        return try ClosedGroupKeyPair
            .filter(Columns.threadId == threadId)
            .order(Columns.receivedTimestamp.desc)
            .fetchOne(db)
    }
}
