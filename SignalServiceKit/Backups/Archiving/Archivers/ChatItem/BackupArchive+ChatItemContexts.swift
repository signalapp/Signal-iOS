//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension BackupArchive {

    public class ChatItemRestoringContext: RestoringContext {

        let chatContext: ChatRestoringContext
        let recipientContext: RecipientRestoringContext

        public var uploadEra: String? { chatContext.customChatColorContext.accountDataContext.uploadEra }

        init(
            chatContext: ChatRestoringContext,
            recipientContext: RecipientRestoringContext,
            startTimestampMs: UInt64,
            attachmentByteCounter: BackupArchiveAttachmentByteCounter,
            isPrimaryDevice: Bool,
            tx: DBWriteTransaction,
        ) {
            self.recipientContext = recipientContext
            self.chatContext = chatContext
            super.init(
                startTimestampMs: startTimestampMs,
                attachmentByteCounter: attachmentByteCounter,
                isPrimaryDevice: isPrimaryDevice,
                tx: tx,
            )
        }
    }
}
