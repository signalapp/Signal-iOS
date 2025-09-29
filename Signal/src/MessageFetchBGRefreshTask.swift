//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BackgroundTasks
public import SignalServiceKit

/**
 * Utility class for managing the BGAppRefreshTask we use as a "keepalive" for
 * registration lock.
 *
 * Ensures that while reglock is active, we try to fetch messages every once in a while
 * even if the app or NSE don't launch, so that the server keeps the account active
 * and reglock alive.
 */
final public class MessageFetchBGRefreshTask {

    private static var _shared: MessageFetchBGRefreshTask?

    public static func getShared(appReadiness: AppReadiness) -> MessageFetchBGRefreshTask? {
        if let _shared {
            return _shared
        }

        guard appReadiness.isAppReady else {
            return nil
        }
        let value = MessageFetchBGRefreshTask(
            backgroundMessageFetcherFactory: DependenciesBridge.shared.backgroundMessageFetcherFactory,
            dateProvider: { Date() },
            ows2FAManager: SSKEnvironment.shared.ows2FAManagerRef,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager
        )
        _shared = value
        return value
    }

    // Must be kept in sync with the value in info.plist.
    private static let taskIdentifier = "MessageFetchBGRefreshTask"

    private let backgroundMessageFetcherFactory: BackgroundMessageFetcherFactory
    private let dateProvider: DateProvider
    private let ows2FAManager: OWS2FAManager
    private let tsAccountManager: TSAccountManager

    private init(
        backgroundMessageFetcherFactory: BackgroundMessageFetcherFactory,
        dateProvider: @escaping DateProvider,
        ows2FAManager: OWS2FAManager,
        tsAccountManager: TSAccountManager
    ) {
        self.backgroundMessageFetcherFactory = backgroundMessageFetcherFactory
        self.dateProvider = dateProvider
        self.ows2FAManager = ows2FAManager
        self.tsAccountManager = tsAccountManager
    }

    public static func register(appReadiness: AppReadiness) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil,
            launchHandler: { task in
                appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
                    Self.getShared(appReadiness: appReadiness)!.performTask(task)
                }
            }
        )
    }

    public func scheduleTask() {
        // Note: this file only exists in the main app (Signal/src) so we
        // don't check for that. But if this ever moves, it should check
        // appContext.isMainApp.

        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }

        // Ideally, we would schedule this for N hours _since we last talked to the chat server_.
        // Without knowing that, we risk scheduling this 24 hours out over and over every time you
        // launch the app without internet. That scenario is unlikely, so is left unhandled.
        let refreshInterval: TimeInterval = RemoteConfig.current.backgroundRefreshInterval
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = dateProvider().addingTimeInterval(refreshInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch let error {
            let errorCode = (error as NSError).code
            switch errorCode {
            case BGTaskScheduler.Error.Code.notPermitted.rawValue:
                Logger.warn("Skipping bg task; user permission required.")
            case BGTaskScheduler.Error.Code.tooManyPendingTaskRequests.rawValue:
                // If we reschedule the same identifier, we don't get this error.
                // This means a task with a different identifier was scheduled (not allowed).
                Logger.error("Too many pending bg tasks; only one app refresh task identifier is allowed at any time.")
            case BGTaskScheduler.Error.Code.unavailable.rawValue:
                Logger.warn("Trying to schedule bg task from an extension or simulator?")
            default:
                Logger.error("Unknown error code scheduling bg task: \(errorCode)")
            }
        }
    }

    private func performTask(_ task: BGTask) {
        Logger.info("performing background fetch")
        Task {
            let backgroundMessageFetcher = self.backgroundMessageFetcherFactory.buildFetcher()
            let result = await Result {
                try await withCooperativeTimeout(seconds: 27) {
                    await backgroundMessageFetcher.start()
                    try await backgroundMessageFetcher.waitForFetchingProcessingAndSideEffects()
                }
            }
            await backgroundMessageFetcher.stopAndWaitBeforeSuspending()
            // Schedule the next run now.
            self.scheduleTask()
            do {
                try result.get()
                Logger.info("success")
                task.setTaskCompleted(success: true)
            } catch {
                Logger.error("Failing task; failed to fetch messages")
                task.setTaskCompleted(success: false)
            }
        }
    }
}
