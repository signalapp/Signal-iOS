// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct ClosedGroupKeyPair: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "closedGroupKeyPair" }
    internal static let closedGroupForeignKey = ForeignKey(
        [Columns.publicKey],
        to: [ClosedGroup.Columns.threadId]
    )
    private static let closedGroup = belongsTo(ClosedGroup.self, using: closedGroupForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case publicKey
        case secretKey
        case receivedTimestamp
    }
    
    public var id: String { publicKey }

    public let publicKey: String
    public let secretKey: Data
    public let receivedTimestamp: TimeInterval
    
    // MARK: - Relationships
    
    public var closedGroup: QueryInterfaceRequest<ClosedGroup> {
        request(for: ClosedGroupKeyPair.closedGroup)
    }
}
