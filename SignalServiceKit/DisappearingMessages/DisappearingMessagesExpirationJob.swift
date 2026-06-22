//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public final class DisappearingMessagesExpirationJob: ExpirationJob<ExpiringInteraction> {
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

    override public func nextExpiringElement(tx: DBReadTransaction) -> ExpiringInteraction? {
        return InteractionFinder.nextExpiringInteraction(transaction: tx)
    }

    override public func expirationDate(ofElement interaction: ExpiringInteraction) -> Date {
        return Date(millisecondsSince1970: interaction.expiresAt)
    }

    override public func deleteExpiredElement(_ interaction: ExpiringInteraction, tx: DBWriteTransaction) {
        interactionDeleteManager.delete(
            interaction,
            sideEffects: .custom(associatedCallDelete: .localDeleteOnly),
            tx: tx,
        )
    }

    // MARK: -

    public func startExpiration(
        for interaction: ExpiringInteraction,
        expirationStartedAt: UInt64,
        tx: DBWriteTransaction,
    ) {
        guard interaction.shouldStartExpireTimer() else { return }

        // Don't clobber if multiple actions simultaneously triggered expiration.
        if interaction.expireStartedAt == 0 || interaction.expireStartedAt > expirationStartedAt {
            interaction.updateWithExpireStarted(at: expirationStartedAt, transaction: tx)
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
        tx: DBWriteTransaction,
    ) {
        DependenciesBridge.shared.disappearingMessagesExpirationJob
            .startExpiration(
                for: message,
                expirationStartedAt: expirationStartedAt,
                tx: tx,
            )
    }
}
