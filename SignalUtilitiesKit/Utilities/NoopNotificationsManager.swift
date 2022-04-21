//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SessionMessagingKit

@objc
public class NoopNotificationsManager: NSObject, NotificationsProtocol {

    public func notifyUser(_ db: Database, for interaction: Interaction, in thread: SessionThread, isBackgroundPoll: Bool) {
        owsFailDebug("")
    }
    
    public func cancelNotifications(identifiers: [String]) {
        owsFailDebug("")
    }

    public func clearAllNotifications() {
        Logger.warn("clearAllNotifications")
    }
}
