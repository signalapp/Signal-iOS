// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct DisappearingMessagesConfiguration: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "disappearingMessagesConfiguration" }
    internal static let threadForeignKey = ForeignKey([Columns.threadId], to: [SessionThread.Columns.id])
    private static let thread = belongsTo(SessionThread.self, using: threadForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case threadId
        case isEnabled
        case durationSeconds
    }
    
    public var id: String { threadId }  // Identifiable

    public let threadId: String
    public let isEnabled: Bool
    public let durationSeconds: TimeInterval
    
    // MARK: - Relationships
    
    public var thread: QueryInterfaceRequest<SessionThread> {
        request(for: DisappearingMessagesConfiguration.thread)
    }
}

// MARK: - Mutation

public extension DisappearingMessagesConfiguration {
    static let defaultDuration: TimeInterval = (24 * 60 * 60)
    
    static func defaultWith(_ threadId: String) -> DisappearingMessagesConfiguration {
        return DisappearingMessagesConfiguration(
            threadId: threadId,
            isEnabled: false,
            durationSeconds: defaultDuration
        )
    }
    
    func with(
        isEnabled: Bool? = nil,
        durationSeconds: TimeInterval? = nil
    ) -> DisappearingMessagesConfiguration {
        return DisappearingMessagesConfiguration(
            threadId: threadId,
            isEnabled: (isEnabled ?? self.isEnabled),
            durationSeconds: (durationSeconds ?? self.durationSeconds)
        )
    }
}

// MARK: - Convenience

public extension DisappearingMessagesConfiguration {
    var durationIndex: Int {
        return DisappearingMessagesConfiguration.validDurationsSeconds
            .firstIndex(of: durationSeconds)
            .defaulting(to: 0)
    }
    
    var durationString: String {
        NSString.formatDurationSeconds(UInt32(durationSeconds), useShortFormat: false)
    }
    
    func infoUpdateMessage(with senderName: String?) -> String {
        guard let senderName: String = senderName else {
            // Changed by localNumber on this device or via synced transcript
            guard isEnabled, durationSeconds > 0 else { return "YOU_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION".localized() }
            
            return String(
                format: "YOU_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION".localized(),
                NSString.formatDurationSeconds(UInt32(floor(durationSeconds)), useShortFormat: false)
            )
        }
        
        guard isEnabled, durationSeconds > 0 else {
            return String(format: "OTHER_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION".localized(), senderName)
        }
        
        return String(
            format: "OTHER_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION".localized(),
            NSString.formatDurationSeconds(UInt32(floor(durationSeconds)), useShortFormat: false),
            senderName
        )
    }
}

// MARK: - UI Constraints

extension DisappearingMessagesConfiguration {
    public static var validDurationsSeconds: [TimeInterval] {
        return [
            5,
            10,
            30,
            (1 * 60),
            (5 * 60),
            (30 * 60),
            (1 * 60 * 60),
            (6 * 60 * 60),
            (12 * 60 * 60),
            (24 * 60 * 60),
            (7 * 24 * 60 * 60)
        ]
    }
    
    public static var maxDurationSeconds: TimeInterval = {
        return (validDurationsSeconds.max() ?? 0)
    }()
}

// MARK: - Objective-C Support
@objc(SMKDisappearingMessagesConfiguration)
public class SMKDisappearingMessagesConfiguration: NSObject {
    @objc public static var maxDurationSeconds: UInt = UInt(DisappearingMessagesConfiguration.maxDurationSeconds)
}
