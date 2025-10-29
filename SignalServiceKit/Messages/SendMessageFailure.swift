//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

struct SendMessageFailure {
    let recipientErrors: [(serviceId: ServiceId, error: any Error)]

    init?(recipientErrors: [(ServiceId, any Error)]) {
        if recipientErrors.isEmpty {
            return nil
        }
        self.recipientErrors = recipientErrors
    }

    var arbitraryError: any Error {
        return self.recipientErrors.first!.error
    }

    func containsAny(of senderKeyError: MessageSender.SenderKeyError) -> Bool {
        return recipientErrors.contains(where: { _, recipientError in
            return senderKeyError == (recipientError as? MessageSender.SenderKeyError)
        })
    }
}
