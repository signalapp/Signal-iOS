// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionMessagingKit
import SessionUtilitiesKit
import UIKit

public enum AppSetup {
    private static var hasRun: Bool = false
    
    public static func setupEnvironment(
        appSpecificBlock: @escaping () -> (),
        migrationProgressChanged: ((CGFloat, TimeInterval) -> ())? = nil,
        migrationsCompletion: @escaping (Bool, Bool) -> ()
    ) {
        guard !AppSetup.hasRun else { return }
        
        AppSetup.hasRun = true
        
        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(labelStr: #function)
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Order matters here.
            //
            // All of these "singletons" should have any dependencies used in their
            // initializers injected.
            OWSBackgroundTaskManager.shared().observeNotifications()
            
            // AFNetworking (via CFNetworking) spools it's attachments to NSTemporaryDirectory().
            // If you receive a media message while the device is locked, the download will fail if
            // the temporary directory is NSFileProtectionComplete
            let success: Bool = OWSFileSystem.protectFileOrFolder(
                atPath: NSTemporaryDirectory(),
                fileProtectionType: .completeUntilFirstUserAuthentication
            )
            assert(success)

            Environment.shared = Environment(
                reachabilityManager: SSKReachabilityManagerImpl(),
                audioSession: OWSAudioSession(),
                proximityMonitoringManager: OWSProximityMonitoringManagerImpl(),
                windowManager: OWSWindowManager(default: ())
            )
            appSpecificBlock()
            
            /// `performMainSetup` **MUST** run before `perform(migrations:)`
            Configuration.performMainSetup()
            GRDBStorage.shared.perform(
                migrations: [
                    SNUtilitiesKit.migrations(),
                    SNSnodeKit.migrations(),
                    SNMessagingKit.migrations()
                ],
                onProgressUpdate: migrationProgressChanged,
                onComplete: { success, needsConfigSync in
                    DispatchQueue.main.async {
                        migrationsCompletion(success, needsConfigSync)
                        
                        // The 'if' is only there to prevent the "variable never read" warning from showing
                        if backgroundTask != nil { backgroundTask = nil }
                    }
                }
            )
        }
    }
}
