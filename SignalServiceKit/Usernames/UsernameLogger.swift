//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A logger for username-related events.
public class UsernameLogger: PrefixedLogger {
    public static let shared: UsernameLogger = .init()

    private init() {
        super.init(prefix: "[Username]")
    }
}
