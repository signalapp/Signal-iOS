// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct DisappearingMessagesConfiguration: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "disappearingMessagesConfiguration" }
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case isEnabled
        case durationSeconds
    }

    public let id: String
    public let isEnabled: Bool
    public let durationSeconds: TimeInterval
}

// MARK: - Convenience

extension DisappearingMessagesConfiguration {
    public var durationIndex: Int {
        return DisappearingMessagesConfiguration.validDurationsSeconds
            .firstIndex(of: durationSeconds)
            .defaulting(to: 0)
    }
    
    public var durationString: String {
        NSString.formatDurationSeconds(UInt32(durationSeconds), useShortFormat: false)
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
