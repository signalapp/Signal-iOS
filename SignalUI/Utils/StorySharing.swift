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
        let storyConversations = conversations.filter { $0.outgoingMessageClass == OutgoingStoryMessage.self }
        owsAssertDebug(conversations.count == storyConversations.count)

        guard !storyConversations.isEmpty else { return Promise.value(()) }

        return AttachmentMultisend.sendTextAttachment(
            buildTextAttachment(with: messageBody, linkPreviewDraft: linkPreviewDraft),
            to: storyConversations
        ).asVoid()
    }

    public static func sendTextStoryFromShareExtension(
        with messageBody: MessageBody,
        linkPreviewDraft: OWSLinkPreviewDraft?,
        to conversations: [ConversationItem],
        messagesReadyToSend: @escaping ([TSOutgoingMessage]) -> Void
    ) -> Promise<Void> {
        let storyConversations = conversations.filter { $0.outgoingMessageClass == OutgoingStoryMessage.self }
        owsAssertDebug(conversations.count == storyConversations.count)

        guard !storyConversations.isEmpty else { return Promise.value(()) }

        return AttachmentMultisend.sendTextAttachmentFromShareExtension(
            buildTextAttachment(with: messageBody, linkPreviewDraft: linkPreviewDraft),
            to: storyConversations,
            messagesReadyToSend: messagesReadyToSend
        ).asVoid()
    }

    private static func buildTextAttachment(
        with messageBody: MessageBody,
        linkPreviewDraft: OWSLinkPreviewDraft?
    ) -> UnsentTextAttachment {
        // Send the text message to any selected story recipients
        // as a text story with default styling.
        return UnsentTextAttachment(
            text: text(for: messageBody, with: linkPreviewDraft),
            textStyle: .regular,
            textForegroundColor: .white,
            textBackgroundColor: nil,
            background: .color(.init(rgbHex: 0x688BD4)),
            linkPreviewDraft: linkPreviewDraft
        )
    }

    internal static func text(for messageBody: MessageBody, with linkPreview: OWSLinkPreviewDraft?) -> String? {
        // Turn any mentions in the message body to plaintext
        // TODO[TextFormatting]: preserve styles on the story message proto but hydrate mentions
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
