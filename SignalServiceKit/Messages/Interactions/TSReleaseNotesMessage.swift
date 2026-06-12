//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension TSReleaseNotesMessage {
    public convenience init(thread: TSThread, messageBody: ValidatedInlineMessageBody, timestamp: UInt64) {
        let builder = TSMessageBuilder.withDefaultValues(
            thread: thread,
            timestamp: timestamp,
            messageBody: messageBody,
        )
        self.init(messageWithBuilder: builder)
    }
}
