//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class ContextMenuRectionBarAccessory: ContextMenuTargetedPreviewAccessory, MessageReactionPickerDelegate {
    public let thread: TSThread
    public let itemViewModel: CVItemViewModelImpl?
    public var didSelectReactionHandler: ((TSMessage, String, Bool) -> Void)? // = {(message: TSMessage, reaction: String, isRemoving: Bool) -> Void in }

    private var reactionPicker: MessageReactionPicker
    private var highlightHoverGestureRecognizer: UIGestureRecognizer?
    private var highlightClickGestureRecognizer: UIGestureRecognizer?

    public init(
        thread: TSThread,
        itemViewModel: CVItemViewModelImpl?
    ) {
        self.thread = thread
        self.itemViewModel = itemViewModel

        reactionPicker = MessageReactionPicker(selectedEmoji: itemViewModel?.reactionState?.localUserEmoji, delegate: nil)
        let isRTL = CurrentAppContext().isRTL
        let isIncomingMessage = itemViewModel?.interaction.interactionType == .incomingMessage
        let alignmnetOffset = isIncomingMessage && thread.isGroupThread ? (isRTL ? 22 : -22) : 0
        let horizontalEdgeAlignment: ContextMenuTargetedPreviewAccessory.AccessoryAlignment.Edge = isIncomingMessage ? (isRTL ? .trailing : .leading) : (isRTL ? .leading : .trailing)
        let alignment = ContextMenuTargetedPreviewAccessory.AccessoryAlignment(alignments: [(.top, .exterior), (horizontalEdgeAlignment, .interior)], alignmentOffset: CGPoint(x: alignmnetOffset, y: -12))
        super.init(accessoryView: reactionPicker, accessoryAlignment: alignment)
        reactionPicker.delegate = self
        reactionPicker.isHidden = true

        if #available(iOS 13.4, *) {
            let highlightHoverGestureRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(hoverGestureRecognized(sender:)))
            reactionPicker.addGestureRecognizer(highlightHoverGestureRecognizer)
            self.highlightHoverGestureRecognizer = highlightHoverGestureRecognizer

            let highlightClickGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(hoverClickGestureRecognized(sender:)))
            highlightClickGestureRecognizer.buttonMaskRequired = [.primary]
            reactionPicker.addGestureRecognizer(highlightClickGestureRecognizer)
            self.highlightClickGestureRecognizer = highlightClickGestureRecognizer
        }
    }

    override func animateIn(
        duration: TimeInterval,
        previewWillShift: Bool,
        completion: @escaping () -> Void
    ) {
        let animateIn = {
            self.reactionPicker.isHidden = false
            self.reactionPicker.playPresentationAnimation(duration: 0.2)
            completion()

        }
        if previewWillShift {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { animateIn() }
        } else {
            animateIn()
        }

    }

    override func animateOut(
        duration: TimeInterval,
        previewWillShift: Bool,
        completion: @escaping () -> Void
    ) {
        reactionPicker.playDismissalAnimation(duration: duration, completion: completion)
    }

    @objc
    func hoverGestureRecognized(sender: UIGestureRecognizer) {
        reactionPicker.updateFocusPosition(sender.location(in: reactionPicker), animated: true)
    }

    @objc
    func hoverClickGestureRecognized(sender: UIGestureRecognizer) {
        touchLocationInViewDidEnd(locationInView: sender.location(in: reactionPicker))
    }

    override func touchLocationInViewDidChange(locationInView: CGPoint) {
        reactionPicker.updateFocusPosition(locationInView, animated: true)
    }

    @discardableResult
    override func touchLocationInViewDidEnd(locationInView: CGPoint) -> Bool {
        // Send focused emoji if needed
        if let focusedEmoji = reactionPicker.focusedEmoji {
            if focusedEmoji == MessageReactionPicker.anyEmojiName {
                didSelectAnyEmoji()
            } else {
                let isRemoving = focusedEmoji == self.itemViewModel?.reactionState?.localUserEmoji
                if let index = reactionPicker.currentEmojiSet().firstIndex(of: focusedEmoji) {
                    didSelectReaction(reaction: focusedEmoji, isRemoving: isRemoving, inPosition: index )
                }
            }
            return true
        }

        return false
    }

    // MARK: MessageReactionPickerDelegate
    func didSelectReaction(
        reaction: String,
        isRemoving: Bool,
        inPosition position: Int
    ) {
        guard let message = itemViewModel?.interaction as? TSMessage else {
            owsFailDebug("Not sending reaction for unexpected interaction type")
            return
        }

        reactionPicker.playDismissalAnimation(duration: 0.2) {
            self.didSelectReactionHandler?(message, reaction, isRemoving)
            self.delegate?.contextMenuTargetedPreviewAccessoryRequestsDismissal(self, completion: { })

        }
    }

    func didSelectAnyEmoji() {
        guard let message = itemViewModel?.interaction as? TSMessage else {
            owsFailDebug("Not sending reaction for unexpected interaction type")
            return
        }

        reactionPicker.playDismissalAnimation(duration: 0.2) { }

        self.delegate?.contextMenuTargetedPreviewAccessoryRequestsEmojiPicker(self) { emojiString in
            let isRemoving = emojiString == self.itemViewModel?.reactionState?.localUserEmoji
            self.didSelectReactionHandler?(message, emojiString, isRemoving)
            self.delegate?.contextMenuTargetedPreviewAccessoryRequestsDismissal(self, completion: { })
        }
    }
}
