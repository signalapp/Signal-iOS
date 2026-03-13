//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension TSMessage {
    @objc
    public static func messageStateForRecipientStates(
        _ recipientStates: [TSOutgoingMessageRecipientState],
    ) -> TSOutgoingMessageState {
        var hasSendingReceipient = false
        var hasPendingRecipient = false
        var hasFailedRecipient = false

        for recipientState in recipientStates {
            switch recipientState.status {
            case .sending:
                hasSendingReceipient = true
            case .pending:
                hasPendingRecipient = true
            case .failed:
                hasFailedRecipient = true
            case .skipped, .sent, .delivered, .read, .viewed:
                break
            }
        }

        if hasSendingReceipient {
            return .sending
        }
        if hasPendingRecipient {
            return .pending
        }
        if hasFailedRecipient {
            return .failed
        }
        return .sent
    }
}
