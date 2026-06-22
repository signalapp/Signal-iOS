//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol ExpiringInteraction: TSInteraction {
    var expiresAt: UInt64 { get }

    var expiresInSeconds: UInt32 { get }

    var expireStartedAt: UInt64 { get }

    func shouldStartExpireTimer() -> Bool

    func updateWithExpireStarted(at expirationStartedAt: UInt64, transaction: DBWriteTransaction)
}

protocol ExpiringCallInteraction: ExpiringInteraction, OWSReadTracking {}

extension ExpiringCallInteraction {
    private var hasExpiration: Bool { expiresInSeconds > 0 }
    private var hasExpirationStarted: Bool { hasExpiration && expireStartedAt > 0 }

    public func shouldStartExpireTimer() -> Bool {
        return hasExpirationStarted || (hasExpiration && wasRead)
    }

    func startExpirationIfNecessary(transaction tx: DBWriteTransaction) {
        guard RemoteConfig.current.disappearingCalls else { return }
        guard
            shouldStartExpireTimer(),
            !hasExpirationStarted
        else { return }
        DependenciesBridge.shared.disappearingMessagesExpirationJob.startExpiration(
            for: self,
            expirationStartedAt: Date.ows_millisecondTimestamp(),
            tx: tx,
        )
    }
}

extension TSMessage: ExpiringInteraction {}
