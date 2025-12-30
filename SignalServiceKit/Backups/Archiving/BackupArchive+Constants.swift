//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension BackupArchive {

    enum Constants {
        /// We reject downloading backup proto files larger than this.
        static let maxDownloadSizeBytes: UInt = 100 * 1024 * 1024 // 100 MiB
    }
}
