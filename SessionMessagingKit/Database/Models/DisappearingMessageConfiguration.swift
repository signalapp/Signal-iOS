// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct DisappearingMessagesConfiguration: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
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
    struct MessageInfo: Codable {
        public let senderName: String?
        public let isEnabled: Bool
        public let durationSeconds: TimeInterval
        
        var previewText: String {
            guard let senderName: String = senderName else {
                // Changed by this device or via synced transcript
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
                senderName,
                NSString.formatDurationSeconds(UInt32(floor(durationSeconds)), useShortFormat: false)
            )
        }
    }
    
    var durationString: String {
        NSString.formatDurationSeconds(UInt32(durationSeconds), useShortFormat: false)
    }
    
    func messageInfoString(with senderName: String?) -> String? {
        let messageInfo: MessageInfo = DisappearingMessagesConfiguration.MessageInfo(
            senderName: senderName,
            isEnabled: isEnabled,
            durationSeconds: durationSeconds
        )
        
        guard let messageInfoData: Data = try? JSONEncoder().encode(messageInfo) else { return nil }
        
        return String(data: messageInfoData, encoding: .utf8)
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

// TODO: Remove this when possible

@objc(SMKDisappearingMessagesConfiguration)
public class SMKDisappearingMessagesConfiguration: NSObject {
    @objc public static var maxDurationSeconds: UInt = UInt(DisappearingMessagesConfiguration.maxDurationSeconds)
    
    @objc public static var validDurationsSeconds: [UInt] = DisappearingMessagesConfiguration
        .validDurationsSeconds
        .map { UInt($0) }
    
    @objc(isEnabledFor:)
    public static func isEnabled(for threadId: String) -> Bool {
        return Storage.shared
            .read { db in
                try DisappearingMessagesConfiguration
                    .select(.isEnabled)
                    .filter(id: threadId)
                    .asRequest(of: Bool.self)
                    .fetchOne(db)
            }
            .defaulting(to: false)
    }
    
    @objc(durationIndexFor:)
    public static func durationIndex(for threadId: String) -> Int {
        let durationSeconds: TimeInterval = Storage.shared
            .read { db in
                try DisappearingMessagesConfiguration
                    .select(.durationSeconds)
                    .filter(id: threadId)
                    .asRequest(of: TimeInterval.self)
                    .fetchOne(db)
            }
            .defaulting(to: DisappearingMessagesConfiguration.defaultDuration)
        
        return DisappearingMessagesConfiguration.validDurationsSeconds
            .firstIndex(of: durationSeconds)
            .defaulting(to: 0)
    }
    
    @objc(durationStringFor:)
    public static func durationString(for index: Int) -> String {
        let durationSeconds: TimeInterval = (
            index >= 0 && index < DisappearingMessagesConfiguration.validDurationsSeconds.count ?
                DisappearingMessagesConfiguration.validDurationsSeconds[index] :
                DisappearingMessagesConfiguration.validDurationsSeconds[0]
        )
        
        return NSString.formatDurationSeconds(UInt32(durationSeconds), useShortFormat: false)
    }
    
    @objc(update:isEnabled:durationIndex:)
    public static func update(_ threadId: String, isEnabled: Bool, durationIndex: Int) {
        let durationSeconds: TimeInterval = (
            durationIndex >= 0 && durationIndex < DisappearingMessagesConfiguration.validDurationsSeconds.count ?
                DisappearingMessagesConfiguration.validDurationsSeconds[durationIndex] :
                DisappearingMessagesConfiguration.validDurationsSeconds[0]
        )
        
        Storage.shared.write { db in
            guard let thread: SessionThread = try SessionThread.fetchOne(db, id: threadId) else {
                return
            }
            
            let config: DisappearingMessagesConfiguration = try DisappearingMessagesConfiguration
                .fetchOne(db, id: threadId)
                .defaulting(to: DisappearingMessagesConfiguration.defaultWith(threadId))
                .with(
                    isEnabled: isEnabled,
                    durationSeconds: durationSeconds
                )
                .saved(db)
            
            let interaction: Interaction = try Interaction(
                threadId: threadId,
                authorId: getUserHexEncodedPublicKey(db),
                variant: .infoDisappearingMessagesUpdate,
                body: config.messageInfoString(with: nil),
                timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000))
            )
            .inserted(db)
            
            try MessageSender.send(
                db,
                message: ExpirationTimerUpdate(
                    syncTarget: nil,
                    duration: UInt32(floor(isEnabled ? durationSeconds : 0))
                ),
                interactionId: interaction.id,
                in: thread
            )
        }
    }
}
