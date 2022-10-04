//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public enum StorySharing: Dependencies {
    public static func sendTextStory(
        with messageBody: MessageBody,
        linkPreviewDraft: OWSLinkPreviewDraft?,
        to conversations: [ConversationItem]
    ) -> Promise<Void> {
        // Send the text message to any selected story recipients
        // as a text story with default styling.
        let storyConversations = conversations.filter { $0.outgoingMessageClass == OutgoingStoryMessage.self }
        owsAssertDebug(conversations.count == storyConversations.count)

        guard !storyConversations.isEmpty else { return Promise.value(()) }

        let linkPreview: OWSLinkPreview?
        if let linkPreviewDraft = linkPreviewDraft {
            linkPreview = databaseStorage.write { transaction in
                try? OWSLinkPreview.buildValidatedLinkPreview(fromInfo: linkPreviewDraft, transaction: transaction)
            }
        } else {
            linkPreview = nil
        }

        // If the only message text is the URL of the link preview, omit the message text
        let text: String?
        if linkPreview != nil, messageBody.text == linkPreview?.urlString {
            text = nil
        } else {
            text = messageBody.text
        }

        let textAttachment = TextAttachment(
            text: text,
            textStyle: .regular,
            textForegroundColor: .white,
            textBackgroundColor: nil,
            background: .color(.init(rgbHex: 0x688BD4)),
            linkPreview: linkPreview
        )

        return AttachmentMultisend.sendTextAttachment(textAttachment, to: storyConversations).asVoid()
    }
}
