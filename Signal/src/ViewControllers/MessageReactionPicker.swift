//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol MessageReactionPickerDelegate: class {
    func didSelectReaction(reaction: String, isRemoving: Bool)
    func didSelectAnyEmoji()
}

class MessageReactionPicker: UIStackView {
    static let anyEmojiName = "any"

    let pickerDiameter: CGFloat = UIDevice.current.isNarrowerThanIPhone6 ? 50 : 56
    let reactionFontSize: CGFloat = UIDevice.current.isNarrowerThanIPhone6 ? 30 : 32
    let pickerPadding: CGFloat = 6
    var reactionHeight: CGFloat { return pickerDiameter - (pickerPadding * 2) }
    var selectedBackgroundHeight: CGFloat { return pickerDiameter - 4 }

    private var buttonForEmoji = [String: OWSFlatButton]()
    private var selectedEmoji: EmojiWithSkinTones?
    private weak var delegate: MessageReactionPickerDelegate?
    private var backgroundView: UIView?
    init(selectedEmoji: String?, delegate: MessageReactionPickerDelegate) {
        if let selectedEmoji = selectedEmoji {
            self.selectedEmoji = EmojiWithSkinTones(rawValue: selectedEmoji)
            owsAssertDebug(self.selectedEmoji != nil)
        } else {
            self.selectedEmoji = nil
        }
        self.delegate = delegate

        super.init(frame: .zero)

        backgroundView = addBackgroundView(
            withBackgroundColor: Theme.actionSheetBackgroundColor,
            cornerRadius: pickerDiameter / 2
        )
        backgroundView?.layer.shadowColor = UIColor.ows_black.cgColor
        backgroundView?.layer.shadowRadius = 4
        backgroundView?.layer.shadowOpacity = 0.05
        backgroundView?.layer.shadowOffset = .zero

        let shadowView = UIView()
        shadowView.backgroundColor = Theme.actionSheetBackgroundColor
        shadowView.layer.cornerRadius = pickerDiameter / 2
        shadowView.layer.shadowColor = UIColor.ows_black.cgColor
        shadowView.layer.shadowRadius = 12
        shadowView.layer.shadowOpacity = 0.3
        shadowView.layer.shadowOffset = CGSize(width: 0, height: 4)
        backgroundView?.addSubview(shadowView)
        shadowView.autoPinEdgesToSuperviewEdges()

        autoSetDimension(.height, toSize: pickerDiameter)

        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: pickerPadding, leading: pickerPadding, bottom: pickerPadding, trailing: pickerPadding)

        var emojiSet: [EmojiWithSkinTones] = SDSDatabaseStorage.shared.uiRead { transaction in
            return ReactionManager.emojiSet.compactMap { Emoji(rawValue: $0)?.withPreferredSkinTones(transaction: transaction) }
        }
        owsAssertDebug(emojiSet.count == ReactionManager.emojiSet.count)

        var addAnyButton = true

        if let selectedEmoji = self.selectedEmoji {
            // If the local user reacted with any of the default emoji set,
            // regardless of skin tone, we should show it in the normal place
            // in the picker bar.
            if let index = emojiSet.map({ $0.baseEmoji }).firstIndex(of: selectedEmoji.baseEmoji) {
                emojiSet[index] = selectedEmoji
            } else {
                emojiSet.append(selectedEmoji)
                addAnyButton = false
            }
        }

        for emoji in emojiSet {
            let button = OWSFlatButton()
            button.autoSetDimensions(to: CGSize(square: reactionHeight))
            button.setTitle(title: emoji.rawValue, font: .systemFont(ofSize: reactionFontSize), titleColor: Theme.primaryTextColor)
            button.setPressedBlock { [weak self] in
                self?.delegate?.didSelectReaction(reaction: emoji.rawValue, isRemoving: emoji == self?.selectedEmoji)
            }
            buttonForEmoji[emoji.rawValue] = button
            addArrangedSubview(button)

            // Add a circle behind the currently selected emoji
            if self.selectedEmoji == emoji {
                let selectedBackgroundView = UIView()
                selectedBackgroundView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_gray05
                selectedBackgroundView.clipsToBounds = true
                selectedBackgroundView.layer.cornerRadius = selectedBackgroundHeight / 2
                backgroundView?.addSubview(selectedBackgroundView)
                selectedBackgroundView.autoSetDimensions(to: CGSize(square: selectedBackgroundHeight))
                selectedBackgroundView.autoAlignAxis(.horizontal, toSameAxisOf: button)
                selectedBackgroundView.autoAlignAxis(.vertical, toSameAxisOf: button)
            }
        }

        if addAnyButton {
            let button = OWSFlatButton()
            button.autoSetDimensions(to: CGSize(square: reactionHeight))
            button.setImage(Theme.isDarkThemeEnabled ? #imageLiteral(resourceName: "any-emoji-32-dark") : #imageLiteral(resourceName: "any-emoji-32-light"))
            button.setPressedBlock { [weak self] in
                self?.delegate?.didSelectAnyEmoji()
            }
            buttonForEmoji[MessageReactionPicker.anyEmojiName] = button
            addArrangedSubview(button)
        }
    }

    func playPresentationAnimation(duration: TimeInterval) {
        backgroundView?.alpha = 0
        UIView.animate(withDuration: duration) { self.backgroundView?.alpha = 1 }

        var delay: TimeInterval = 0
        for view in arrangedSubviews {
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: 24)
            UIView.animate(withDuration: duration, delay: delay, options: .curveEaseIn, animations: {
                view.transform = .identity
                view.alpha = 1
            })
            delay += 0.01
        }
    }

    func playDismissalAnimation(duration: TimeInterval, completion: @escaping () -> Void) {
        UIView.animate(withDuration: duration) { self.backgroundView?.alpha = 0 }

        var delay: TimeInterval = 0
        for view in arrangedSubviews.reversed() {
            UIView.animate(withDuration: duration, delay: delay, options: .curveEaseOut, animations: {
                view.alpha = 0
                view.transform = CGAffineTransform(translationX: 0, y: 24)
            }, completion: { _ in
                guard view == self.arrangedSubviews.first else { return }
                completion()
            })
            delay += 0.01
        }
    }

    var focusedEmoji: String?
    func updateFocusPosition(_ position: CGPoint, animated: Bool) {
        var previouslyFocusedButton: OWSFlatButton?
        var focusedButton: OWSFlatButton?

        if let focusedEmoji = focusedEmoji, let focusedButton = buttonForEmoji[focusedEmoji] {
            previouslyFocusedButton = focusedButton
        }

        focusedEmoji = nil

        for (emoji, button) in buttonForEmoji {
            guard focusArea(for: button).contains(position) else { continue }
            focusedEmoji = emoji
            focusedButton = buttonForEmoji[emoji]
            break
        }

        // Do nothing if we're already focused
        guard previouslyFocusedButton != focusedButton else { return }

        SelectionHapticFeedback().selectionChanged()

        UIView.animate(withDuration: animated ? 0.15 : 0) {
            previouslyFocusedButton?.transform = .identity
            focusedButton?.transform = CGAffineTransform.scale(1.5).translatedBy(x: 0, y: -24)
        }
    }

    func focusArea(for button: UIView) -> CGRect {
        var focusArea = button.frame

        // This button is currently focused, restore identity while we get the frame
        // as the focus area is always relative to the unfocused state.
        if button.transform != .identity {
            let originalTransform = button.transform
            button.transform = .identity
            focusArea = button.frame
            button.transform = originalTransform
        }

        // Always a fixed height
        focusArea.size.height = 136

        // Allows focus a fixed distance above the reaction bar
        focusArea.origin.y -= 20

        // Encompases the width of the reaction, plus half of the padding on either side
        focusArea.size.width = reactionHeight + pickerPadding
        focusArea.origin.x -= pickerPadding / 2

        return focusArea
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
