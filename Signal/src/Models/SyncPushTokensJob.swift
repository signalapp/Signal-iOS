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
    var uploadOnlyIfStale = true
    // useful to ensure promise runs to completion
    var retainCycle: SyncPushTokensJob?

    required init(pushManager: PushManager, accountManager: AccountManager, preferences: PropertyListPreferences) {
        self.pushManager = pushManager
        self.accountManager = accountManager
        self.preferences = preferences
    }

    @objc class func run(pushManager: PushManager, accountManager: AccountManager, preferences: PropertyListPreferences) -> AnyPromise {
        let job = self.init(pushManager: pushManager, accountManager: accountManager, preferences: preferences)
        return AnyPromise(job.run())
    }

    @objc func run() -> AnyPromise {
        return AnyPromise(run())
    }

    func run() -> Promise<Void> {
        Logger.debug("\(TAG) Starting.")
        // Make sure we don't GC until completion.
        self.retainCycle = self

        // Required to potentially prompt user for notifications settings
        // before `requestPushTokens` will return.
        self.pushManager.validateUserNotificationSettings()

        return self.requestPushTokens().then { (pushToken: String, voipToken: String) in
            var shouldUploadTokens = !self.uploadOnlyIfStale
            if self.preferences.getPushToken() != pushToken || self.preferences.getVoipToken() != voipToken {
                Logger.debug("\(self.TAG) push tokens changed.")
                shouldUploadTokens = true
            }

            guard shouldUploadTokens else {
                Logger.info("\(self.TAG) skipping push token upload")
                return Promise(value: ())
            }

            Logger.info("\(self.TAG) Sending new tokens to account servers.")
            return self.accountManager.updatePushTokens(pushToken:pushToken, voipToken:voipToken).then {
                Logger.info("\(self.TAG) Recording tokens locally.")
                return self.recordNewPushTokens(pushToken:pushToken, voipToken:voipToken)
            }
        }.always {
            self.retainCycle = nil
        }
    }

    private func requestPushTokens() -> Promise<(pushToken: String, voipToken: String)> {
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

        // TODO code cleanup: convert to `return Promise(value: nil)` and test.
        return Promise { fulfill, reject in  fulfill(); }
    }
}
