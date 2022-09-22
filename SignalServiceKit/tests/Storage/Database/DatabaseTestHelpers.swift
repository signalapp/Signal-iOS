//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

enum DatabaseTestHelpers {
    class TestSDSDatabaseStorageDelegate: SDSDatabaseStorageDelegate {
        var storageCoordinatorState: StorageCoordinatorState { .GRDB }
    }
}
