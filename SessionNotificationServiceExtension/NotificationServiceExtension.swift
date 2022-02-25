import UserNotifications
import SessionMessagingKit
import SignalUtilitiesKit

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
        let userPublicKey = SNGeneralUtilities.getUserPublicKey()

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
            let notificationContent = self.notificationContent!
            guard let base64EncodedData = notificationContent.userInfo["ENCRYPTED_DATA"] as! String?, let data = Data(base64Encoded: base64EncodedData),
                let envelope = try? MessageWrapper.unwrap(data: data), let envelopeAsData = try? envelope.serializedData() else {
                return self.handleFailure(for: notificationContent)
            }
            Storage.write { transaction in // Intentionally capture self
                do {
                    let (message, proto) = try MessageReceiver.parse(envelopeAsData, openGroupMessageServerID: nil, using: transaction)
                    let senderPublicKey = message.sender!
                    var senderDisplayName = Storage.shared.getContact(with: senderPublicKey)?.displayName(for: .regular) ?? senderPublicKey
                    let snippet: String
                    var userInfo: [String: Any] = [ NotificationServiceExtension.isFromRemoteKey: true ]
                    var isMessageRequest: Bool = false
                    
                    switch message {
                        case let visibleMessage as VisibleMessage:
                            let tsIncomingMessageID = try MessageReceiver.handleVisibleMessage(visibleMessage, associatedWithProto: proto, openGroupID: nil, isBackgroundPoll: false, using: transaction)
                            
                            guard let tsMessage = TSMessage.fetch(uniqueId: tsIncomingMessageID, transaction: transaction) else {
                                return self.completeSilenty()
                            }
                            
                            let thread = tsMessage.thread(with: transaction)
                            let threadID = thread.uniqueId!
                            userInfo[NotificationServiceExtension.threadIdKey] = threadID
                            snippet = tsMessage.previewText(with: transaction).filterForDisplay?.replacingMentions(for: threadID, using: transaction)
                                ?? "You've got a new message"
                            
                            if let tsIncomingMessage = tsMessage as? TSIncomingMessage {
                                // Ignore PNs if the thread is muted
                                if thread.isMuted { return self.completeSilenty() }
                                if let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction), let group = thread as? TSGroupThread,
                                    group.groupModel.groupType == .closedGroup { // Should always be true because we don't get PNs for open groups
                                    senderDisplayName = String(format: NotificationStrings.incomingGroupMessageTitleFormat, senderDisplayName, group.groupModel.groupName ?? MessageStrings.newGroupDefaultTitle)
                                    if group.isOnlyNotifyingForMentions && !tsIncomingMessage.isUserMentioned {
                                        // Ignore PNs if the group is set to only notify for mentions
                                        return self.completeSilenty()
                                    }
                                }
                                
                                // If the thread is a message request and the user hasn't hidden message requests then we need
                                // to check if this is the only message request thread (group threads can't be message requests
                                // so just ignore those and if the user has hidden message requests then we want to show the
                                // notification regardless of how many message requests there are)
                                if !thread.isGroupThread() && thread.isMessageRequest() && !CurrentAppContext().appUserDefaults()[.hasHiddenMessageRequests] {
                                    let dbConnection: YapDatabaseConnection = OWSPrimaryStorage.shared().newDatabaseConnection()
                                    dbConnection.objectCacheLimit = 2
                                    dbConnection.beginLongLivedReadTransaction() // Freeze the connection for use on the main thread (this gives us a stable data source that doesn't change until we tell it to)
                                    let threads: YapDatabaseViewMappings = YapDatabaseViewMappings(groups: [ TSMessageRequestGroup ], view: TSThreadDatabaseViewExtensionName)
                                    dbConnection.read { transaction in
                                        threads.update(with: transaction) // Perform the initial update
                                    }

                                    let numMessageRequests = threads.numberOfItems(inGroup: TSMessageRequestGroup)
                                    dbConnection.endLongLivedReadTransaction()

                                    // Allow this to show a notification if there are no message requests (ie. this is the first one)
                                    guard numMessageRequests == 0 else { return self.completeSilenty() }
                                }
                                else if thread.isMessageRequest() && CurrentAppContext().appUserDefaults()[.hasHiddenMessageRequests] {
                                    // If there are other interactions on this thread already then don't show the notification
                                    if thread.numberOfInteractions() > 1 { return }
                                    
                                    CurrentAppContext().appUserDefaults()[.hasHiddenMessageRequests] = false
                                }

                                isMessageRequest = thread.isMessageRequest()
                                
                                // Store the notification ID for unsend requests to later cancel this notification
                                tsIncomingMessage.setNotificationIdentifier(request.identifier, transaction: transaction)
                            }
                            else {
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
                            notificationContent.sound = OWSSounds.notificationSound(for: thread).notificationSound(isQuiet: false)
                            
                        case let unsendRequest as UnsendRequest:
                            MessageReceiver.handleUnsendRequest(unsendRequest, using: transaction)
                            return self.completeSilenty()
                            
                        case let closedGroupControlMessage as ClosedGroupControlMessage:
                            // TODO: We could consider actually handling the update here. Not sure if there's enough time though, seeing as though
                            // in some cases we need to send messages (e.g. our sender key) to a number of other users.
                            switch closedGroupControlMessage.kind {
                                case .new(_, let name, _, _, _, _): snippet = "\(senderDisplayName) added you to \(name)"
                                default: return self.completeSilenty()
                            }
                            
                        default: return self.completeSilenty()
                    }
                    
                    if (senderPublicKey == userPublicKey) {
                        // Ignore PNs for messages sent by the current user
                        // after handling the message. Otherwise the closed
                        // group self-send messages won't show.
                        return self.completeSilenty()
                    }
                    notificationContent.userInfo = userInfo
                    notificationContent.badge = 1
                    
                    let notificationsPreference = Environment.shared.preferences!.notificationPreviewType()
                    
                    switch notificationsPreference {
                        case .namePreview:
                            notificationContent.title = senderDisplayName
                            notificationContent.body = snippet
                            
                        case .nameNoPreview:
                            notificationContent.title = senderDisplayName
                            notificationContent.body = NotificationStrings.incomingMessageBody
                            
                        case .noNameNoPreview:
                            notificationContent.title = "Session"
                            notificationContent.body = NotificationStrings.incomingMessageBody
                            
                        default: break
                    }
                    
                    // If it's a message request then overwrite the body to be something generic (only show a notification
                    // when receiving a new message request if there aren't any others or the user had hidden them)
                    if isMessageRequest {
                        notificationContent.title = "Session"
                        notificationContent.body = NSLocalizedString("MESSAGE_REQUESTS_NOTIFICATION", comment: "")
                    }
                    
                    self.handleSuccess(for: notificationContent)
                }
                catch {
                    if let error = error as? MessageReceiver.Error, error.isRetryable {
                        self.handleFailure(for: notificationContent)
                    }
                    self.completeSilenty()
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
        notificationContent.body = "You've got a new message"
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
    
    private func completeSilenty() {
        contentHandler!(.init())
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
}

private extension String {
    
    func replacingMentions(for threadID: String, using transaction: YapDatabaseReadWriteTransaction) -> String {
        MentionsManager.populateUserPublicKeyCacheIfNeeded(for: threadID, in: transaction)
        var result = self
        let regex = try! NSRegularExpression(pattern: "@[0-9a-fA-F]{66}", options: [])
        let knownPublicKeys = MentionsManager.userPublicKeyCache[threadID] ?? []
        var mentions: [(range: NSRange, publicKey: String)] = []
        var m0 = regex.firstMatch(in: result, options: .withoutAnchoringBounds, range: NSRange(location: 0, length: result.utf16.count))
        while let m1 = m0 {
            let publicKey = String((result as NSString).substring(with: m1.range).dropFirst()) // Drop the @
            var matchEnd = m1.range.location + m1.range.length
            if knownPublicKeys.contains(publicKey) {
                let displayName = Storage.shared.getContact(with: publicKey)?.displayName(for: .regular)
                if let displayName = displayName {
                    result = (result as NSString).replacingCharacters(in: m1.range, with: "@\(displayName)")
                    mentions.append((range: NSRange(location: m1.range.location, length: displayName.utf16.count + 1), publicKey: publicKey)) // + 1 to include the @
                    matchEnd = m1.range.location + displayName.utf16.count
                }
            }
            m0 = regex.firstMatch(in: result, options: .withoutAnchoringBounds, range: NSRange(location: matchEnd, length: result.utf16.count - matchEnd))
        }
        return result
    }
}
