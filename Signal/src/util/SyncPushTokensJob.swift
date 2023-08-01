//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit

class SyncPushTokensJob: NSObject {
    enum Mode {
        case normal
        case forceUpload
        case forceRotation
        case rotateIfEligible
    }

    private let mode: Mode

    public let auth: ChatServiceAuth

    required init(mode: Mode, auth: ChatServiceAuth = .implicit()) {
        self.mode = mode
        self.auth = auth
    }

    private static let hasUploadedTokensOnce = AtomicBool(false)

    func run() -> Promise<Void> {
        Logger.info("Starting.")

        return firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            switch self.mode {
            case .normal, .forceUpload:
                // Don't rotate.
                return self.run(shouldRotateAPNSToken: false)
            case .forceRotation:
                // Always rotate
                return self.run(shouldRotateAPNSToken: true)
            case .rotateIfEligible:
                return Self.databaseStorage.read(PromiseNamespace.promise) { transaction -> Bool in
                    return APNSRotationStore.canRotateAPNSToken(transaction: transaction)
                }.then { shouldRotate in
                    if !shouldRotate {
                        // If we aren't rotating, no-op.
                        return Promise.value(())
                    }
                    return self.run(shouldRotateAPNSToken: true)
                }
            }
        }
    }

    private func run(shouldRotateAPNSToken: Bool) -> Promise<Void> {
        return firstly(on: DispatchQueue.main) {
            return self.pushRegistrationManager.requestPushTokens(
                forceRotation: shouldRotateAPNSToken
            ).map(on: DispatchQueue.main) {
                return (shouldRotateAPNSToken, $0)
            }
        }.then(on: DispatchQueue.global()) { (didRotate: Bool, regResult: (String, String?)) -> Promise<(pushToken: String, voipToken: String?)> in
            let (pushToken, voipToken) = regResult
            return Self.databaseStorage.write(.promise) { transaction in
                if shouldRotateAPNSToken {
                    APNSRotationStore.didRotateAPNSToken(transaction: transaction)
                }
                return (pushToken, voipToken)
            }
        }.then(on: DispatchQueue.global()) { (pushToken: String, voipToken: String?) -> Promise<Void> in
            Logger.info("Fetched pushToken: \(redact(pushToken)), voipToken: \(redact(voipToken))")

            var shouldUploadTokens = false

            if self.preferences.pushToken != pushToken || self.preferences.voipToken != voipToken {
                Logger.info("Push tokens changed.")
                shouldUploadTokens = true
            } else if self.mode == .forceUpload {
                Logger.info("Forced uploading, even though tokens didn't change.")
                shouldUploadTokens = true
            } else if AppVersionImpl.shared.lastAppVersion != AppVersionImpl.shared.currentAppReleaseVersion {
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
                switch self.auth.credentials {
                case .implicit:
                    return self.accountManager.updatePushTokens(pushToken: pushToken, voipToken: voipToken)
                case .explicit:
                    let request = OWSRequestFactory.registerForPushRequest(withPushIdentifier: pushToken, voipIdentifier: voipToken)
                    request.shouldHaveAuthorizationHeaders = true
                    request.setAuth(self.auth)
                    return self.accountManager.updatePushTokens(request: request)
                }
            }.done(on: DispatchQueue.global()) { _ in
                self.recordPushTokensLocally(pushToken: pushToken, voipToken: voipToken)

                Self.hasUploadedTokensOnce.set(true)
            }
        }.done(on: DispatchQueue.global()) {
            Logger.info("completed successfully.")
        }
    }

    class func run(mode: Mode = .normal) {
        firstly {
            SyncPushTokensJob(mode: mode).run()
        }.done(on: DispatchQueue.global()) {
            Logger.info("completed successfully.")
        }.catch(on: DispatchQueue.global()) { error in
            Logger.error("Error: \(error).")
        }
    }

    // MARK: 

    private func recordPushTokensLocally(pushToken: String, voipToken: String?) {
        assert(!Thread.isMainThread)
        Logger.warn("Recording push tokens locally. pushToken: \(redact(pushToken)), voipToken: \(redact(voipToken))")

        if pushToken != preferences.pushToken {
            Logger.info("Recording new plain push token")
            preferences.setPushToken(pushToken)

            // Tokens should now be aligned with stored tokens.
            owsAssertDebug(pushToken == preferences.pushToken)
        }

        if voipToken != preferences.voipToken {
            Logger.info("Recording new voip token")
            preferences.setVoipToken(voipToken)

            // Tokens should now be aligned with stored tokens.
            owsAssertDebug(voipToken == preferences.voipToken)
        }
    }
}

private func redact(_ string: String?) -> String {
    guard let string = string else { return "nil" }
    return OWSIsDebugBuild() ? string : "[ REDACTED \(string.prefix(2))...\(string.suffix(2)) ]"
}
