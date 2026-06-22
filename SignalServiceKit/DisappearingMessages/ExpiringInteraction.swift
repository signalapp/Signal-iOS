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

protocol ExpiringCallInteraction: ExpiringInteraction, OWSReadTracking {
    var expireStartedAt: UInt64 { get set }
}

extension ExpiringCallInteraction {
    private var hasExpiration: Bool { expiresInSeconds > 0 }
    private var hasExpirationStarted: Bool { hasExpiration && expireStartedAt > 0 }

    public func shouldStartExpireTimer() -> Bool {
        return hasExpirationStarted || (hasExpiration && wasRead)
    }

    public func updateWithExpireStarted(at expirationStartedAt: UInt64, transaction tx: DBWriteTransaction) {
        owsAssertDebug(expirationStartedAt > 0)
        anyUpdate(transaction: tx) { interaction in
            guard let interaction = interaction as? Self else { return }
            interaction.expireStartedAt = expirationStartedAt
        }
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

    func startOrUpdateExpiration(readTimestamp: UInt64, tx: DBWriteTransaction) {
        guard RemoteConfig.current.disappearingCalls else { return }
        DependenciesBridge.shared.disappearingMessagesExpirationJob.startExpiration(
            for: self,
            expirationStartedAt: readTimestamp,
            tx: tx,
        )
    }
}

extension TSMessage: ExpiringInteraction {}
