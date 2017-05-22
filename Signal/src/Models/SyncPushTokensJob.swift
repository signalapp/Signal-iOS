//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSSyncPushTokensJob)
class SyncPushTokensJob: NSObject {
    let TAG = "[SyncPushTokensJob]"
    let pushManager: PushManager
    let accountManager: AccountManager
    let preferences: PropertyListPreferences
    let showAlerts: Bool
    var uploadOnlyIfStale = true

    required init(pushManager: PushManager, accountManager: AccountManager, preferences: PropertyListPreferences, showAlerts: Bool) {
        self.pushManager = pushManager
        self.accountManager = accountManager
        self.preferences = preferences
        self.showAlerts = showAlerts
    }

    @objc class func run(pushManager: PushManager, accountManager: AccountManager, preferences: PropertyListPreferences, showAlerts: Bool = false) {
        let job = self.init(pushManager: pushManager, accountManager: accountManager, preferences: preferences, showAlerts:showAlerts)
        job.run()
    }

    func run() {
        Logger.debug("\(TAG) Starting.")

        // Required to potentially prompt user for notifications settings
        // before `requestPushTokens` will return.
        self.pushManager.validateUserNotificationSettings()

        let runPromise: Promise<Void> = self.requestPushTokens().then { (pushToken: String, voipToken: String) in
            var shouldUploadTokens = false

            if self.preferences.getPushToken() != pushToken || self.preferences.getVoipToken() != voipToken {
                Logger.debug("\(self.TAG) Push tokens changed.")
                shouldUploadTokens = true
            } else if !self.uploadOnlyIfStale {
                Logger.debug("\(self.TAG) Uploading even though tokens didn't change.")
                shouldUploadTokens = true
            }

            Logger.warn("\(self.TAG) lastAppVersion: \(AppVersion.instance().lastAppVersion), currentAppVersion: \(AppVersion.instance().currentAppVersion)")
            if AppVersion.instance().lastAppVersion != AppVersion.instance().currentAppVersion {
                Logger.debug("\(self.TAG) Fresh install or app upgrade.")
                shouldUploadTokens = true
            }

            guard shouldUploadTokens else {
                Logger.warn("\(self.TAG) Skipping push token upload. pushToken: \(pushToken), voipToken: \(voipToken)")
                return Promise(value: ())
            }

            Logger.warn("\(self.TAG) Sending new tokens to account servers. pushToken: \(pushToken), voipToken: \(voipToken)")

            return self.accountManager.updatePushTokens(pushToken:pushToken, voipToken:voipToken).then {
                return self.recordNewPushTokens(pushToken:pushToken, voipToken:voipToken)
            }.then {
                Logger.debug("\(self.TAG) Successfully ran syncPushTokensJob.")
                if self.showAlerts {
                    OWSAlerts.showAlert(withTitle:NSLocalizedString("PUSH_REGISTER_SUCCESS", comment: "Title of alert shown when push tokens sync job succeeds."))
                }
                return Promise(value: ())
            }.catch { error in
                Logger.error("\(self.TAG) Failed to run syncPushTokensJob with error: \(error).")
                if self.showAlerts {
                    OWSAlerts.showAlert(withTitle:NSLocalizedString("REGISTRATION_BODY", comment: "Title of alert shown when push tokens sync job fails."))
                }
            }
        }

        runPromise.retainUntilComplete()
    }

    private func requestPushTokens() -> Promise<(pushToken: String, voipToken: String)> {
        return Promise { fulfill, reject in
            self.pushManager.requestPushToken(
                success: { (pushToken: String, voipToken: String) in
                    fulfill((pushToken:pushToken, voipToken:voipToken))
                },
                failure: reject
            )
        }
    }

    private func recordNewPushTokens(pushToken: String, voipToken: String) -> Promise<Void> {
        Logger.warn("\(TAG) Recording new push tokens. pushToken: \(pushToken), voipToken: \(voipToken)")

        if (pushToken != self.preferences.getPushToken()) {
            Logger.info("\(TAG) Recording new plain push token")
            self.preferences.setPushToken(pushToken)
        }

        if (voipToken != self.preferences.getVoipToken()) {
            Logger.info("\(TAG) Recording new voip token")
            self.preferences.setVoipToken(voipToken)
        }

        return Promise(value: ())
    }
}
