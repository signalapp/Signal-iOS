//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit

@objc(OWSSyncPushTokensJob)
class SyncPushTokensJob: NSObject {

    @objc
    public static let PushTokensDidChange = Notification.Name("PushTokensDidChange")

    @objc var uploadOnlyIfStale = true

    func run() -> Promise<Void> {
        Logger.info("Starting.")

        return firstly {
            return self.pushRegistrationManager.requestPushTokens()
        }.then { (pushToken: String, voipToken: String?) -> Promise<Void> in
            Logger.info("finished: requesting push tokens")
            var shouldUploadTokens = false

            if self.preferences.getPushToken() != pushToken || self.preferences.getVoipToken() != voipToken {
                Logger.debug("Push tokens changed.")
                shouldUploadTokens = true
            } else if !self.uploadOnlyIfStale {
                Logger.debug("Forced uploading, even though tokens didn't change.")
                shouldUploadTokens = true
            }

            if Self.appVersion.lastAppVersion != Self.appVersion.currentAppReleaseVersion {
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
    class func run() {
        firstly {
            SyncPushTokensJob().run()
        }.done {
            Logger.info("completed successfully.")
        }.catch { error in
            Logger.error("Error: \(error).")
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    func run() -> AnyPromise {
        AnyPromise(self.run())
    }

    // MARK: 

    private func recordPushTokensLocally(pushToken: String, voipToken: String?) {
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

private func redact(_ string: String?) -> String {
    guard let string = string else { return "nil" }
    return OWSIsDebugBuild() ? string : "[ READACTED \(string.prefix(2))...\(string.suffix(2)) ]"
}
