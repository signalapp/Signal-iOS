//  Created by Michael Kirk on 12/28/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation

/**
 * Present call related notifications to the user.
 */
@objc(OWSCallNotificationsAdapter)
class CallNotificationsAdapter: NSObject {

    let TAG = "[CallNotificationsAdapter]"
    let adaptee: OWSCallNotificationsAdaptee

    override init() {
        // TODO We can't mix UILocalNotification (NotificationManager) with the UNNotifications
        // Because registering message categories in one, clobbers the registered categories from the other
        // We have to first port *all* the existing UINotification categories to UNNotifications
        // which is a good thing to do, but in trying to limit the scope of changes that's been 
        // left out for now.
//        if #available(iOS 10.0, *) {
//            adaptee = UserNotificationsAdaptee()
//        } else {
            adaptee = NotificationsManager()
//        }
    }

    func presentIncomingCall(_ call: SignalCall, callerName: String) {
        Logger.debug("\(TAG) in \(#function)")
        adaptee.presentIncomingCall(call, callerName: callerName)
    }

    func presentMissedCall(_ call: SignalCall, callerName: String) {
        Logger.debug("\(TAG) in \(#function)")
        adaptee.presentMissedCall(call, callerName: callerName)
    }
}
