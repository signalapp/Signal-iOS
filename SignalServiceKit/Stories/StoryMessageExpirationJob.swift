//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public final class StoryMessageExpirationJob: ExpirationJob<StoryMessage> {

    init(
        dateProvider: @escaping DateProvider,
        db: DB,
    ) {
        super.init(
            dateProvider: dateProvider,
            db: db,
            logger: PrefixedLogger(prefix: "[StoryMessageExpJob]"),
        )
    }

    // MARK: -

    override public func nextExpiringElement(tx: DBReadTransaction) -> StoryMessage? {
        return StoryFinder.nextExpiringStory(tx: tx)
    }

    override public func expirationDate(ofElement storyMessage: StoryMessage) -> Date {
        return Date(millisecondsSince1970: storyMessage.timestamp + StoryManager.storyLifetimeMillis)
    }

    override public func deleteExpiredElement(_ storyMessage: StoryMessage, tx: DBWriteTransaction) {
        storyMessage.anyRemove(transaction: tx)
    }
}
