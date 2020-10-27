//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

extension ConversationViewController: MentionTextViewDelegate {
    @objc
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
        guard supportsMentions else { return [] }
        return thread.recipientAddresses
    }

    public func textView(_ textView: MentionTextView, didDeleteMention mention: Mention) {}

    public func textView(_ textView: MentionTextView, shouldResolveMentionForAddress address: SignalServiceAddress) -> Bool {
        supportsMentions && thread.recipientAddresses.contains(address)
    }

    public func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style {
        .composing
    }
}
