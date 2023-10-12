//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension ThreadStore {
    func fetchAssociatedThread<ThreadType>(
        callRecord: CallRecord,
        tx: DBReadTransaction
    ) -> ThreadType? {
        guard
            let thread = fetchThread(
                rowId: callRecord.threadRowId, tx: tx
            ) as? ThreadType
        else {
            CallRecordLogger.shared.error("Missing associated interaction for call record. This should be impossible per the DB schema!")
            return nil
        }

        return thread
    }
}
