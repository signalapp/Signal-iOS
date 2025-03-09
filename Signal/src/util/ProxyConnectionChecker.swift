//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

enum ProxyConnectionChecker {
    static func checkConnectionAndNotify() async -> Bool {
        var hasTransitionedToConnecting = false
        for await _ in NotificationCenter.default.notifications(named: OWSChatConnection.chatConnectionStateDidChange) {
            switch DependenciesBridge.shared.chatConnectionManager.identifiedConnectionState {
            case .closed:
                // Ignore closed state until we start connecting, it's expected that old sockets will close
                guard hasTransitionedToConnecting else { continue }
                return false
            case .connecting:
                hasTransitionedToConnecting = true
            case .open:
                return true
            }
        }

        // If we get here, the task was cancelled before we got a successful connection.
        return false
    }
}
