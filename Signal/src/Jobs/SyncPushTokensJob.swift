//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit

@objc(OWSSyncPushTokensJob)
class SyncPushTokensJob: NSObject {

    @objc
    public static let PushTokensDidChange = Notification.Name("PushTokensDidChange")

    private let uploadOnlyIfStale: Bool

    required init(uploadOnlyIfStale: Bool) {
        self.uploadOnlyIfStale = uploadOnlyIfStale
    }

    private static let hasUploadedTokensOnce = AtomicBool(false)

    func run() -> Promise<Void> {
        Logger.info("Starting.")

        return firstly {
            return self.pushRegistrationManager.requestPushTokens()
        }.then(on: .global()) { (pushToken: String, voipToken: String?) -> Promise<Void> in
            Logger.info("Fetched pushToken: \(redact(pushToken)), voipToken: \(redact(voipToken))")

            var shouldUploadTokens = false

            if self.preferences.getPushToken() != pushToken || self.preferences.getVoipToken() != voipToken {
                Logger.info("Push tokens changed.")
                shouldUploadTokens = true
            } else if !self.uploadOnlyIfStale {
                Logger.info("Forced uploading, even though tokens didn't change.")
                shouldUploadTokens = true
            } else if Self.appVersion.lastAppVersion != Self.appVersion.currentAppReleaseVersion {
                Logger.info("Uploading due to fresh install or app upgrade.")
                shouldUploadTokens = true
            } else if !Self.hasUploadedTokensOnce.get() {
                Logger.info("Uploading for app launch.")
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

                Self.hasUploadedTokensOnce.set(true)
            }
        }.done(on: .global()) {
            Logger.info("completed successfully.")
        }
    }

    // MARK: - objc wrappers, since objc can't use swift parameterized types

    @objc
    class func run() {
        run(uploadOnlyIfStale: true)
    }

    @objc
    class func run(uploadOnlyIfStale: Bool) {
        firstly {
            SyncPushTokensJob(uploadOnlyIfStale: uploadOnlyIfStale).run()
        }.done(on: .global()) {
            Logger.info("completed successfully.")
        }.catch(on: .global()) { error in
            Logger.error("Error: \(error).")
        }
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

            // Tokens should now be aligned with stored tokens.
            owsAssertDebug(pushToken == self.preferences.getPushToken())
        }

        if voipToken != self.preferences.getVoipToken() {
            Logger.info("Recording new voip token")
            self.preferences.setVoipToken(voipToken)
            didTokensChange = true

            // Tokens should now be aligned with stored tokens.
            owsAssertDebug(voipToken == self.preferences.getVoipToken())
        }

        if didTokensChange {
            NotificationCenter.default.postNotificationNameAsync(SyncPushTokensJob.PushTokensDidChange, object: nil)
        }
    }
}

private func redact(_ string: String?) -> String {
    guard let string = string else { return "nil" }
    return OWSIsDebugBuild() ? string : "[ REDACTED \(string.prefix(2))...\(string.suffix(2)) ]"
}
