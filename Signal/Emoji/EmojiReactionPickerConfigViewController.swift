//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class EmojiReactionPickerConfigViewController: UIViewController {

    private lazy var reactionPicker: MessageReactionPicker = {
        return MessageReactionPicker(
            selectedEmoji: nil,
            delegate: nil,
            style: .configure,
            forceDarkTheme: self.forceDarkTheme
        )
    }()

    private lazy var instructionLabel: UILabel = {
        let label = UILabel()
        label.text = OWSLocalizedString("TAP_REPLACE_EMOJI", comment: "Tap to Replace Emoji string for reaction configuration")
        label.font = UIFont.dynamicTypeBody2
        label.textColor = self.forceDarkTheme ? Theme.darkThemeSecondaryTextAndIconColor : Theme.secondaryTextAndIconColor
        return label
    }()

    private let forceDarkTheme: Bool

    private let reactionPickerConfigurationListener: ReactionPickerConfigurationListener?

    init(
        forceDarkTheme: Bool = false,
        reactionPickerConfigurationListener: ReactionPickerConfigurationListener? = nil
    ) {
        self.forceDarkTheme = forceDarkTheme
        self.reactionPickerConfigurationListener = reactionPickerConfigurationListener
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = OWSLocalizedString("CONFIGURE_REACTIONS", comment: "Configure reactions title text")
        if self.forceDarkTheme || Theme.isDarkThemeEnabled {
            view.backgroundColor = .ows_gray75
        } else {
            view.backgroundColor = UIColor.color(rgbHex: 0xF0F0F0)
        }

        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.doneButtonTapped()
        }

        navigationItem.leftBarButtonItem = .button(
            title: OWSLocalizedString(
                "RESET",
                comment: "Configure reactions reset button text"
            ),
            style: .plain,
            action: { [weak self] in
                self?.resetButtonTapped()
            }
        )
        if self.forceDarkTheme {
            navigationController?.navigationBar.tintColor = .white
            let textAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
            navigationController?.navigationBar.titleTextAttributes = textAttributes
        }

        // Reaction picker
        reactionPicker.delegate = self
        view.addSubview(reactionPicker)
        reactionPicker.autoHCenterInSuperview()
        reactionPicker.autoPinEdge(toSuperviewMargin: .top, withInset: 95)

        view.addSubview(instructionLabel)
        instructionLabel.autoHCenterInSuperview()
        instructionLabel.autoPinEdge(.top, to: .bottom, of: reactionPicker, withOffset: 30)
    }

    private func resetButtonTapped() {
        let emojiSet: [EmojiWithSkinTones] = ReactionManager.defaultEmojiSet.map { EmojiWithSkinTones(rawValue: $0)! }

        for (index, emoji) in reactionPicker.currentEmojiSet().enumerated() {
            if let newEmoji = emojiSet[safe: index]?.rawValue {
                reactionPicker.replaceEmojiReaction(emoji, newEmoji: newEmoji, inPosition: index)
            }
        }
    }

    private func doneButtonTapped() {
        let currentEmojiSet = reactionPicker.currentEmojiSet()
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            ReactionManager.setCustomEmojiSet(currentEmojiSet, transaction: transaction)
        }
        self.reactionPickerConfigurationListener?.didCompleteReactionPickerConfiguration()
        SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
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

        let picker = EmojiPickerSheet(message: nil, allowReactionConfiguration: false) { [weak self] emoji in
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

protocol ReactionPickerConfigurationListener {
    func didCompleteReactionPickerConfiguration()
}
