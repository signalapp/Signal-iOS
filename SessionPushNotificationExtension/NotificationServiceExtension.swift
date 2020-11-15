import UserNotifications
import SignalUtilitiesKit

final class NotificationServiceExtension : UNNotificationServiceExtension {
    static let isFromRemoteKey = "remote"
    static let threadIdKey = "Signal.AppNotificationsUserInfoKey.threadId"

    private var didPerformSetup = false

    var areVersionMigrationsComplete = false
    var contentHandler: ((UNNotificationContent) -> Void)?
    var notificationContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        notificationContent = request.content.mutableCopy() as? UNMutableNotificationContent
        
        var isMainAppActive = false
        if let sharedUserDefaults = UserDefaults(suiteName: "group.com.loki-project.loki-messenger") {
            isMainAppActive = sharedUserDefaults.bool(forKey: "isMainAppActive")
        }
        // If the main app is running, skip the whole process
        guard !isMainAppActive else { return self.completeWithFailure(content: notificationContent!) }
        
        // The code using DispatchQueue.main.async { self.setUpIfNecessary() { Modify the notification content } } will somehow cause a freeze when a second PN comes
        
        DispatchQueue.main.sync { self.setUpIfNecessary() {} }
        
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            if let notificationContent = self.notificationContent {
                // Modify the notification content here...
                let base64EncodedData = notificationContent.userInfo["ENCRYPTED_DATA"] as! String
                let data = Data(base64Encoded: base64EncodedData)!
                if let envelope = try? MessageWrapper.unwrap(data: data), let data = try? envelope.serializedData() {
                    // TODO TODO TODO
                    
                    /*
                    decrypter.decryptEnvelope(envelope,
                                              envelopeData: data,
                                              successBlock: { result, transaction in
                                                  if let envelope = try? SSKProtoEnvelope.parseData(result.envelopeData) {
                                                      messageManager.throws_processEnvelope(envelope, plaintextData: result.plaintextData, wasReceivedByUD: wasReceivedByUD, transaction: transaction, serverID: 0)
                                                      self.handleDecryptionResult(result: result, notificationContent: notificationContent, transaction: transaction)
                                                  } else {
                                                      self.completeWithFailure(content: notificationContent)
                                                  }
                                              },
                                              failureBlock: {
                                                  self.completeWithFailure(content: notificationContent)
                                              }
                    )
                     */
                } else {
                    self.completeWithFailure(content: notificationContent)
                }
            }
        }
    }
    
    /*
    func handleDecryptionResult(result: OWSMessageDecryptResult, notificationContent: UNMutableNotificationContent, transaction: YapDatabaseReadWriteTransaction) {
        let contentProto = try? SSKProtoContent.parseData(result.plaintextData!)
        var thread: TSThread
        var newNotificationBody = ""
        let masterPublicKey = OWSPrimaryStorage.shared().getMasterHexEncodedPublicKey(for: result.source, in: transaction) ?? result.source
        var displayName = OWSUserProfile.fetch(uniqueId: masterPublicKey, transaction: transaction)?.profileName ?? SSKEnvironment.shared.contactsManager.displayName(forPhoneIdentifier: masterPublicKey)
        if let groupID = contentProto?.dataMessage?.group?.id {
            thread = TSGroupThread.getOrCreateThread(withGroupId: groupID, groupType: .closedGroup, transaction: transaction)
            var groupName = thread.name()
            if groupName.count < 1 {
                groupName = MessageStrings.newGroupDefaultTitle
            }
            let senderName = OWSUserProfile.fetch(uniqueId: masterPublicKey, transaction: transaction)?.profileName ?? SSKEnvironment.shared.contactsManager.displayName(forPhoneIdentifier: masterPublicKey)
            displayName = String(format: NotificationStrings.incomingGroupMessageTitleFormat, senderName, groupName)
            let group: SSKProtoGroupContext = contentProto!.dataMessage!.group!
            let oldGroupModel = (thread as! TSGroupThread).groupModel
            let removedMembers = NSMutableSet(array: oldGroupModel.groupMemberIds)
            let newGroupModel = TSGroupModel.init(title: group.name,
                                                  memberIds:group.members,
                                                  image: oldGroupModel.groupImage,
                                                  groupId: group.id,
                                                  groupType: oldGroupModel.groupType,
                                                  adminIds: group.admins)
            removedMembers.minus(Set(newGroupModel.groupMemberIds))
            newGroupModel.removedMembers = removedMembers
            switch contentProto?.dataMessage?.group?.type {
            case .update:
                newNotificationBody = oldGroupModel.getInfoStringAboutUpdate(to: newGroupModel, contactsManager: SSKEnvironment.shared.contactsManager)
                break
            case .quit:
                let nameString = SSKEnvironment.shared.contactsManager.displayName(forPhoneIdentifier: masterPublicKey, transaction: transaction)
                newNotificationBody = NSLocalizedString("GROUP_MEMBER_LEFT", comment: nameString)
                break
            default:
                break
            }
        } else {
            thread = TSContactThread.getOrCreateThread(withContactId: result.source, transaction: transaction)
        }
        let userInfo: [String:Any] = [ NotificationServiceExtension.threadIdKey : thread.uniqueId!, NotificationServiceExtension.isFromRemoteKey : true ]
        notificationContent.title = displayName
        notificationContent.userInfo = userInfo
        notificationContent.badge = 1
        if let attachment = contentProto?.dataMessage?.attachments.last {
            newNotificationBody = TSAttachment.emoji(forMimeType: attachment.contentType!) + "Attachment"
            if let rawMessageBody = contentProto?.dataMessage?.body, rawMessageBody.count > 0 {
                newNotificationBody += ": \(rawMessageBody)"
            }
        }
        if newNotificationBody.count < 1 {
            newNotificationBody = contentProto?.dataMessage?.body ?? "You've got a new message"
        }
        newNotificationBody = handleMentionIfNecessary(rawMessageBody: newNotificationBody, threadID: thread.uniqueId!, transaction: transaction)
        
        let notificationPreference = Environment.shared.preferences
        if let notificationType = notificationPreference?.notificationPreviewType() {
            switch notificationType {
            case .nameNoPreview:
                notificationContent.body = "New Message"
            case .noNameNoPreview:
                notificationContent.title = ""
                notificationContent.body = "New Message"
            default:
                notificationContent.body = newNotificationBody
            }
        } else {
            notificationContent.body = newNotificationBody
        }
        
        if notificationContent.body.count < 1 {
            self.completeWithFailure(content: notificationContent)
        } else {
            self.contentHandler!(notificationContent)
        }
    }
     */
    
    func handleMentionIfNecessary(rawMessageBody: String, threadID: String, transaction: YapDatabaseReadWriteTransaction) -> String {
        var string = rawMessageBody
        let regex = try! NSRegularExpression(pattern: "@[0-9a-fA-F]*", options: [])
        var outerMatch = regex.firstMatch(in: string, options: .withoutAnchoringBounds, range: NSRange(location: 0, length: string.utf16.count))
        while let match = outerMatch {
            let publicKey = String((string as NSString).substring(with: match.range).dropFirst()) // Drop the @
            let matchEnd: Int
            let displayName: String? = OWSProfileManager.shared().profileNameForRecipient(withID: publicKey, transaction: transaction)
            if let displayName = displayName {
                string = (string as NSString).replacingCharacters(in: match.range, with: "@\(displayName)")
                matchEnd = match.range.location + displayName.utf16.count
            } else {
                matchEnd = match.range.location + match.range.length
            }
            outerMatch = regex.firstMatch(in: string, options: .withoutAnchoringBounds, range: NSRange(location: matchEnd, length: string.utf16.count - matchEnd))
        }
        return string
    }

    func setUpIfNecessary(completion: @escaping () -> Void) {
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
                SSKEnvironment.shared.callMessageHandler = NoopCallMessageHandler()
                SSKEnvironment.shared.notificationsManager = NoopNotificationsManager()
            },
            migrationCompletion: { [weak self] in
                self?.versionMigrationsDidComplete()
                completion()
            }
        )

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(storageIsReady),
                                               name: .StorageIsReady,
                                               object: nil)
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let notificationContent =  notificationContent {
            contentHandler(notificationContent)
        }
    }
    
    func wasReceivedByUD(envelope: SSKProtoEnvelope) -> Bool {
        return (envelope.type == .unidentifiedSender && (!envelope.hasSource || envelope.source!.count < 1))
    }
    
    @objc
    func versionMigrationsDidComplete() {
        AssertIsOnMainThread()

        areVersionMigrationsComplete = true

        checkIsAppReady()
    }

    @objc
    func storageIsReady() {
        AssertIsOnMainThread()

        checkIsAppReady()
    }

    @objc
    func checkIsAppReady() {
        AssertIsOnMainThread()

        // Only mark the app as ready once.
        guard !AppReadiness.isAppReady() else { return }

        // App isn't ready until storage is ready AND all version migrations are complete.
        guard OWSStorage.isStorageReady() && areVersionMigrationsComplete else { return }

        // Note that this does much more than set a flag; it will also run all deferred blocks.
        AppReadiness.setAppIsReady()
    }
    
    func completeSilenty() {
        contentHandler?(.init())
    }
    
    func completeWithFailure(content: UNMutableNotificationContent) {
        content.body = "You've got a new message"
        content.title = "Session"
        let userInfo: [String:Any] = [NotificationServiceExtension.isFromRemoteKey : true]
        content.userInfo = userInfo
        contentHandler?(content)
    }
}
