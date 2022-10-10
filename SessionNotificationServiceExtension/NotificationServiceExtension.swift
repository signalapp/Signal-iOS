// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import CallKit
import UserNotifications
import BackgroundTasks
import PromiseKit
import SessionMessagingKit
import SignalUtilitiesKit

public final class NotificationServiceExtension: UNNotificationServiceExtension {
    private var didPerformSetup = false
    private var areVersionMigrationsComplete = false
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var request: UNNotificationRequest?

    public static let isFromRemoteKey = "remote"
    public static let threadIdKey = "Signal.AppNotificationsUserInfoKey.threadId"
    public static let threadNotificationCounter = "Session.AppNotificationsUserInfoKey.threadNotificationCounter"

    // MARK: Did receive a remote push notification request
    
    override public func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        self.request = request
        
        // Resume database
        NotificationCenter.default.post(name: Database.resumeNotification, object: self)
        
        guard let notificationContent = request.content.mutableCopy() as? UNMutableNotificationContent else {
            return self.completeSilenty()
        }

        // Abort if the main app is running
        guard !(UserDefaults.sharedLokiProject?[.isMainAppActive]).defaulting(to: false) else {
            return self.completeSilenty()
        }
        
        let isCallOngoing: Bool = (UserDefaults.sharedLokiProject?[.isCallOngoing])
            .defaulting(to: false)

        // Perform main setup
        DispatchQueue.main.sync { self.setUpIfNecessary() { } }

        // Handle the push notification
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            let openGroupPollingPromises = self.pollForOpenGroups()
            defer {
                when(resolved: openGroupPollingPromises).done { _ in
                    self.completeSilenty()
                }
            }
            
            guard
                let base64EncodedData: String = notificationContent.userInfo["ENCRYPTED_DATA"] as? String,
                let data: Data = Data(base64Encoded: base64EncodedData),
                let envelope = try? MessageWrapper.unwrap(data: data)
            else {
                return self.handleFailure(for: notificationContent)
            }
            
            // HACK: It is important to use write synchronously here to avoid a race condition
            // where the completeSilenty() is called before the local notification request
            // is added to notification center
            Storage.shared.write { db in
                do {
                    guard let processedMessage: ProcessedMessage = try Message.processRawReceivedMessageAsNotification(db, envelope: envelope) else {
                        self.handleFailure(for: notificationContent)
                        return
                    }
                    
                    let maybeVariant: SessionThread.Variant? = processedMessage.threadId
                        .map { threadId in
                            try? SessionThread
                                .filter(id: threadId)
                                .select(.variant)
                                .asRequest(of: SessionThread.Variant.self)
                                .fetchOne(db)
                        }
                    let isOpenGroup: Bool = (maybeVariant == .openGroup)
                    
                    switch processedMessage.messageInfo.message {
                        case let visibleMessage as VisibleMessage:
                            let interactionId: Int64 = try MessageReceiver.handleVisibleMessage(
                                db,
                                message: visibleMessage,
                                associatedWithProto: processedMessage.proto,
                                openGroupId: (isOpenGroup ? processedMessage.threadId : nil)
                            )
                            
                            // Remove the notifications if there is an outgoing messages from a linked device
                            if
                                let interaction: Interaction = try? Interaction.fetchOne(db, id: interactionId),
                                interaction.variant == .standardOutgoing
                            {
                                let semaphore = DispatchSemaphore(value: 0)
                                let center = UNUserNotificationCenter.current()
                                center.getDeliveredNotifications { notifications in
                                    let matchingNotifications = notifications.filter({ $0.request.content.userInfo[NotificationServiceExtension.threadIdKey] as? String == interaction.threadId })
                                    center.removeDeliveredNotifications(withIdentifiers: matchingNotifications.map({ $0.request.identifier }))
                                    // Hack: removeDeliveredNotifications seems to be async,need to wait for some time before the delivered notifications can be removed.
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { semaphore.signal() }
                                }
                                semaphore.wait()
                            }
                        
                        case let unsendRequest as UnsendRequest:
                            try MessageReceiver.handleUnsendRequest(db, message: unsendRequest)
                            
                        case let closedGroupControlMessage as ClosedGroupControlMessage:
                            try MessageReceiver.handleClosedGroupControlMessage(db, closedGroupControlMessage)
                            
                        case let callMessage as CallMessage:
                            try MessageReceiver.handleCallMessage(db, message: callMessage)
                            
                            guard case .preOffer = callMessage.kind else { return self.completeSilenty() }
                            
                            if !db[.areCallsEnabled] {
                                if let sender: String = callMessage.sender, let interaction: Interaction = try MessageReceiver.insertCallInfoMessage(db, for: callMessage, state: .permissionDenied) {
                                    let thread: SessionThread = try SessionThread.fetchOrCreate(db, id: sender, variant: .contact)

                                    Environment.shared?.notificationsManager.wrappedValue?
                                        .notifyUser(
                                            db,
                                            forIncomingCall: interaction,
                                            in: thread
                                        )
                                }
                                break
                            }
                            
                            if isCallOngoing {
                                try MessageReceiver.handleIncomingCallOfferInBusyState(db, message: callMessage)
                                break
                            }
                            
                            self.handleSuccessForIncomingCall(db, for: callMessage)
                            
                        default: break
                    }
                    
                    // Perform any required post-handling logic
                    try MessageReceiver.postHandleMessage(
                        db,
                        message: processedMessage.messageInfo.message,
                        openGroupId: (isOpenGroup ? processedMessage.threadId : nil)
                    )
                }
                catch {
                    if let error = error as? MessageReceiverError, error.isRetryable {
                        switch error {
                            case .invalidGroupPublicKey, .noGroupKeyPair: self.completeSilenty()
                            default: self.handleFailure(for: notificationContent)
                        }
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
        guard Storage.shared[.isReadyForAppExtensions] else { return completeSilenty() }

        AppSetup.setupEnvironment(
            appSpecificBlock: {
                Environment.shared?.notificationsManager.mutate {
                    $0 = NSENotificationPresenter()
                }
            },
            migrationsCompletion: { [weak self] _, needsConfigSync in
                self?.versionMigrationsDidComplete(needsConfigSync: needsConfigSync)
                completion()
            }
        )
    }
    
    @objc
    private func versionMigrationsDidComplete(needsConfigSync: Bool) {
        AssertIsOnMainThread()

        areVersionMigrationsComplete = true
        
        // If we need a config sync then trigger it now
        if needsConfigSync {
            Storage.shared.write { db in
                try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
            }
        }

        checkIsAppReady()
    }

    @objc
    private func checkIsAppReady() {
        AssertIsOnMainThread()

        // Only mark the app as ready once.
        guard !AppReadiness.isAppReady() else { return }

        // App isn't ready until storage is ready AND all version migrations are complete.
        guard Storage.shared.isValid && areVersionMigrationsComplete else { return }

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
        
        // Suspend the database
        NotificationCenter.default.post(name: Database.suspendNotification, object: self)
        
        self.contentHandler!(.init())
    }
    
    private func handleSuccessForIncomingCall(_ db: Database, for callMessage: CallMessage) {
        if #available(iOSApplicationExtension 14.5, *), Preferences.isCallKitSupported {
            guard let caller: String = callMessage.sender, let timestamp = callMessage.sentTimestamp else { return }
            
            let payload: JSON = [
                "uuid": callMessage.uuid,
                "caller": caller,
                "timestamp": timestamp
            ]
            
            CXProvider.reportNewIncomingVoIPPushPayload(payload) { error in
                if let error = error {
                    self.handleFailureForVoIP(db, for: callMessage)
                    SNLog("Failed to notify main app of call message: \(error)")
                }
                else {
                    self.completeSilenty()
                    SNLog("Successfully notified main app of call message.")
                }
            }
        }
        else {
            self.handleFailureForVoIP(db, for: callMessage)
        }
    }
    
    private func handleFailureForVoIP(_ db: Database, for callMessage: CallMessage) {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.userInfo = [ NotificationServiceExtension.isFromRemoteKey : true ]
        notificationContent.title = "Session"
        
        // Badge Number
        let newBadgeNumber = CurrentAppContext().appUserDefaults().integer(forKey: "currentBadgeNumber") + 1
        notificationContent.badge = NSNumber(value: newBadgeNumber)
        CurrentAppContext().appUserDefaults().set(newBadgeNumber, forKey: "currentBadgeNumber")
        
        if let sender: String = callMessage.sender {
            let senderDisplayName: String = Profile.displayName(db, id: sender, threadVariant: .contact)
            notificationContent.body = "\(senderDisplayName) is calling..."
        }
        else {
            notificationContent.body = "Incoming call..."
        }
        
        let identifier = self.request?.identifier ?? UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: notificationContent, trigger: nil)
        let semaphore = DispatchSemaphore(value: 0)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                SNLog("Failed to add notification request due to error:\(error)")
            }
            semaphore.signal()
        }
        semaphore.wait()
        SNLog("Add remote notification request")
    }

    private func handleFailure(for content: UNMutableNotificationContent) {
        // Suspend the database
        NotificationCenter.default.post(name: Database.suspendNotification, object: self)
        
        content.body = "You've got a new message"
        content.title = "Session"
        let userInfo: [String:Any] = [ NotificationServiceExtension.isFromRemoteKey : true ]
        content.userInfo = userInfo
        contentHandler!(content)
    }
    
    // MARK: - Poll for open groups
    
    private func pollForOpenGroups() -> [Promise<Void>] {
        let promises: [Promise<Void>] = Storage.shared
            .read { db in
                // The default room promise creates an OpenGroup with an empty `roomToken` value,
                // we don't want to start a poller for this as the user hasn't actually joined a room
                try OpenGroup
                    .select(.server)
                    .filter(OpenGroup.Columns.roomToken != "")
                    .filter(OpenGroup.Columns.isActive)
                    .distinct()
                    .asRequest(of: String.self)
                    .fetchSet(db)
            }
            .defaulting(to: [])
            .map { server in
                OpenGroupAPI.Poller(for: server)
                    .poll(calledFromBackgroundPoller: true, isPostCapabilitiesRetry: false)
                    .timeout(
                        seconds: 20,
                        timeoutError: NotificationServiceError.timeout
                    )
            }
        
        return promises
    }
    
    private enum NotificationServiceError: Error {
        case timeout
    }
}
