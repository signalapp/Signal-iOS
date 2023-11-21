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

    func run() async throws {
        Logger.info("Starting.")

        switch mode {
        case .normal, .forceUpload:
            // Don't rotate.
            return try await run(shouldRotateAPNSToken: false)
        case .forceRotation:
            // Always rotate
            return try await run(shouldRotateAPNSToken: true)
        case .rotateIfEligible:
            let shouldRotate = databaseStorage.read { tx -> Bool in
                return APNSRotationStore.canRotateAPNSToken(transaction: tx)
            }
            guard shouldRotate else {
                // If we aren't rotating, no-op.
                return
            }
            return try await run(shouldRotateAPNSToken: true)
        }
    }

    public typealias ApnRegistrationId = RegistrationRequestFactory.ApnRegistrationId

    private func run(shouldRotateAPNSToken: Bool) async throws {
        let regResult = try await pushRegistrationManager.requestPushTokens(forceRotation: shouldRotateAPNSToken).awaitable()

        await databaseStorage.awaitableWrite { tx in
            if shouldRotateAPNSToken {
                APNSRotationStore.didRotateAPNSToken(transaction: tx)
            }
        }

        let (pushToken, voipToken) = (regResult.apnsToken, regResult.voipToken)

        Logger.info("Fetched pushToken: \(redact(pushToken)), voipToken: \(redact(voipToken))")

        var shouldUploadTokens = false

        if preferences.pushToken != pushToken || preferences.voipToken != voipToken {
            Logger.info("Push tokens changed.")
            shouldUploadTokens = true
        } else if mode == .forceUpload {
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
            return
        }

        Logger.warn("uploading tokens to account servers. pushToken: \(redact(pushToken)), voipToken: \(redact(voipToken))")
        try await self.updatePushTokens(pushToken: pushToken, voipToken: voipToken, auth: auth)

        await recordPushTokensLocally(pushToken: pushToken, voipToken: voipToken)

        Self.hasUploadedTokensOnce.set(true)

        Logger.info("completed successfully.")
    }

    class func run(mode: Mode = .normal) {
        Task {
            do {
                try await SyncPushTokensJob(mode: mode).run()
            } catch {
                Logger.error("Error: \(error).")
            }
        }
    }

    // MARK: 

    private func recordPushTokensLocally(pushToken: String, voipToken: String?) async {
        assert(!Thread.isMainThread)

        await databaseStorage.awaitableWrite { tx in
            Logger.warn("Recording push tokens locally. pushToken: \(redact(pushToken)), voipToken: \(redact(voipToken))")

            if pushToken != self.preferences.getPushToken(tx: tx) {
                Logger.info("Recording new plain push token")
                self.preferences.setPushToken(pushToken, tx: tx)
            }
            if voipToken != self.preferences.getVoipToken(tx: tx) {
                Logger.info("Recording new voip token")
                self.preferences.setVoipToken(voipToken, tx: tx)
            }
        }
    }

    // MARK: - Requests

    func updatePushTokens(pushToken: String, voipToken: String?, auth: ChatServiceAuth) async throws {
        let request = OWSRequestFactory.registerForPushRequest(
            withPushIdentifier: pushToken,
            voipIdentifier: voipToken
        )
        request.setAuth(auth)
        return try await updatePushTokens(request: request, remainingRetries: 3)
    }

    private func updatePushTokens(
        request: TSRequest,
        remainingRetries: Int
    ) async throws {
        do {
            _ = try await networkManager
                .makePromise(request: request)
                .awaitable()
            return
        } catch let error {
            if remainingRetries > 0 {
                return try await updatePushTokens(
                    request: request,
                    remainingRetries: remainingRetries - 1
                )
            } else {
                owsFailDebugUnlessNetworkFailure(error)
                throw error
            }
        }
    }
}

private func redact(_ string: String?) -> String {
    guard let string = string else { return "nil" }
    return OWSIsDebugBuild() ? string : "[ REDACTED \(string.prefix(2))...\(string.suffix(2)) ]"
}
