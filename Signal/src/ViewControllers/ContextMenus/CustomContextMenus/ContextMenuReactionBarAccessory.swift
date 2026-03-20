//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
import UIKit

public class ContextMenuReactionBarAccessory: ContextMenuTargetedPreviewAccessory, MessageReactionPickerDelegate {
    public let thread: TSThread
    public let itemViewModel: CVItemViewModelImpl?
    public var didSelectReactionHandler: ((TSMessage, CustomReactionItem, Bool) -> Void)?

    private var reactionPicker: MessageReactionPicker
    private var highlightHoverGestureRecognizer: UIGestureRecognizer?
    private var highlightClickGestureRecognizer: UIGestureRecognizer?

    public init(
        thread: TSThread,
        itemViewModel: CVItemViewModelImpl?,
    ) {
        self.thread = thread
        self.itemViewModel = itemViewModel

        let selectedReaction: CustomReactionItem? = {
            guard let reaction = itemViewModel?.reactionState?.localUserReaction else { return nil }
            return CustomReactionItem(emoji: reaction.emoji, sticker: reaction.sticker)
        }()
        reactionPicker = MessageReactionPicker(
            selectedReaction: selectedReaction,
            delegate: nil,
            style: .contextMenu(allowGlass: true),
        )
        let isRTL = CurrentAppContext().isRTL
        let isIncomingMessage = itemViewModel?.interaction.interactionType == .incomingMessage
        let alignmentOffset = isIncomingMessage && thread.isGroupThread ? 22 : 0
        let horizontalEdgeAlignment: ContextMenuTargetedPreviewAccessory.AccessoryAlignment.Edge = isIncomingMessage ? (isRTL ? .trailing : .leading) : (isRTL ? .leading : .trailing)
        let alignment = ContextMenuTargetedPreviewAccessory.AccessoryAlignment(alignments: [(.top, .exterior), (horizontalEdgeAlignment, .interior)], alignmentOffset: CGPoint(x: alignmentOffset, y: 12))
        super.init(accessoryView: reactionPicker, accessoryAlignment: alignment)
        reactionPicker.delegate = self
        reactionPicker.isHidden = true

        let highlightHoverGestureRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(hoverGestureRecognized(sender:)))
        reactionPicker.addGestureRecognizer(highlightHoverGestureRecognizer)
        self.highlightHoverGestureRecognizer = highlightHoverGestureRecognizer

        let highlightClickGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(hoverClickGestureRecognized(sender:)))
        highlightClickGestureRecognizer.buttonMaskRequired = [.primary]
        reactionPicker.addGestureRecognizer(highlightClickGestureRecognizer)
        self.highlightClickGestureRecognizer = highlightClickGestureRecognizer
    }

    override func animateIn(
        duration: TimeInterval,
        previewWillShift: Bool,
        completion: @escaping () -> Void,
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
        completion: @escaping () -> Void,
    ) {
        reactionPicker.playDismissalAnimation(duration: duration, completion: completion)
    }

    @objc
    private func hoverGestureRecognized(sender: UIGestureRecognizer) {
        reactionPicker.updateFocusPosition(sender.location(in: reactionPicker), animated: true)
    }

    @objc
    private func hoverClickGestureRecognized(sender: UIGestureRecognizer) {
        touchLocationInViewDidEnd(locationInView: sender.location(in: reactionPicker))
    }

    override func touchLocationInViewDidChange(locationInView: CGPoint) {
        reactionPicker.updateFocusPosition(locationInView, animated: true)
    }

    @discardableResult
    override func touchLocationInViewDidEnd(locationInView: CGPoint) -> Bool {
        // Send focused reaction if needed
        if let focusedReaction = reactionPicker.focusedReaction {
            switch focusedReaction {
            case .more:
                didSelectMore()
            case .reaction(let reaction):
                let localUserReaction = self.itemViewModel?.reactionState?.localUserReaction
                let isRemoving = localUserReaction.map { CustomReactionItem(emoji: $0.emoji, sticker: $0.sticker) } == reaction
                if let index = reactionPicker.currentReactionItems().firstIndex(of: reaction) {
                    didSelectReaction(reaction, isRemoving: isRemoving, inPosition: index)
                }
            }
            return true
        }

        return false
    }

    // MARK: MessageReactionPickerDelegate

    func didSelectReaction(
        _ reaction: CustomReactionItem,
        isRemoving: Bool,
        inPosition position: Int,
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

    func didSelectMore() {
        guard let message = itemViewModel?.interaction as? TSMessage else {
            owsFailDebug("Not sending reaction for unexpected interaction type")
            return
        }

        reactionPicker.playDismissalAnimation(duration: 0.2) { }

        self.delegate?.contextMenuTargetedPreviewAccessoryRequestsReactionPicker(for: message, accessory: self) { reaction in
            let localUserReaction = self.itemViewModel?.reactionState?.localUserReaction
            let isRemoving = localUserReaction.map { CustomReactionItem(emoji: $0.emoji, sticker: $0.sticker) } == reaction
            self.didSelectReactionHandler?(message, reaction, isRemoving)
            self.delegate?.contextMenuTargetedPreviewAccessoryRequestsDismissal(self, completion: { })
        }
    }
}
