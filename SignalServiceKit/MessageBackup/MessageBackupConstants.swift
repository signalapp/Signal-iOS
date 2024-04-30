//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension MessageBackup {

    internal enum Constants {
        /// Any messages set to expire within this time frame are excluded from the backup.
        static let minExpireTimerMs: UInt64 = kDayInMs

        /// We reject downloading backup proto files larger than this.
        static let maxDownloadSizeBytes: UInt = 100 * 1024 * 1024 // 100 MiB
    }
}
