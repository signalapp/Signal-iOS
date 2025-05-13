//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {

    public class ChatItemRestoringContext: RestoringContext {

        let chatContext: ChatRestoringContext
        let recipientContext: RecipientRestoringContext

        /// Will only be nil if there was no earlier AccountData frame to set it, which
        /// should be treated as an error at read time when processing all subsequent frames.
        var uploadEra: String?

        init(
            chatContext: ChatRestoringContext,
            recipientContext: RecipientRestoringContext,
            startTimestampMs: UInt64,
            tx: DBWriteTransaction
        ) {
            self.recipientContext = recipientContext
            self.chatContext = chatContext
            super.init(
                startTimestampMs: startTimestampMs,
                tx: tx
            )
        }
    }
}
