//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {

    /// The upload era value we should use for attachments restored from a given backup.
    /// "uploadEra" is meaningless except in comparison with other upload eras; if the upload
    /// era on an attachment doesn't match the current upload era, it should not be considered
    /// uploaded to the media tier. The upload era should thus change whenever subscription
    /// state changes, because existing uploads may have expired and need reupload.
    public enum RestoredAttachmentUploadEra {
        /// The AccountData frame contained a subscriber id that was active at
        /// the time the backup was made, from which we derive an upload era.
        /// Attachments should be considered uploaded in that upload era.
        case fromProtoSubscriberId(String)
        /// The AccountData frame did not have a subscription. Because we do not
        /// know when any attachments were uploaded, we use a random upload era
        /// that will fail comparison with any other upload era and thus designate all
        /// attachments as needing reupload (which is what we want).
        case random(String)
    }

    public class ChatItemRestoringContext: RestoringContext {

        let recipientContext: RecipientRestoringContext
        let chatContext: ChatRestoringContext

        /// Will only be nil if there was no earier AccountData frame to set it, which
        /// should be treated as an error at read time when processing all subsequent frames.
        var uploadEra: RestoredAttachmentUploadEra?

        init(
            recipientContext: RecipientRestoringContext,
            chatContext: ChatRestoringContext,
            tx: DBWriteTransaction
        ) {
            self.recipientContext = recipientContext
            self.chatContext = chatContext
            super.init(tx: tx)
        }
    }
}
