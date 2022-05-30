// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

public class Environment {
    public static var shared: Environment!
    
    public let primaryStorage: OWSPrimaryStorage
    public let reachabilityManager: SSKReachabilityManager
    
    public let audioSession: OWSAudioSession
    public let preferences: OWSPreferences
    public let proximityMonitoringManager: OWSProximityMonitoringManager
    public let windowManager: OWSWindowManager
    public var isRequestingPermission: Bool
    
    // Note: This property is configured after Environment is created.
    public let notificationsManager: Atomic<NotificationsProtocol?> = Atomic(nil)
    
    public var isComplete: Bool {
        (notificationsManager.wrappedValue != nil)
    }
    
    public var objectReadWriteConnection: YapDatabaseConnection
    public var sessionStoreDBConnection: YapDatabaseConnection
    public var migrationDBConnection: YapDatabaseConnection
    public var analyticsDBConnection: YapDatabaseConnection
    
    // MARK: - Initialization
    
    public init(
        primaryStorage: OWSPrimaryStorage,
        reachabilityManager: SSKReachabilityManager,
        audioSession: OWSAudioSession,
        preferences: OWSPreferences,
        proximityMonitoringManager: OWSProximityMonitoringManager,
        windowManager: OWSWindowManager
    ) {
        self.primaryStorage = primaryStorage
        self.reachabilityManager = reachabilityManager
        self.audioSession = audioSession
        self.preferences = preferences
        self.proximityMonitoringManager = proximityMonitoringManager
        self.windowManager = windowManager
        self.isRequestingPermission = false
        
        self.objectReadWriteConnection = primaryStorage.newDatabaseConnection()
        self.sessionStoreDBConnection = primaryStorage.newDatabaseConnection()
        self.migrationDBConnection = primaryStorage.newDatabaseConnection()
        self.analyticsDBConnection = primaryStorage.newDatabaseConnection()
        
        if Environment.shared == nil {
            Environment.shared = self
        }
    }
    
    // MARK: - Functions
    
    public static func clearSharedForTests() {
        shared = nil
    }
}

// MARK: - Objective C Support

@objc(SMKEnvironment)
class SMKEnvironment: NSObject {
    @objc public static let shared: SMKEnvironment = SMKEnvironment()
    
    @objc public var primaryStorage: OWSPrimaryStorage { Environment.shared.primaryStorage }
    @objc public var audioSession: OWSAudioSession { Environment.shared.audioSession }
    @objc public var windowManager: OWSWindowManager { Environment.shared.windowManager }
    
    @objc public var isRequestingPermission: Bool { Environment.shared.isRequestingPermission }
}
