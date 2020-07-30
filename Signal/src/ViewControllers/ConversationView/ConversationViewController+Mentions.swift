//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

extension ConversationViewController: MentionTextViewDelegate {
    @objc
    var supportsMentions: Bool {
        guard FeatureFlags.mentionsSend else { return false }

        guard let groupThread = thread as? TSGroupThread,
            groupThread.groupModel.groupsVersion == .V2 else { return false }
        return true
    }

    public func textViewDidBeginTypingMention(_ textView: MentionTextView) {}

    public func textViewDidEndTypingMention(_ textView: MentionTextView) {}

    public func textViewMentionPickerParentView(_ textView: MentionTextView) -> UIView? {
        return view
    }

    public func textViewMentionPickerReferenceView(_ textView: MentionTextView) -> UIView? {
        return bottomBar()
    }

    public func textViewMentionPickerPossibleAddresses(_ textView: MentionTextView) -> [SignalServiceAddress] {
        guard supportsMentions else { return [] }
        return thread.recipientAddresses
    }

    public func textView(_ textView: MentionTextView, didTapMention mention: Mention) {}

    public func textView(_ textView: MentionTextView, didDeleteMention mention: Mention) {}

    public func textView(_ textView: MentionTextView, shouldResolveMentionForAddress address: SignalServiceAddress) -> Bool {
        return supportsMentions && thread.recipientAddresses.contains(address)
    }

    public func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style {
        return .composing
    }
}
