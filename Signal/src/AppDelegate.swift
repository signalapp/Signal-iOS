//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
enum LaunchFailure: UInt {
    case none
    case couldNotLoadDatabase
    case unknownDatabaseVersion
    case couldNotRestoreTransferredData
    case databaseUnrecoverablyCorrupted
    case lastAppLaunchCrashed
    case lowStorageSpaceAvailable
}

extension AppDelegate {
    @objc(checkSomeDiskSpaceAvailable)
    func checkSomeDiskSpaceAvailable() -> Bool {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .path
        let succeededCreatingDir = OWSFileSystem.ensureDirectoryExists(tempDir)

        // Best effort at deleting temp dir, which shouldn't ever fail
        if succeededCreatingDir && !OWSFileSystem.deleteFile(tempDir) {
            owsFailDebug("Failed to delete temp dir used for checking disk space!")
        }

        return succeededCreatingDir
    }

    @objc(getActionSheetForLaunchFailure:fromViewController:onContinue:)
    func getActionSheet(for launchFailure: LaunchFailure,
                        from viewController: UIViewController,
                        onContinue: @escaping () -> Void) -> ActionSheetController {
        let title: String
        var message: String = NSLocalizedString("APP_LAUNCH_FAILURE_ALERT_MESSAGE",
                                                comment: "Message for the 'app launch failed' alert.")
        switch launchFailure {
        case .databaseUnrecoverablyCorrupted, .couldNotLoadDatabase:
            title = NSLocalizedString("APP_LAUNCH_FAILURE_COULD_NOT_LOAD_DATABASE",
                                      comment: "Error indicating that the app could not launch because the database could not be loaded.")
        case .unknownDatabaseVersion:
            title = NSLocalizedString("APP_LAUNCH_FAILURE_INVALID_DATABASE_VERSION_TITLE",
                                      comment: "Error indicating that the app could not launch without reverting unknown database migrations.")
            message = NSLocalizedString("APP_LAUNCH_FAILURE_INVALID_DATABASE_VERSION_MESSAGE",
                                        comment: "Error indicating that the app could not launch without reverting unknown database migrations.")
        case .couldNotRestoreTransferredData:
            title = NSLocalizedString("APP_LAUNCH_FAILURE_RESTORE_FAILED_TITLE",
                                      comment: "Error indicating that the app could not restore transferred data.")
            message = NSLocalizedString("APP_LAUNCH_FAILURE_RESTORE_FAILED_MESSAGE",
                                        comment: "Error indicating that the app could not restore transferred data.")
        case .lastAppLaunchCrashed:
            title = NSLocalizedString("APP_LAUNCH_FAILURE_LAST_LAUNCH_CRASHED_TITLE",
                                      comment: "Error indicating that the app crashed during the previous launch.")
            message = NSLocalizedString("APP_LAUNCH_FAILURE_LAST_LAUNCH_CRASHED_MESSAGE",
                                        comment: "Error indicating that the app crashed during the previous launch.")
        case .lowStorageSpaceAvailable:
            title = NSLocalizedString("APP_LAUNCH_FAILURE_LOW_STORAGE_SPACE_AVAILABLE_TITLE",
                                      comment: "Error title indicating that the app crashed because there was low storage space available on the device.")
            message = NSLocalizedString("APP_LAUNCH_FAILURE_LOW_STORAGE_SPACE_AVAILABLE_MESSAGE",
                                        comment: "Error description indicating that the app crashed because there was low storage space available on the device.")
        case .none:
            owsFailDebug("Unknown launch failure.")
            title = NSLocalizedString("APP_LAUNCH_FAILURE_ALERT_TITLE", comment: "Title for the 'app launch failed' alert.")
        }

        let result = ActionSheetController(title: title, message: message)

        if DebugFlags.internalSettings {
            result.addAction(.init(title: "Export Database (internal)") { _ in
                SignalApp.showExportDatabaseUI(from: viewController) { [weak viewController] in
                    viewController?.presentActionSheet(result)
                }
            })
        }

        if launchFailure != .lowStorageSpaceAvailable {
            let title = NSLocalizedString("SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", comment: "")
            result.addAction(.init(title: title) { _ in
                func submitDebugLogs() {
                    Pastelog.submitLogs(withSupportTag: Self.string(for: launchFailure),
                                        completion: onContinue)
                }

                if launchFailure == .databaseUnrecoverablyCorrupted {
                    SignalApp.showDatabaseIntegrityCheckUI(from: viewController,
                                                           completion: submitDebugLogs)
                } else {
                    submitDebugLogs()
                }
            })
        }

        if launchFailure == .lastAppLaunchCrashed {
            // Use a cancel-style button to draw attention.
            let title = NSLocalizedString("APP_LAUNCH_FAILURE_CONTINUE",
                                          comment: "Button to try launching the app even though the last launch failed")
            result.addAction(.init(title: title, style: .cancel) { _ in
                onContinue()
            })
        }

        return result
    }

    @objc(stringForLaunchFailure:)
    class func string(for launchFailure: LaunchFailure) -> String {
        switch launchFailure {
        case .none:
            return "LaunchFailure_None"
        case .couldNotLoadDatabase:
            return "LaunchFailure_CouldNotLoadDatabase"
        case .unknownDatabaseVersion:
            return "LaunchFailure_UnknownDatabaseVersion"
        case .couldNotRestoreTransferredData:
            return "LaunchFailure_CouldNotRestoreTransferredData"
        case .databaseUnrecoverablyCorrupted:
            return "LaunchFailure_DatabaseUnrecoverablyCorrupted"
        case .lastAppLaunchCrashed:
            return "LaunchFailure_LastAppLaunchCrashed"
        case .lowStorageSpaceAvailable:
            return "LaunchFailure_NoDiskSpaceAvailable"
        }
    }

    @objc
    func setupNSEInteroperation() {
        Logger.info("")

        // We immediately post a notification letting the NSE know the main app has launched.
        // If it's running it should take this as a sign to terminate so we don't unintentionally
        // try and fetch messages from two processes at once.
        DarwinNotificationCenter.post(.mainAppLaunched)

        // We listen to this notification for the lifetime of the application, so we don't
        // record the returned observer token.
        DarwinNotificationCenter.addObserver(
            for: .nseDidReceiveNotification,
            queue: DispatchQueue.global(qos: .userInitiated)
        ) { token in
            Logger.debug("Handling NSE received notification")

            // Immediately let the NSE know we will handle this notification so that it
            // does not attempt to process messages while we are active.
            DarwinNotificationCenter.post(.mainAppHandledNotification)

            AppReadiness.runNowOrWhenAppDidBecomeReadySync {
                self.messageFetcherJob.run()
            }
        }
    }
}
