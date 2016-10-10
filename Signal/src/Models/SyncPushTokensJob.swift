//  Created by Michael Kirk on 10/26/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation
import PromiseKit

@objc(OWSSyncPushTokensJob)
class SyncPushTokensJob : NSObject {
    let TAG = "[SyncPushTokensJob]"
    let pushManager: PushManager
    let accountManager: AccountManager
    let preferences: PropertyListPreferences

    required init(pushManager: PushManager, accountManager: AccountManager, preferences: PropertyListPreferences) {
        self.pushManager = pushManager
        self.accountManager = accountManager
        self.preferences = preferences
    }

    @objc func run() -> AnyPromise {
        return AnyPromise(run())
    }

    func run() -> Promise<Void> {
        Logger.debug("\(TAG) Starting.")

        // Required to potentially prompt user for notifications settings
        // before `requestPushTokens` will return.
        self.pushManager.validateUserNotificationSettings()

        return self.requestPushTokens().then { (pushToken: String, voipToken: String) in
            if self.preferences.getPushToken() == pushToken && self.preferences.getVoipToken() == voipToken {
                Logger.debug("\(self.TAG) push tokens are already up to date.")
                return Promise { fulfill, reject in  fulfill(); }
            }

            Logger.info("\(self.TAG) push tokens changed. Updating...")
            return self.accountManager.updatePushTokens(pushToken:pushToken, voipToken:voipToken).then {
                return self.recordNewPushTokens(pushToken:pushToken, voipToken:voipToken);
            }
        }
    }

    func requestPushTokens() -> Promise<(pushToken: String, voipToken: String)> {
        return Promise { fulfill, reject in
            self.pushManager.requestPushToken(
                success: { (pushToken: String, voipToken: String) in
                    fulfill((pushToken:pushToken, voipToken:voipToken))
                },
                failure: reject
            );
        }
    }

    private func recordNewPushTokens(pushToken: String, voipToken: String) -> Promise<Void> {
        Logger.info("\(TAG) Recording new push tokens.")

        if (pushToken != self.preferences.getPushToken()) {
            Logger.info("\(TAG) Recording new plain push token")
            self.preferences.setPushToken(pushToken);
        }

        if (voipToken != self.preferences.getVoipToken()) {
            Logger.info("\(TAG) Recording new voip token")
            self.preferences.setVoipToken(voipToken);
        }

        return Promise { fulfill, reject in  fulfill(); }
    }
}
