//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension ConversationViewController: MentionTextViewDelegate {
    var supportsMentions: Bool { Mention.threadAllowsMentionSend(thread) }

    public func textViewDidBeginTypingMention(_ textView: MentionTextView) {}

    public func textViewDidEndTypingMention(_ textView: MentionTextView) {}

    public func textViewMentionPickerParentView(_ textView: MentionTextView) -> UIView? {
        view
    }

    public func textViewMentionPickerReferenceView(_ textView: MentionTextView) -> UIView? {
        bottomBar
    }

    public func textViewMentionPickerPossibleAddresses(_ textView: MentionTextView) -> [SignalServiceAddress] {
        supportsMentions ? thread.recipientAddressesWithSneakyTransaction : []
    }

    public func textView(_ textView: MentionTextView, didDeleteMention mention: Mention) {}

    public func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style {
        .composing
    }
}
