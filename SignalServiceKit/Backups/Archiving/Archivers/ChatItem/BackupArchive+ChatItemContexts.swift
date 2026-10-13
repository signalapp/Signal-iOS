//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension BackupArchive {

    class ChatItemRestoringContext: RestoringContext {

        let accountDataContext: AccountDataRestoringContext
        let chatContext: ChatRestoringContext
        let recipientContext: RecipientRestoringContext

        var uploadEra: String? { chatContext.customChatColorContext.accountDataContext.uploadEra }

        init(
            accountDataContext: AccountDataRestoringContext,
            chatContext: ChatRestoringContext,
            recipientContext: RecipientRestoringContext,
            localIdentifiers: LocalIdentifiers,
            startDate: Date,
            remoteConfig: RemoteConfig,
            attachmentByteCounter: BackupArchiveAttachmentByteCounter,
            isPrimaryDevice: Bool,
            tx: DBWriteTransaction,
        ) {
            self.accountDataContext = accountDataContext
            self.recipientContext = recipientContext
            self.chatContext = chatContext
            super.init(
                localIdentifiers: localIdentifiers,
                startDate: startDate,
                remoteConfig: remoteConfig,
                attachmentByteCounter: attachmentByteCounter,
                isPrimaryDevice: isPrimaryDevice,
                tx: tx,
            )
        }
    }
}
