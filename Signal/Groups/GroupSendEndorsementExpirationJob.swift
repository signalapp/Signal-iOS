//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class GroupSendEndorsementExpirationJob: ExpirationJob<CombinedGroupSendEndorsementRecord> {
    private let groupSendEndorsementStore: GroupSendEndorsementStore

    init(
        dateProvider: @escaping DateProvider,
        db: any DB,
        groupSendEndorsementStore: GroupSendEndorsementStore,
    ) {
        self.groupSendEndorsementStore = groupSendEndorsementStore
        super.init(
            dateProvider: dateProvider,
            db: db,
            logger: PrefixedLogger(prefix: "[GroupSendEndorsementExpJob]"),
        )
    }

    override func nextExpiringElement(tx: DBReadTransaction) -> CombinedGroupSendEndorsementRecord? {
        return groupSendEndorsementStore.fetchNextExpiringCombinedEndorsement(tx: tx)
    }

    override func expirationDate(ofElement element: CombinedGroupSendEndorsementRecord) -> Date {
        return element.expiration
    }

    override func deleteExpiredElement(_ element: CombinedGroupSendEndorsementRecord, tx: DBWriteTransaction) {
        groupSendEndorsementStore.deleteEndorsements(groupRowId: element.groupRowId, tx: tx)
    }
}
