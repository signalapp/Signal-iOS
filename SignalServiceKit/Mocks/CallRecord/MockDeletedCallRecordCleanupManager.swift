//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

final class MockDeletedCallRecordCleanupManager: DeletedCallRecordCleanupManager {
    var cleanupStartCount: UInt = 0
    func startCleanupIfNecessary(tx syncTx: DBWriteTransaction) {
        cleanupStartCount += 1
    }
}

#endif
