//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

extension ConversationViewController: MentionTextViewDelegate {
    var supportsMentions: Bool {
        guard FeatureFlags.mentionsSend && FeatureFlags.mentionsReceive else { return false }

        guard let groupThread = thread as? TSGroupThread,
            groupThread.groupModel.groupsVersion == .V2 else { return false }
        return true
    }

    public func textViewMentionPickerParentView(_ textView: MentionTextView) -> UIView {
        return view
    }

    public func textViewMentionPickerReferenceView(_ textView: MentionTextView) -> UIView {
        return bottomBar()
    }

    public func textViewMentionPickerPossibleAddresses(_ textView: MentionTextView) -> [SignalServiceAddress] {
        guard supportsMentions else { return [] }
        return thread.recipientAddresses
    }

    public func textView(_ textView: MentionTextView, didTapMention mention: Mention) {
        Logger.debug("did tap mention \(mention.address)")
    }

    public func textView(_ textView: MentionTextView, didDeleteMention mention: Mention) {
        Logger.debug("did delete mention \(mention.address)")
    }

    public func textView(_ textView: MentionTextView, shouldResolveMentionForAddress address: SignalServiceAddress) -> Bool {
        return supportsMentions && thread.recipientAddresses.contains(address)
    }

    public func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style {
        return .composing
    }
}
