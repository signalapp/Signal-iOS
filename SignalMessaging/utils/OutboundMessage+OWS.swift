//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

extension OutgoingMessagePreparer {
    @objc
    public convenience init(fullMessageText: String,
                            mediaAttachments: [SignalAttachment],
                            thread: TSThread,
                            quotedReplyModel: OWSQuotedReplyModel?,
                            transaction: SDSAnyReadTransaction) {

        var attachments = mediaAttachments
        let truncatedText: String?
        if fullMessageText.lengthOfBytes(using: .utf8) <= kOversizeTextMessageSizeThreshold {
            truncatedText = fullMessageText
        } else {
            truncatedText = fullMessageText.truncated(toByteCount: kOversizeTextMessageSizeThreshold)

            if let dataSource = DataSourceValue.dataSource(withOversizeText: fullMessageText) {
                let attachment = SignalAttachment.attachment(dataSource: dataSource,
                                                             dataUTI: kOversizeTextAttachmentUTI)
                attachments.append(attachment)
            } else {
                owsFailDebug("dataSource was unexpectedly nil")
            }
        }

        let expiresInSeconds: UInt32
        if let configuration = OWSDisappearingMessagesConfiguration.anyFetch(uniqueId: thread.uniqueId,
                                                                             transaction: transaction),
            configuration.isEnabled {
            expiresInSeconds = configuration.durationSeconds
        } else {
            expiresInSeconds = 0
        }

        if _isDebugAssertConfiguration() {
            for attachment in attachments {
                assert(!attachment.hasError)
                assert(attachment.mimeType.count > 0)
            }
        }

        let isVoiceMessage = attachments.count == 1 && attachments.last?.isVoiceMessage == true

        var isViewOnceMessage = false
        for attachment in mediaAttachments {
            if attachment.isViewOnceAttachment {
                assert(mediaAttachments.count == 1)
                isViewOnceMessage = true
                break
            }

            if attachment.isBorderless {
                assert(mediaAttachments.count == 1)
                break
            }
        }

        // Discard quoted reply for view-once messages.
        let quotedMessage: TSQuotedMessage? = (isViewOnceMessage
            ? nil
            : quotedReplyModel?.buildQuotedMessageForSending())

        let message = TSOutgoingMessageBuilder(thread: thread,
                                                messageBody: truncatedText,
                                                expiresInSeconds: expiresInSeconds,
                                                isVoiceMessage: isVoiceMessage,
                                                quotedMessage: quotedMessage,
                                                isViewOnceMessage: isViewOnceMessage).build()

        let attachmentInfos = attachments.map { $0.buildOutgoingAttachmentInfo(message: message) }

        self.init(message, unsavedAttachmentInfos: attachmentInfos)
    }
}
