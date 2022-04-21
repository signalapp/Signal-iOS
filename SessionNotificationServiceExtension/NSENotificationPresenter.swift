// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import UserNotifications
import SignalUtilitiesKit
import SessionMessagingKit

public class NSENotificationPresenter: NSObject, NotificationsProtocol {
    
    public func notifyUser(_ db: Database, for interaction: Interaction, in thread: SessionThread, isBackgroundPoll: Bool) {
        guard thread.notificationMode != .none else { return }
        
        let isMessageRequest = thread.isMessageRequest(db)
        
        // If the thread is a message request and the user hasn't hidden message requests then we need
        // to check if this is the only message request thread (group threads can't be message requests
        // so just ignore those and if the user has hidden message requests then we want to show the
        // notification regardless of how many message requests there are)
        if thread.variant == .contact {
            if isMessageRequest && !db[.hasHiddenMessageRequests] {
                let numMessageRequestThreads: Int? = try? SessionThread.messageRequestThreads(db)
                    .fetchCount(db)
                
                // Allow this to show a notification if there are no message requests (ie. this is the first one)
                guard (numMessageRequestThreads ?? 0) == 0 else { return }
            }
            else if isMessageRequest && db[.hasHiddenMessageRequests] {
                // If there are other interactions on this thread already then don't show the notification
                if ((try? thread.interactions.fetchCount(db)) ?? 0) > 1 { return }
                
                db[.hasHiddenMessageRequests] = false
            }
        }
        
        let senderPublicKey: String = interaction.authorId
        let userPublicKey: String = getUserHexEncodedPublicKey()
        
        guard senderPublicKey != userPublicKey else {
            // Ignore PNs for messages sent by the current user
            // after handling the message. Otherwise the closed
            // group self-send messages won't show.
            return
        }
        
        let senderName = Profile.displayName(db, id: senderPublicKey, thread: thread)
        
        var notificationTitle = senderName
        
        if thread.variant == .closedGroup || thread.variant == .openGroup {
            if thread.notificationMode == .mentionsOnly && !interaction.isUserMentioned(db) {
                // Ignore PNs if the group is set to only notify for mentions
                return
            }
            
            var groupName = thread.name(db)
            if groupName.count < 1 {
                groupName = MessageStrings.newGroupDefaultTitle
            }
            notificationTitle = String(
                format: NotificationStrings.incomingGroupMessageTitleFormat,
                senderName,
                groupName
            )
        }
        
        
        let snippet = interaction.previewText(db)
            .filterForDisplay?
            .replacingMentions(for: thread.id) ?? "APN_Message".localized()
        
        var userInfo: [String: Any] = [ NotificationServiceExtension.isFromRemoteKey: true ]
        userInfo[NotificationServiceExtension.threadIdKey] = thread.id
        
        let notificationContent = UNMutableNotificationContent()
        notificationContent.userInfo = userInfo
        notificationContent.sound = OWSSounds.notificationSound(forThreadId: thread.id)
            .notificationSound(isQuiet: false)
        
        // Badge Number
        let newBadgeNumber = CurrentAppContext().appUserDefaults().integer(forKey: "currentBadgeNumber") + 1
        notificationContent.badge = NSNumber(value: newBadgeNumber)
        CurrentAppContext().appUserDefaults().set(newBadgeNumber, forKey: "currentBadgeNumber")
        
        // Title & body
        let notificationsPreference = Environment.shared.preferences!.notificationPreviewType()
        switch notificationsPreference {
        case .namePreview:
            notificationContent.title = notificationTitle
            notificationContent.body = snippet
        case .nameNoPreview:
            notificationContent.title = notificationTitle
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
            notificationContent.body = "MESSAGE_REQUESTS_NOTIFICATION".localized()
        }
        
        // Add request
        let identifier = interaction.notificationIdentifier(isBackgroundPoll: isBackgroundPoll)
        let request = UNNotificationRequest(identifier: identifier, content: notificationContent, trigger: nil)
        
        SNLog("Add remote notification request: \(notificationContent.body)")
        let semaphore = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                SNLog("Failed to add notification request due to error:\(error)")
            }
            semaphore.signal()
        }
        semaphore.wait()
        SNLog("Finish adding remote notification request")
    }
    
    public func cancelNotifications(identifiers: [String]) {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    
    public func clearAllNotifications() {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }
}

private extension String {
    
    func replacingMentions(for threadID: String) -> String {
        var result = self
        let regex = try! NSRegularExpression(pattern: "@[0-9a-fA-F]{66}", options: [])
        var mentions: [(range: NSRange, publicKey: String)] = []
        var m0 = regex.firstMatch(in: result, options: .withoutAnchoringBounds, range: NSRange(location: 0, length: result.utf16.count))
        while let m1 = m0 {
            let publicKey = String((result as NSString).substring(with: m1.range).dropFirst()) // Drop the @
            var matchEnd = m1.range.location + m1.range.length
            
            if let displayName: String = Profile.displayNameNoFallback(id: publicKey) {
                result = (result as NSString).replacingCharacters(in: m1.range, with: "@\(displayName)")
                mentions.append((range: NSRange(location: m1.range.location, length: displayName.utf16.count + 1), publicKey: publicKey)) // + 1 to include the @
                matchEnd = m1.range.location + displayName.utf16.count
            }
            m0 = regex.firstMatch(in: result, options: .withoutAnchoringBounds, range: NSRange(location: matchEnd, length: result.utf16.count - matchEnd))
        }
        return result
    }
}

