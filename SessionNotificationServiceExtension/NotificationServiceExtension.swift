import UserNotifications
import SessionMessagingKit
import SignalUtilitiesKit
import PromiseKit

public final class NotificationServiceExtension : UNNotificationServiceExtension {
    private var didPerformSetup = false
    private var areVersionMigrationsComplete = false
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var notificationContent: UNMutableNotificationContent?

    public static let isFromRemoteKey = "remote"
    public static let threadIdKey = "Signal.AppNotificationsUserInfoKey.threadId"

    // MARK: Did receive a remote push notification request
    
    override public func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        self.notificationContent = request.content.mutableCopy() as? UNMutableNotificationContent

        // Abort if the main app is running
        var isMainAppAndActive = false
        if let sharedUserDefaults = UserDefaults(suiteName: "group.com.loki-project.loki-messenger") {
            isMainAppAndActive = sharedUserDefaults.bool(forKey: "isMainAppActive")
        }
        guard !isMainAppAndActive else { return self.completeSilenty() }

        // Perform main setup
        DispatchQueue.main.sync { self.setUpIfNecessary() { } }

        // Handle the push notification
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            let openGorupPollingPromises = self.pollForOpenGroups()
            defer {
                when(resolved: openGorupPollingPromises).done { _ in
                    self.completeSilenty()
                }
            }
            let notificationContent = self.notificationContent!
            guard let base64EncodedData = notificationContent.userInfo["ENCRYPTED_DATA"] as! String?, let data = Data(base64Encoded: base64EncodedData),
                let envelope = try? MessageWrapper.unwrap(data: data), let envelopeAsData = try? envelope.serializedData() else {
                return self.handleFailure(for: notificationContent)
            }
            // HACK: It is important to use writeSync() here to avoid a race condition
            // where the completeSilenty() is called before the local notification request
            // is added to notification center.
            Storage.writeSync { transaction in // Intentionally capture self
                do {
                    let (message, proto) = try MessageReceiver.parse(envelopeAsData, openGroupMessageServerID: nil, using: transaction)
                    switch message {
                    case let visibleMessage as VisibleMessage:
                        let tsMessageID = try MessageReceiver.handleVisibleMessage(visibleMessage, associatedWithProto: proto, openGroupID: nil, isBackgroundPoll: false, using: transaction)
                        
                        // Remove the notificaitons if there is an outgoing messages from a linked device
                        if let tsMessage = TSMessage.fetch(uniqueId: tsMessageID, transaction: transaction), tsMessage.isKind(of: TSOutgoingMessage.self), let threadID = tsMessage.thread(with: transaction).uniqueId {
                            let semaphore = DispatchSemaphore(value: 0)
                            let center = UNUserNotificationCenter.current()
                            center.getDeliveredNotifications { notifications in
                                let matchingNotifications = notifications.filter({ $0.request.content.userInfo[NotificationServiceExtension.threadIdKey] as? String == threadID})
                                center.removeDeliveredNotifications(withIdentifiers: matchingNotifications.map({ $0.request.identifier }))
                                // Hack: removeDeliveredNotifications seems to be async,need to wait for some time before the delivered notifications can be removed.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { semaphore.signal() }
                            }
                            semaphore.wait()
                        }
                        
                    case let unsendRequest as UnsendRequest:
                        MessageReceiver.handleUnsendRequest(unsendRequest, using: transaction)
                    case let closedGroupControlMessage as ClosedGroupControlMessage:
                        MessageReceiver.handleClosedGroupControlMessage(closedGroupControlMessage, using: transaction)
                    default: break
                    }
                } catch {
                    if let error = error as? MessageReceiver.Error, error.isRetryable {
                        self.handleFailure(for: notificationContent)
                    }
                }
            }
        }
    }

    // MARK: Setup
    
    private func setUpIfNecessary(completion: @escaping () -> Void) {
        AssertIsOnMainThread()

        // The NSE will often re-use the same process, so if we're
        // already set up we want to do nothing; we're already ready
        // to process new messages.
        guard !didPerformSetup else { return }

        didPerformSetup = true

        // This should be the first thing we do.
        SetCurrentAppContext(NotificationServiceExtensionContext())

        _ = AppVersion.sharedInstance()

        Cryptography.seedRandom()

        // We should never receive a non-voip notification on an app that doesn't support
        // app extensions since we have to inform the service we wanted these, so in theory
        // this path should never occur. However, the service does have our push token
        // so it is possible that could change in the future. If it does, do nothing
        // and don't disturb the user. Messages will be processed when they open the app.
        guard OWSPreferences.isReadyForAppExtensions() else { return completeSilenty() }

        AppSetup.setupEnvironment(
            appSpecificSingletonBlock: {
                SSKEnvironment.shared.notificationsManager = NSENotificationPresenter()
            },
            migrationCompletion: { [weak self] _, needsConfigSync in
                self?.versionMigrationsDidComplete(needsConfigSync: needsConfigSync)
                completion()
            }
        )

        NotificationCenter.default.addObserver(self, selector: #selector(storageIsReady), name: .StorageIsReady, object: nil)
    }
    
    @objc
    private func versionMigrationsDidComplete(needsConfigSync: Bool) {
        AssertIsOnMainThread()

        areVersionMigrationsComplete = true
        
        // If we need a config sync then trigger it now
        if needsConfigSync {
            MessageSender.syncConfiguration(forceSyncNow: true).retainUntilComplete()
        }

        checkIsAppReady()
    }

    @objc
    private func storageIsReady() {
        AssertIsOnMainThread()

        checkIsAppReady()
    }

    @objc
    private func checkIsAppReady() {
        AssertIsOnMainThread()

        // Only mark the app as ready once.
        guard !AppReadiness.isAppReady() else { return }

        // App isn't ready until storage is ready AND all version migrations are complete.
        guard OWSStorage.isStorageReady() && areVersionMigrationsComplete else { return }

        SignalUtilitiesKit.Configuration.performMainSetup()

        // Note that this does much more than set a flag; it will also run all deferred blocks.
        AppReadiness.setAppIsReady()
    }
    
    // MARK: Handle completion
    
    override public func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        completeSilenty()
    }
    
    private func completeSilenty() {
        SNLog("Complete silenty")
        self.contentHandler!(.init())
    }

    private func handleSuccess(for content: UNMutableNotificationContent) {
        contentHandler!(content)
    }

    private func handleFailure(for content: UNMutableNotificationContent) {
        content.body = "You've got a new message"
        content.title = "Session"
        let userInfo: [String:Any] = [ NotificationServiceExtension.isFromRemoteKey : true ]
        content.userInfo = userInfo
        contentHandler!(content)
    }
    
    // MARK: Poll for open groups
    private func pollForOpenGroups() -> [Promise<Void>] {
        var promises: [Promise<Void>] = []
        let servers = Set(Storage.shared.getAllV2OpenGroups().values.map { $0.server })
        servers.forEach { server in
            let poller = OpenGroupPollerV2(for: server)
            let promise = poller.poll().timeout(seconds: 20, timeoutError: NotificationServiceError.timeout)
            promises.append(promise)
        }
        return promises
    }
    
    private enum NotificationServiceError: Error {
        case timeout
    }
}
