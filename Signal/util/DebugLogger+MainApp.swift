//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension DebugLogger {

    func postLaunchLogCleanup(appContext: MainAppContext) {
        let shouldWipeLogs: Bool = {
            guard let lastLaunchVersion = AppVersionImpl.shared.lastCompletedLaunchMainAppVersion else {
                // This is probably a new version, but perhaps it's a really old version.
                return true
            }
            return AppVersionNumber(lastLaunchVersion) < AppVersionNumber("6.16.0.0")
        }()
        if shouldWipeLogs {
            wipeLogsAlways(appContext: appContext)
            Logger.warn("Wiped logs")
        }
    }

    func wipeLogsAlways(appContext: MainAppContext) {
        disableFileLogging()

        // Only the main app can wipe logs because only the main app can access its
        // own logs. (The main app can wipe logs for the other extensions.)
        for dirPath in Self.allLogsDirPaths {
            do {
                try FileManager.default.removeItem(atPath: dirPath)
            } catch {
                owsFailDebug("Failed to delete log directory: \(error)")
            }
        }

        enableFileLogging(appContext: appContext, canLaunchInBackground: true)
    }
}
