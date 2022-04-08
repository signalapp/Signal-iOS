// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct SessionThread: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "thread" }
    private static let closedGroup = hasOne(ClosedGroup.self, using: ClosedGroup.threadForeignKey)
    private static let openGroup = hasOne(OpenGroup.self, using: OpenGroup.threadForeignKey)
    private static let disappearingMessagesConfiguration = hasOne(
        DisappearingMessagesConfiguration.self,
        using: DisappearingMessagesConfiguration.threadForeignKey
    )
    private static let interactions = hasMany(Interaction.self, using: Interaction.threadForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case variant
        case creationDateTimestamp
        case shouldBeVisible
        case isPinned
        case messageDraft
        case notificationMode
        case mutedUntilTimestamp
    }
    
    public enum Variant: Int, Codable, DatabaseValueConvertible {
        case contact
        case closedGroup
        case openGroup
    }
    
    public enum NotificationMode: Int, Codable, DatabaseValueConvertible {
        case none
        case all
        case mentionsOnly   // Only applicable to group threads
    }

    public let id: String
    public let variant: Variant
    public let creationDateTimestamp: TimeInterval
    public let shouldBeVisible: Bool
    public let isPinned: Bool
    public let messageDraft: String?
    public let notificationMode: NotificationMode
    public let mutedUntilTimestamp: TimeInterval?
    
    // MARK: - Relationships
    
    public var closedGroup: QueryInterfaceRequest<ClosedGroup> {
        request(for: SessionThread.closedGroup)
    }
    
    public var openGroup: QueryInterfaceRequest<OpenGroup> {
        request(for: SessionThread.openGroup)
    }
    
    public var disappearingMessagesConfiguration: QueryInterfaceRequest<DisappearingMessagesConfiguration> {
        request(for: SessionThread.disappearingMessagesConfiguration)
    }
    
    public var interactions: QueryInterfaceRequest<Interaction> {
        request(for: SessionThread.interactions)
    }
    
}
