//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSUserNotificationActionHandler)
public class UserNotificationActionHandler: NSObject {

    var actionHandler: NotificationActionHandler {
        return NotificationActionHandler.shared
    }

    @objc
    func handleNotificationResponse( _ response: UNNotificationResponse, completionHandler: @escaping () -> Void) {
        AssertIsOnMainThread()
        firstly {
            try handleNotificationResponse(response)
        }.done {
            completionHandler()
        }.catch { error in
            completionHandler()
            owsFailDebug("error: \(error)")
            Logger.error("error: \(error)")
        }
    }

    func handleNotificationResponse( _ response: UNNotificationResponse) throws -> Promise<Void> {
        AssertIsOnMainThread()
        assert(AppReadiness.isAppReady)

        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            Logger.debug("default action")
            return try actionHandler.showThread(userInfo: userInfo)
        case UNNotificationDismissActionIdentifier:
            // TODO - mark as read?
            Logger.debug("dismissed notification")
            return Promise.value(())
        default:
            // proceed
            break
        }

        guard let action = UserNotificationConfig.action(identifier: response.actionIdentifier) else {
            throw NotificationError.failDebug("unable to find action for actionIdentifier: \(response.actionIdentifier)")
        }

        switch action {
        case .answerCall:
            return try actionHandler.answerCall(userInfo: userInfo)
        case .callBack:
            return try actionHandler.callBack(userInfo: userInfo)
        case .declineCall:
            return try actionHandler.declineCall(userInfo: userInfo)
        case .markAsRead:
            return try actionHandler.markAsRead(userInfo: userInfo)
        case .reply:
            guard let textInputResponse = response as? UNTextInputNotificationResponse else {
                throw NotificationError.failDebug("response had unexpected type: \(response)")
            }

            return try actionHandler.reply(userInfo: userInfo, replyText: textInputResponse.userText)
        case .showThread:
            return try actionHandler.showThread(userInfo: userInfo)
        }
    }
}
