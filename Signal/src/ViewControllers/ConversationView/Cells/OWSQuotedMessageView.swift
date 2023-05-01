//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension OWSQuotedMessageView {

    @objc
    static func displayableTextWithSneakyTransaction(forPreview quotedMessage: OWSQuotedReplyModel) -> DisplayableText? {
        guard let text = quotedMessage.body else {
            return nil
        }
        return Self.databaseStorage.read { tx in
            let messageBody = MessageBody(text: text, ranges: quotedMessage.bodyRanges ?? .empty)
            return DisplayableText.displayableText(
                withMessageBody: messageBody,
                displayConfig: HydratedMessageBody.DisplayConfiguration(
                    mention: .quotedReply,
                    style: .quotedReply,
                    searchRanges: nil
                ),
                transaction: tx
            )
        }
    }
}
