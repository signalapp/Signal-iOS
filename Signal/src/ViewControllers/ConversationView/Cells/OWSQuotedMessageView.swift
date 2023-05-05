//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension OWSQuotedMessageView {

    static func forPreview(
        _ quotedMessage: OWSQuotedReplyModel,
        conversationStyle: ConversationStyle,
        spoilerReveal: SpoilerRevealState
    ) -> OWSQuotedMessageView {

        let displayableQuotedText: DisplayableText?
        if quotedMessage.body?.isEmpty == false {
            displayableQuotedText = displayableTextWithSneakyTransaction(
                forPreview: quotedMessage,
                spoilerReveal: spoilerReveal
            )
        } else {
            displayableQuotedText = nil
        }
        let instance = OWSQuotedMessageView(
            quotedMessage: quotedMessage,
            displayableQuotedText: displayableQuotedText,
            conversationStyle: conversationStyle,
            spoilerReveal: spoilerReveal
        )
        instance.createContents()
        return instance
    }

    static func displayableTextWithSneakyTransaction(
        forPreview quotedMessage: OWSQuotedReplyModel,
        spoilerReveal: SpoilerRevealState
    ) -> DisplayableText? {
        guard let text = quotedMessage.body else {
            return nil
        }
        return Self.databaseStorage.read { tx in
            let messageBody = MessageBody(text: text, ranges: quotedMessage.bodyRanges ?? .empty)
            return DisplayableText.displayableText(
                withMessageBody: messageBody,
                displayConfig: HydratedMessageBody.DisplayConfiguration(
                    mention: .quotedReply,
                    style: .quotedReply(revealedSpoilerIds: spoilerReveal.revealedSpoilerIds(
                        interactionIdentifier: InteractionSnapshotIdentifier(
                            timestamp: quotedMessage.timestamp,
                            authorUuid: quotedMessage.authorAddress.uuidString
                        )
                    )),
                    searchRanges: nil
                ),
                transaction: tx
            )
        }
    }

    @objc
    func restyleDisplayableQuotedText(
        _ displayableQuotedText: DisplayableText,
        font: UIFont,
        textColor: UIColor,
        quotedReplyModel: OWSQuotedReplyModel,
        spoilerReveal: SpoilerRevealState
    ) -> NSAttributedString {
        let mutableCopy = NSMutableAttributedString(attributedString: displayableQuotedText.displayAttributedText)
        mutableCopy.addAttributesToEntireString([
            .font: font,
            .foregroundColor: textColor
        ])
        return RecoveredHydratedMessageBody
            .recover(from: mutableCopy)
            .reapplyAttributes(
                config: HydratedMessageBody.DisplayConfiguration(
                    mention: MentionDisplayConfiguration(
                        font: font,
                        foregroundColor: .fixed(textColor),
                        backgroundColor: nil
                    ),
                    style: StyleDisplayConfiguration(
                        baseFont: font,
                        textColor: .fixed(textColor),
                        revealAllIds: false,
                        revealedIds: spoilerReveal.revealedSpoilerIds(
                            interactionIdentifier: InteractionSnapshotIdentifier(
                                timestamp: quotedReplyModel.timestamp,
                                authorUuid: quotedReplyModel.authorAddress.uuidString
                            )
                        )
                    ),
                    searchRanges: nil
                ),
                isDarkThemeEnabled: Theme.isDarkThemeEnabled
            )
    }
}
