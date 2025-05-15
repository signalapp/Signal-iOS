//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

final class MockDeletedCallRecordCleanupManager: DeletedCallRecordCleanupManager {
    func startCleanupIfNecessary() async {}
}

#endif
