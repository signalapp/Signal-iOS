//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

struct ProxyConnectionChecker {
    private let chatConnectionManager: any ChatConnectionManager

    init(chatConnectionManager: any ChatConnectionManager) {
        self.chatConnectionManager = chatConnectionManager
    }

    func checkConnection() async -> Bool {
        do {
            try await withCooperativeTimeout(seconds: OWSRequestFactory.textSecureHTTPTimeOut) {
                try await chatConnectionManager.waitForUnidentifiedConnectionToOpen()
            }
            return true
        } catch {
            return false
        }
    }
}
