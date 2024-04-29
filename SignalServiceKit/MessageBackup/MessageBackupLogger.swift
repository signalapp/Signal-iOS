//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public final class MessageBackupLogger: PrefixedLogger {
    public static let shared: MessageBackupLogger = .init()

    private init() {
        super.init(prefix: "[MessageBackup]")
    }
}
