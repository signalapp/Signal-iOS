import UserNotifications
import SessionMessagingKit
import SignalUtilitiesKit

// TODO: Group notifications

public final class NotificationServiceExtension : UNNotificationServiceExtension {
    private var didPerformSetup = false
    private var areVersionMigrationsComplete = false
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var notificationContent: UNMutableNotificationContent?

    private static let isFromRemoteKey = "remote"
    private static let threadIdKey = "Signal.AppNotificationsUserInfoKey.threadId"

    override public func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        self.notificationContent = request.content.mutableCopy() as? UNMutableNotificationContent

        // Abort if the main app is running
        var isMainAppAndActive = false
        if let sharedUserDefaults = UserDefaults(suiteName: "group.com.loki-project.loki-messenger") {
            isMainAppAndActive = sharedUserDefaults.bool(forKey: "isMainAppActive")
        }
        guard !isMainAppAndActive else { return self.handleFailure(for: notificationContent!) }

        // Perform main setup
        DispatchQueue.main.sync { self.setUpIfNecessary() { } }

        // Handle the push notification
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            let notificationContent = self.notificationContent!
            guard let base64EncodedData = notificationContent.userInfo["ENCRYPTED_DATA"] as! String?, let data = Data(base64Encoded: base64EncodedData),
                let envelope = try? MessageWrapper.unwrap(data: data), let envelopeAsData = try? envelope.serializedData() else {
                return self.handleFailure(for: notificationContent)
            }
            Storage.write { transaction in // Intentionally capture self
                do {
                    let (message, proto) = try MessageReceiver.parse(envelopeAsData, openGroupMessageServerID: nil, using: transaction)
                    guard let visibleMessage = message as? VisibleMessage else {
                        return self.handleFailure(for: notificationContent)
                    }
                    let tsIncomingMessageID = try MessageReceiver.handleVisibleMessage(visibleMessage, associatedWithProto: proto, openGroupID: nil, using: transaction)
                    guard let tsIncomingMessage = TSIncomingMessage.fetch(uniqueId: tsIncomingMessageID, transaction: transaction) else {
                        return self.handleFailure(for: notificationContent)
                    }
                    let snippet = tsIncomingMessage.previewText(with: transaction).filterForDisplay
                    let userInfo: [String:Any] = [ NotificationServiceExtension.threadIdKey : tsIncomingMessage.thread(with: transaction).uniqueId!, NotificationServiceExtension.isFromRemoteKey : true ]
                    let senderPublicKey = message.sender!
                    let senderDisplayName = OWSProfileManager.shared().profileNameForRecipient(withID: senderPublicKey, transaction: transaction) ?? senderPublicKey
                    notificationContent.userInfo = userInfo
                    notificationContent.badge = 1
                    let notificationsPreference = Environment.shared.preferences!.notificationPreviewType()
                    switch notificationsPreference {
                    case .namePreview:
                        notificationContent.title = senderDisplayName
                        notificationContent.body = snippet!
                    case .nameNoPreview:
                        notificationContent.title = senderDisplayName
                        notificationContent.body = "New Message"
                    case .noNameNoPreview:
                        notificationContent.title = "Session"
                        notificationContent.body = "New Message"
                    default: break
                    }
                    self.handleSuccess(for: notificationContent)
                } catch {
                    self.handleFailure(for: notificationContent)
                }
            }
        }
    }

    private func setUpIfNecessary(completion: @escaping () -> Void) {
        AssertIsOnMainThread()

        // The NSE will often re-use the same process, so if we're
        // already set up we want to do nothing; we're already ready
        // to process new messages.
        guard !didPerformSetup else { return }

        didPerformSetup = true

        // This should be the first thing we do.
        SetCurrentAppContext(NotificationServiceExtensionContext())

        DebugLogger.shared().enableTTYLogging()
        if _isDebugAssertConfiguration() {
            DebugLogger.shared().enableFileLogging()
        }

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
                SSKEnvironment.shared.notificationsManager = NoopNotificationsManager()
            },
            migrationCompletion: { [weak self] in
                self?.versionMigrationsDidComplete()
                completion()
            }
        )

        NotificationCenter.default.addObserver(self, selector: #selector(storageIsReady), name: .StorageIsReady, object: nil)
    }
    
    override public func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        let userInfo: [String:Any] = [ NotificationServiceExtension.isFromRemoteKey : true ]
        let notificationContent = self.notificationContent!
        notificationContent.userInfo = userInfo
        notificationContent.badge = 1
        notificationContent.title = "Session"
        notificationContent.body = "New Message"
        handleSuccess(for: notificationContent)
    }
    
    @objc
    private func versionMigrationsDidComplete() {
        AssertIsOnMainThread()

        areVersionMigrationsComplete = true

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
    
    private  func completeSilenty() {
        contentHandler!(.init())
    }

    private func handleSuccess(for content: UNMutableNotificationContent) {
        contentHandler!(content)
    }

    private func handleFailure(for content: UNMutableNotificationContent) {
        content.body = "New Message"
        content.title = "Session"
        let userInfo: [String:Any] = [ NotificationServiceExtension.isFromRemoteKey : true ]
        content.userInfo = userInfo
        contentHandler!(content)
    }
}
