//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
        // Turn any mentions in the message body to plaintext
        let plaintextMessageBody = databaseStorage.read { messageBody.plaintextBody(transaction: $0.unwrapGrdbRead) }

        let text: String?
        if linkPreview != nil, let linkPreviewUrlString = linkPreview?.urlString, plaintextMessageBody.contains(linkPreviewUrlString) {
            if plaintextMessageBody == linkPreviewUrlString {
                // If the only message text is the URL of the link preview, omit the message text
                text = nil
            } else if
                plaintextMessageBody.hasPrefix(linkPreviewUrlString),
                CharacterSet.whitespacesAndNewlines.contains(
                    plaintextMessageBody[plaintextMessageBody.index(
                        plaintextMessageBody.startIndex,
                        offsetBy: linkPreviewUrlString.count
                    )]
                )
            {
                // If the URL is at the start of the message, strip it off
                text = String(plaintextMessageBody.dropFirst(linkPreviewUrlString.count)).stripped
            } else if
                plaintextMessageBody.hasSuffix(linkPreviewUrlString),
                CharacterSet.whitespacesAndNewlines.contains(
                    plaintextMessageBody[plaintextMessageBody.index(
                        plaintextMessageBody.endIndex,
                        offsetBy: -(linkPreviewUrlString.count + 1)
                    )]
                )
            {
                // If the URL is at the end of the message, strip it off
                text = String(plaintextMessageBody.dropLast(linkPreviewUrlString.count)).stripped
            } else {
                // If the URL is in the middle of the message, send the message as is
                text = plaintextMessageBody
            }
        } else {
            text = plaintextMessageBody
        }
        return text
    }
}

private extension CharacterSet {
    func contains(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(contains(_:))
    }
}
