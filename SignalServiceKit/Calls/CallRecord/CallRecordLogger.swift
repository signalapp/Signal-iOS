//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A logger for call record-related events.
final class CallRecordLogger: PrefixedLogger {
    public static let shared = CallRecordLogger()

    private init() {
        super.init(prefix: "[CallRecord]")
    }
}
