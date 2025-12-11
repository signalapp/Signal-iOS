//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
public import SignalServiceKit
public import SignalUI

extension ConversationViewController: BodyRangesTextViewDelegate {
    var supportsMentions: Bool { thread.allowsMentionSend }

    public func textViewDidBeginTypingMention(_ textView: BodyRangesTextView) {}

    public func textViewDidEndTypingMention(_ textView: BodyRangesTextView) {}

    public func textViewMentionPickerParentView(_ textView: BodyRangesTextView) -> UIView? {
        view
    }

    public func textViewMentionPickerReferenceView(_ textView: BodyRangesTextView) -> UIView? {
        bottomBarContainer
    }

    public func textViewMentionPickerPossibleAcis(_ textView: BodyRangesTextView, tx: DBReadTransaction) -> [Aci] {
        supportsMentions ? thread.recipientAddresses(with: tx).compactMap(\.aci) : []
    }

    public func textViewMentionCacheInvalidationKey(_ textView: BodyRangesTextView) -> String {
        return thread.uniqueId
    }

    public func textViewDisplayConfiguration(_ textView: BodyRangesTextView) -> HydratedMessageBody.DisplayConfiguration {
        return .composing(textViewColor: textView.textColor)
    }

    public func mentionPickerStyle(_ textView: BodyRangesTextView) -> MentionPickerStyle {
        return .default
    }

    public func textViewDidInsertMemoji(_ memojiGlyph: OWSAdaptiveImageGlyph) {
        do {
            self.didPasteAttachments([try PasteboardAttachment.loadPreviewableMemojiAttachment(fromMemojiGlyph: memojiGlyph)])
        } catch {
            self.showErrorAlert(attachmentError: error as? SignalAttachmentError)
        }
    }
}
