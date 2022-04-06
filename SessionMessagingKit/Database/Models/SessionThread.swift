// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct SessionThread: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "thread" }
    static let disappearingMessagesConfiguration = hasOne(DisappearingMessagesConfiguration.self)
    static let closedGroup = hasOne(ClosedGroup.self)
    static let openGroup = hasOne(OpenGroup.self)
    
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
        case all
        case none
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
    
    public var disappearingMessagesConfiguration: QueryInterfaceRequest<DisappearingMessagesConfiguration> {
        request(for: SessionThread.disappearingMessagesConfiguration)
    }
    
//    public var lastInteraction
    
    public var closedGroup: QueryInterfaceRequest<ClosedGroup> {
        request(for: SessionThread.closedGroup)
    }
    
    public var openGroup: QueryInterfaceRequest<OpenGroup> {
        request(for: SessionThread.openGroup)
    }
}
