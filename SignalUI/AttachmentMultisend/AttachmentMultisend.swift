//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public class AttachmentMultisend {

    public struct Result {
        /// Resolved when the messages are prepared but before uploading/sending.
        public let preparedPromise: Promise<[PreparedOutgoingMessage]>
        /// Resolved when sending is durably enqueued but before uploading/sending.
        public let enqueuedPromise: Promise<[TSThread]>
        /// Resolved when the message is sent.
        public let sentPromise: Promise<[TSThread]>
    }

    private init() {}

    public class func sendApprovedMedia(
        conversations: [ConversationItem],
        approvedMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment]
    ) -> AttachmentMultisend.Result {
        fatalError("TODO")
    }

    public class func sendTextAttachment(
        _ textAttachment: UnsentTextAttachment,
        to conversations: [ConversationItem]
    ) -> AttachmentMultisend.Result {
        fatalError("TODO")
    }

    // MARK: - Dependencies

    private struct Dependencies {
        let attachmentManager: AttachmentManager
        let contactsMentionHydrator: ContactsMentionHydrator.Type
        let databaseStorage: SDSDatabaseStorage
        let imageQualityLevel: ImageQualityLevel.Type
        let messageSenderJobQueue: MessageSenderJobQueue
        let tsAccountManager: TSAccountManager
    }

    private static var deps = Dependencies(
        attachmentManager: DependenciesBridge.shared.attachmentManager,
        contactsMentionHydrator: ContactsMentionHydrator.self,
        databaseStorage: SSKEnvironment.shared.databaseStorage,
        imageQualityLevel: ImageQualityLevel.self,
        messageSenderJobQueue: SSKEnvironment.shared.messageSenderJobQueueRef,
        tsAccountManager: DependenciesBridge.shared.tsAccountManager
    )
}
