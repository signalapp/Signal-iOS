//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

extension ConversationViewController: MentionTextViewDelegate {
    public func textViewDidBeginTypingMention(_ textView: MentionTextView) {
        Logger.debug("begin typing mention")
    }

    public func textViewDidEndTypingMention(_ textView: MentionTextView) {
        Logger.debug("end typing mention")
    }

    public func textView(_ textView: MentionTextView, didUpdateMentionText mentionText: String) {
        Logger.debug("did update mention \(mentionText)")
    }

    public func textView(_ textView: MentionTextView, didTapMention mention: Mention) {
        Logger.debug("did tap mention \(mention.address)")
    }

    public func textView(_ textView: MentionTextView, didDeleteMention mention: Mention) {
        Logger.debug("did delete mention \(mention.address)")
    }

    public func textView(_ textView: MentionTextView, shouldResolveMentionForAddress address: SignalServiceAddress) -> Bool {
        return false
    }

    public func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style {
        return .composing
    }
}
