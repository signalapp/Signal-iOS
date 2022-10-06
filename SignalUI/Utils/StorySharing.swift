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

        let textAttachment = TextAttachment(
            text: text(for: messageBody, with: linkPreview),
            textStyle: .regular,
            textForegroundColor: .white,
            textBackgroundColor: nil,
            background: .color(.init(rgbHex: 0x688BD4)),
            linkPreview: linkPreview
        )

        return AttachmentMultisend.sendTextAttachment(textAttachment, to: storyConversations).asVoid()
    }

    internal static func text(for messageBody: MessageBody, with linkPreview: OWSLinkPreview?) -> String? {
        let text: String?
        if linkPreview != nil, let linkPreviewUrlString = linkPreview?.urlString, messageBody.text.contains(linkPreviewUrlString) {
            if messageBody.text == linkPreviewUrlString {
                // If the only message text is the URL of the link preview, omit the message text
                text = nil
            } else if
                messageBody.text.hasPrefix(linkPreviewUrlString),
                CharacterSet.whitespacesAndNewlines.contains(
                    messageBody.text[messageBody.text.index(
                        messageBody.text.startIndex,
                        offsetBy: linkPreviewUrlString.count
                    )]
                )
            {
                // If the URL is at the start of the message, strip it off
                text = String(messageBody.text.dropFirst(linkPreviewUrlString.count)).stripped
            } else if
                messageBody.text.hasSuffix(linkPreviewUrlString),
                CharacterSet.whitespacesAndNewlines.contains(
                    messageBody.text[messageBody.text.index(
                        messageBody.text.endIndex,
                        offsetBy: -(linkPreviewUrlString.count + 1)
                    )]
                )
            {
                // If the URL is at the end of the message, strip it off
                text = String(messageBody.text.dropLast(linkPreviewUrlString.count)).stripped
            } else {
                // If the URL is in the middle of the message, send the message as is
                text = messageBody.text
            }
        } else {
            text = messageBody.text
        }
        return text
    }
}

private extension CharacterSet {
    func contains(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(contains(_:))
    }
}
