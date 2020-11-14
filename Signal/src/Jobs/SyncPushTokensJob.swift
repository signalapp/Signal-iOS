//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import PromiseKit
import SignalServiceKit

@objc(OWSSyncPushTokensJob)
class SyncPushTokensJob: NSObject {

    @objc
    public static let PushTokensDidChange = Notification.Name("PushTokensDidChange")

    // MARK: Dependencies
    let accountManager: AccountManager
    let preferences: OWSPreferences
    var pushRegistrationManager: PushRegistrationManager {
        return PushRegistrationManager.shared
    }

    @objc var uploadOnlyIfStale = true

    @objc
    required init(accountManager: AccountManager, preferences: OWSPreferences) {
        self.accountManager = accountManager
        self.preferences = preferences
    }

    private class func run(accountManager: AccountManager, preferences: OWSPreferences) -> Promise<Void> {
        let job = self.init(accountManager: accountManager, preferences: preferences)
        return job.run()
    }

    func run() -> Promise<Void> {
        Logger.info("Starting.")

        return firstly {
            return self.pushRegistrationManager.requestPushTokens()
        }.then { (pushToken: String, voipToken: String) -> Promise<Void> in
            Logger.info("finished: requesting push tokens")
            var shouldUploadTokens = false

            if self.preferences.getPushToken() != pushToken || self.preferences.getVoipToken() != voipToken {
                Logger.debug("Push tokens changed.")
                shouldUploadTokens = true
            } else if !self.uploadOnlyIfStale {
                Logger.debug("Forced uploading, even though tokens didn't change.")
                shouldUploadTokens = true
            }

            if AppVersion.shared().lastAppVersion != AppVersion.shared().currentAppVersion {
                Logger.info("Uploading due to fresh install or app upgrade.")
                shouldUploadTokens = true
            }

            guard shouldUploadTokens else {
                Logger.info("No reason to upload pushToken: \(redact(pushToken)), voipToken: \(redact(voipToken))")
                return Promise.value(())
            }

            Logger.warn("uploading tokens to account servers. pushToken: \(redact(pushToken)), voipToken: \(redact(voipToken))")
            return firstly {
                self.accountManager.updatePushTokens(pushToken: pushToken, voipToken: voipToken)
            }.done(on: .global()) { _ in
                self.recordPushTokensLocally(pushToken: pushToken, voipToken: voipToken)
            }
        }.done {
            Logger.info("completed successfully.")
        }
    }

    // MARK: - objc wrappers, since objc can't use swift parameterized types

    @objc
    class func run(accountManager: AccountManager, preferences: OWSPreferences) {
        firstly {
            self.run(accountManager: accountManager, preferences: preferences)
        }.done {
            Logger.info("completed successfully.")
        }.catch { error in
            Logger.error("Error: \(error).")
        }
    }

    @objc
    func run() -> AnyPromise {
        let promise: Promise<Void> = self.run()
        return AnyPromise(promise)
    }

    // MARK: 

    private func recordPushTokensLocally(pushToken: String, voipToken: String) {
        assert(!Thread.isMainThread)
        Logger.warn("Recording push tokens locally. pushToken: \(redact(pushToken)), voipToken: \(redact(voipToken))")

        var didTokensChange = false

        if pushToken != self.preferences.getPushToken() {
            Logger.info("Recording new plain push token")
            self.preferences.setPushToken(pushToken)
            didTokensChange = true
        }

        if voipToken != self.preferences.getVoipToken() {
            Logger.info("Recording new voip token")
            self.preferences.setVoipToken(voipToken)
            didTokensChange = true
        }

        if didTokensChange {
            NotificationCenter.default.postNotificationNameAsync(SyncPushTokensJob.PushTokensDidChange, object: nil)
        }
    }
}

private func redact(_ string: String) -> String {
    return OWSIsDebugBuild() ? string : "[ READACTED \(string.prefix(2))...\(string.suffix(2)) ]"
}
