//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public final class OWSDecryptionPlaceholderExpirationJob: ExpirationJob<OWSRecoverableDecryptionPlaceholder> {
    private let interactionDeleteManager: InteractionDeleteManager
    private let messageTimestampGenerator: MessageTimestampGenerator
    private let notificationPresenter: NotificationPresenter

    init(
        dateProvider: @escaping DateProvider,
        db: DB,
        interactionDeleteManager: InteractionDeleteManager,
        messageTimestampGenerator: MessageTimestampGenerator,
        notificationPresenter: NotificationPresenter,
    ) {
        self.interactionDeleteManager = interactionDeleteManager
        self.messageTimestampGenerator = messageTimestampGenerator
        self.notificationPresenter = notificationPresenter

        super.init(
            dateProvider: dateProvider,
            db: db,
            logger: PrefixedLogger(prefix: "[DecryptionPlaceholderExpJob]"),
        )
    }

    override public func nextExpiringElement(tx: DBReadTransaction) -> OWSRecoverableDecryptionPlaceholder? {
        return InteractionFinder.nextExpiringPlaceholder(tx: tx)
    }

    override public func expirationDate(ofElement placeholder: OWSRecoverableDecryptionPlaceholder) -> Date {
        return placeholder.expirationDate
    }

    override public func deleteExpiredElement(_ placeholder: OWSRecoverableDecryptionPlaceholder, tx: DBWriteTransaction) {
        logger.warn("Replacing decryption placeholder \(placeholder.timestamp) with error.")

        interactionDeleteManager.delete(placeholder, sideEffects: .default(), tx: tx)

        guard let thread = placeholder.thread(tx: tx) else {
            return
        }

        let errorMessage: TSErrorMessage = .failedDecryption(
            thread: thread,
            timestamp: messageTimestampGenerator.generateTimestamp(),
            sender: placeholder.sender,
        )
        errorMessage.anyInsert(transaction: tx)

        notificationPresenter.notifyUser(forErrorMessage: errorMessage, thread: thread, transaction: tx)
    }
}
