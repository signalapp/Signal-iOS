//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public class ContextMenuRectionBarAccessory: ContextMenuTargetedPreviewAccessory, MessageReactionPickerDelegate {
    public let thread: TSThread
    public let itemViewModel: CVItemViewModelImpl?
    public var didSelectReactionHandler: ((TSMessage, String, Bool)->Void)? // = {(message: TSMessage, reaction: String, isRemoving: Bool) -> Void in }
    
    private var reactionPicker: MessageReactionPicker
    
    public init(
        thread: TSThread,
        itemViewModel: CVItemViewModelImpl?
    ) {
        self.thread = thread
        self.itemViewModel = itemViewModel
        
        reactionPicker = MessageReactionPicker(selectedEmoji: itemViewModel?.reactionState?.localUserEmoji, delegate: nil)
        let isIncomingMessage = itemViewModel?.interaction.interactionType() == .incomingMessage
        let alignmnetOffset = isIncomingMessage && thread.isGroupThread ? -22 : 0
        let alignment = ContextMenuTargetedPreviewAccessory.AccessoryAlignment(alignments: [(.top, .exterior), (isIncomingMessage ? .leading : .trailing, .interior)], alignmentOffset: CGPoint(x: alignmnetOffset, y: -12))
        super.init(accessoryView: reactionPicker, accessoryAlignment: alignment)
        reactionPicker.delegate = self
    }
    
    override func animateIn(
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        reactionPicker.playPresentationAnimation(duration: duration)
        completion()
    }
    
    override func animateOut(
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        reactionPicker.playDismissalAnimation(duration: duration, completion: completion)
    }
    
    //MARK: MessageReactionPickerDelegate
    func didSelectReaction(
        reaction: String,
        isRemoving: Bool
    ) {
        guard let message = itemViewModel?.interaction as? TSMessage else {
            owsFailDebug("Not sending reaction for unexpected interaction type")
            return
        }
        
        reactionPicker.playDismissalAnimation(duration: 0.2) {
            self.didSelectReactionHandler?(message, reaction, isRemoving)
            self.delegate?.contextMenuTargetedPreviewAccessoryRequestsDismissal(self)

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
            self.delegate?.contextMenuTargetedPreviewAccessoryRequestsDismissal(self)
        }
    }
}
