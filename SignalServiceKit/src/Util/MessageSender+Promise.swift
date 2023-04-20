//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public extension MessageSender {
    /**
     * Wrap message sending in a Promise for easier callback chaining.
     */
    func sendMessage(_ namespace: PromiseNamespace, _ message: OutgoingMessagePreparer) -> Promise<Void> {
        return Promise { future in
            self.sendMessage(message, success: { future.resolve() }, failure: future.reject)
        }
    }
}
