//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class SyncPushTokensJob: NSObject {
    enum Mode {
        case normal
        case forceRotation
        case rotateIfEligible
    }

    private let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    private static let hasUploadedTokensOnce = AtomicBool(false, lock: .sharedGlobal)

    func run() async throws {
        switch mode {
        case .normal:
            // Don't rotate.
            return try await run(shouldRotateAPNSToken: false)
        case .forceRotation:
            // Always rotate
            return try await run(shouldRotateAPNSToken: true)
        case .rotateIfEligible:
            let shouldRotate = SSKEnvironment.shared.databaseStorageRef.read { tx -> Bool in
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
        let regResult = try await AppEnvironment.shared.pushRegistrationManagerRef.requestPushTokens(forceRotation: shouldRotateAPNSToken)

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            if shouldRotateAPNSToken {
                APNSRotationStore.didRotateAPNSToken(transaction: tx)
            }
        }

        let pushToken = regResult.apnsToken

        let reason: String

        if SSKEnvironment.shared.preferencesRef.pushToken != pushToken {
            reason = "changed"
        } else if !Self.hasUploadedTokensOnce.get() {
            reason = "launched"
        } else {
            Logger.info("No reason to upload pushToken: \(redact(pushToken))")
            return
        }

        Logger.warn("Uploading push token; reason: \(reason), pushToken: \(redact(pushToken))")
        try await self.updatePushTokens(pushToken: pushToken)

        await recordPushTokensLocally(pushToken: pushToken)

        Self.hasUploadedTokensOnce.set(true)
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

    private func recordPushTokensLocally(pushToken: String) async {
        assert(!Thread.isMainThread)

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            Logger.warn("Recording push tokens locally. pushToken: \(redact(pushToken))")

            if pushToken != SSKEnvironment.shared.preferencesRef.getPushToken(tx: tx) {
                Logger.info("Recording new plain push token")
                SSKEnvironment.shared.preferencesRef.setPushToken(pushToken, tx: tx)
            }
        }
    }

    // MARK: - Requests

    private func updatePushTokens(pushToken: String) async throws {
        return try await Retry.performWithBackoff(maxAttempts: 3) {
            let request = OWSRequestFactory.registerForPushRequest(apnsToken: pushToken)
            _ = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)
        }
    }
}

private func redact(_ string: String?) -> String {
    guard let string = string else { return "nil" }
#if DEBUG
    return string
#else
    return "\(string.prefix(2))…\(string.suffix(2))"
#endif
}
