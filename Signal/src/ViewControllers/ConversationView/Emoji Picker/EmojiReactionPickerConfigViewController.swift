//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalServiceKit

public class EmojiReactionPickerConfigViewController: UIViewController {

    private lazy var reactionPicker: MessageReactionPicker = {
       return MessageReactionPicker(selectedEmoji: nil, delegate: nil, configureMode: true)
    }()

    private lazy var instructionLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString("TAP_REPLACE_EMOJI", comment: "Tap to Replace Emoji string for reaction configuration")
        label.font = UIFont.dynamicTypeBody2
        label.textColor = Theme.secondaryTextAndIconColor
        return label
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("CONFIGURE_REACTIONS", comment: "Configure reactions title text")
        view.backgroundColor = Theme.isDarkThemeEnabled ? Theme.actionSheetBackgroundColor : UIColor.color(rgbHex: 0xF0F0F0)

        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonTapped(sender:)))
        navigationItem.setRightBarButton(doneButton, animated: false)

        let resetButton = UIBarButtonItem(title: NSLocalizedString("RESET", comment: "Configure reactions reset button text"), style: .plain, target: self, action: #selector(resetButtonTapped(sender:)))
        navigationItem.setLeftBarButton(resetButton, animated: false)

        // Reaction picker
        reactionPicker.delegate = self
        view.addSubview(reactionPicker)
        reactionPicker.autoHCenterInSuperview()
        reactionPicker.autoPinEdge(toSuperviewMargin: .top, withInset: 95)

        view.addSubview(instructionLabel)
        instructionLabel.autoHCenterInSuperview()
        instructionLabel.autoPinEdge(.top, to: .bottom, of: reactionPicker, withOffset: 30)
    }

    @objc
    private func resetButtonTapped(sender: UIButton) {
        let emojiSet: [EmojiWithSkinTones] = ReactionManager.defaultEmojiSet.map { EmojiWithSkinTones(rawValue: $0)! }

        for (index, emoji) in reactionPicker.currentEmojiSet().enumerated() {
            if let newEmoji = emojiSet[safe: index]?.rawValue {
                reactionPicker.replaceEmojiReaction(emoji, newEmoji: newEmoji, inPosition: index)
            }
        }
    }

    @objc
    private func doneButtonTapped(sender: UIButton) {
        let currentEmojiSet = reactionPicker.currentEmojiSet()
        SDSDatabaseStorage.shared.write { transaction in
            ReactionManager.setCustomEmojiSet(currentEmojiSet, transaction: transaction)
        }
        Self.storageServiceManager.recordPendingLocalAccountUpdates()
        dismiss(animated: true, completion: nil)
    }

}

extension EmojiReactionPickerConfigViewController: MessageReactionPickerDelegate {
    func didSelectReaction(reaction: String, isRemoving: Bool, inPosition position: Int) {

        if presentedViewController != nil {
            self.reactionPicker.endReplaceAnimation()
            presentedViewController?.dismiss(animated: true, completion: nil)
            return
        }

        let picker = EmojiPickerSheet(allowReactionConfiguration: false) { [weak self] emoji in
            guard let self = self else { return }

            guard let emojiString = emoji?.rawValue else {
                self.reactionPicker.endReplaceAnimation()
                return
            }

            self.reactionPicker.replaceEmojiReaction(reaction, newEmoji: emojiString, inPosition: position)
            self.reactionPicker.endReplaceAnimation()
        }
        picker.backdropColor = .clear

        reactionPicker.startReplaceAnimation(focusedEmoji: reaction, inPosition: position)
        present(picker, animated: true)
    }

    func didSelectAnyEmoji() {
        // No-op for configuration
    }
}
