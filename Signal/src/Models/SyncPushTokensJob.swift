//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import PromiseKit

@objc(OWSSyncPushTokensJob)
class SyncPushTokensJob: NSObject {
    let TAG = "[SyncPushTokensJob]"

    // MARK: Dependencies
    let accountManager: AccountManager
    let preferences: PropertyListPreferences
    var uploadOnlyIfStale = true

    required init(accountManager: AccountManager, preferences: PropertyListPreferences) {
        self.accountManager = accountManager
        self.preferences = preferences
    }

    var pushRegistrationManager: PushRegistrationManager {
        return PushRegistrationManager.shared
    }

    class func run(accountManager: AccountManager, preferences: PropertyListPreferences) -> Promise<Void> {
        let job = self.init(accountManager: accountManager, preferences: preferences)
        return job.run()
    }

    func run() -> Promise<Void> {
        Logger.info("\(TAG) Starting.")

        let runPromise: Promise<Void> = DispatchQueue.main.promise {
            // HACK: no-op dispatch to work around a bug in PromiseKit/Swift which won't compile
            // when dispatching complex Promise types. We should eventually be able to delete the 
            // following two lines, skipping this no-op dispatch.
            return
        }.then {
            return self.pushRegistrationManager.requestPushTokens()
        }.then { (pushToken: String, voipToken: String) in
            Logger.info("\(self.TAG) finished: requesting push tokens")
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

            Logger.warn("\(self.TAG) Sending tokens to account servers. pushToken: \(pushToken), voipToken: \(voipToken)")
            return self.accountManager.updatePushTokens(pushToken:pushToken, voipToken:voipToken).then {
                Logger.info("\(self.TAG) updated push tokens with server")
                return self.recordNewPushTokens(pushToken:pushToken, voipToken:voipToken)
            }
        }.then {
            Logger.info("\(self.TAG) in \(#function): succeeded")
        }.catch { error in
            Logger.error("\(self.TAG) in \(#function): Failed with error: \(error).")
        }

        runPromise.retainUntilComplete()

        return runPromise
    }

    // MARK - objc wrappers, since objc can't use swift parameterized types

    @objc class func run(accountManager: AccountManager, preferences: PropertyListPreferences) -> AnyPromise {
        let promise: Promise<Void> = self.run(accountManager: accountManager, preferences: preferences)
        return AnyPromise(promise)
    }

    @objc func run() -> AnyPromise {
        let promise: Promise<Void> = self.run()
        return AnyPromise(promise)
    }

    private func recordNewPushTokens(pushToken: String, voipToken: String) -> Promise<Void> {
        Logger.warn("\(TAG) Recording uploaded push tokens locally. pushToken: \(pushToken), voipToken: \(voipToken)")

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
