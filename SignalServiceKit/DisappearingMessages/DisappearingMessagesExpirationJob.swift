//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public final class DisappearingMessagesExpirationJob: ExpirationJob<TSMessage> {
    private let interactionDeleteManager: InteractionDeleteManager

    init(
        dateProvider: @escaping DateProvider,
        db: DB,
        interactionDeleteManager: InteractionDeleteManager,
    ) {
        self.interactionDeleteManager = interactionDeleteManager

        super.init(
            dateProvider: dateProvider,
            db: db,
            logger: PrefixedLogger(prefix: "[DisappearingMessagesExpJob]"),
        )
    }

    // MARK: -

    override public func nextExpiringElement(tx: DBReadTransaction) -> TSMessage? {
        return InteractionFinder.nextExpiringMessage(transaction: tx)
    }

    override public func expirationDate(ofElement message: TSMessage) -> Date {
        return Date(millisecondsSince1970: message.expiresAt)
    }

    override public func deleteExpiredElement(_ message: TSMessage, tx: DBWriteTransaction) {
        interactionDeleteManager.delete(message, sideEffects: .default(), tx: tx)
    }

    // MARK: -

    public func startExpiration(
        forMessage message: TSMessage,
        expirationStartedAt: UInt64,
        tx: DBWriteTransaction,
    ) {
        guard message.shouldStartExpireTimer() else { return }

        // Don't clobber if multiple actions simultaneously triggered expiration.
        if message.expireStartedAt == 0 || message.expireStartedAt > expirationStartedAt {
            message.updateWithExpireStarted(at: expirationStartedAt, transaction: tx)
        }

        restart()
    }
}

// MARK: -

@objc
public class DisappearingMessagesExpirationJobObjcBridge: NSObject {
    @objc
    static func startExpiration(
        forMessage message: TSMessage,
        expirationStartedAt: UInt64,
        tx: DBWriteTransaction
    ) {
        DependenciesBridge.shared.disappearingMessagesExpirationJob
            .startExpiration(
                forMessage: message,
                expirationStartedAt: expirationStartedAt,
                tx: tx,
            )
    }
}
