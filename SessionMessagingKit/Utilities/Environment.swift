// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

public class Environment {
    public static var shared: Environment?
    
    public let reachabilityManager: SSKReachabilityManager
    
    public let audioSession: OWSAudioSession
    public let proximityMonitoringManager: OWSProximityMonitoringManager
    public let windowManager: OWSWindowManager
    public var isRequestingPermission: Bool
    
    // Note: This property is configured after Environment is created.
    public let callManager: Atomic<CallManagerProtocol?> = Atomic(nil)
    
    // Note: This property is configured after Environment is created.
    public let notificationsManager: Atomic<NotificationsProtocol?> = Atomic(nil)
    
    public var isComplete: Bool {
        (notificationsManager.wrappedValue != nil)
    }
    
    // MARK: - Initialization
    
    public init(
        reachabilityManager: SSKReachabilityManager,
        audioSession: OWSAudioSession,
        proximityMonitoringManager: OWSProximityMonitoringManager,
        windowManager: OWSWindowManager
    ) {
        self.reachabilityManager = reachabilityManager
        self.audioSession = audioSession
        self.proximityMonitoringManager = proximityMonitoringManager
        self.windowManager = windowManager
        self.isRequestingPermission = false
        
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
public class SMKEnvironment: NSObject {
    @objc public static let shared: SMKEnvironment = SMKEnvironment()
    
    @objc public var audioSession: OWSAudioSession? { Environment.shared?.audioSession }
    @objc public var windowManager: OWSWindowManager? { Environment.shared?.windowManager }
    
    @objc public var isRequestingPermission: Bool { (Environment.shared?.isRequestingPermission == true) }
}
