// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Capability: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "capability" }
    internal static let openGroupForeignKey = ForeignKey([Columns.openGroupId], to: [OpenGroup.Columns.threadId])
    private static let openGroup = belongsTo(OpenGroup.self, using: openGroupForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case openGroupId
        case capability
        case isMissing
    }
    
    public let openGroupId: String
    public let capability: String
    public let isMissing: Bool
    
    // MARK: - Relationships
         
    public var openGroup: QueryInterfaceRequest<OpenGroup> {
        request(for: Capability.openGroup)
    }
}
