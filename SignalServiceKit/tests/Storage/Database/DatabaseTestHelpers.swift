//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

enum DatabaseTestHelpers {
    class TestSDSDatabaseStorageDelegate: SDSDatabaseStorageDelegate {
        var storageCoordinatorState: StorageCoordinatorState { .GRDB }
    }
}
