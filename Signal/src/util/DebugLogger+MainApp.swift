//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension DebugLogger {

    func postLaunchLogCleanup(appContext: MainAppContext) {
        // This must be a 3-part version number.
        let shouldWipeLogs: Bool = {
            guard let lastLaunchVersion = AppVersionImpl.shared.lastCompletedLaunchMainAppVersion else {
                // This is probably a new version, but perhaps it's a really old version.
                return true
            }
            let firstValidVersion = "6.16.0"
            return AppVersionImpl.shared.compare(lastLaunchVersion, with: firstValidVersion) == .orderedAscending
        }()
        if shouldWipeLogs {
            wipeLogsAlways(appContext: appContext)
            Logger.warn("Wiped logs")
        }
    }

    func wipeLogsIfDisabled(appContext: MainAppContext) {
        guard !Preferences.isLoggingEnabled else { return }

        wipeLogsAlways(appContext: appContext)
    }

    func wipeLogsAlways(appContext: MainAppContext) {
        let shouldReEnable = fileLogger != nil
        disableFileLogging()

        // Only the main app can wipe logs because only the main app can access its
        // own logs. (The main app can wipe logs for the other extensions.)
        for dirPath in Self.allLogsDirPaths() {
            do {
                try FileManager.default.removeItem(atPath: dirPath)
            } catch {
                owsFailDebug("Failed to delete log directory: \(error)")
            }
        }

        if shouldReEnable {
            enableFileLogging(appContext: appContext, canLaunchInBackground: true)
        }
    }
}
