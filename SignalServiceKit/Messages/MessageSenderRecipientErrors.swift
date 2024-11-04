//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

struct MessageSenderRecipientErrors {
    var recipientErrors: [(serviceId: ServiceId, error: any Error)]

    func containsAny(of senderKeyErrors: MessageSender.SenderKeyError...) -> Bool {
        return recipientErrors.contains(where: { _, recipientError in
            return senderKeyErrors.contains(where: { $0 == (recipientError as? MessageSender.SenderKeyError) })
        })
    }
}
