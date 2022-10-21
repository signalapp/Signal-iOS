//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

protocol MessageReactionPickerDelegate: AnyObject {
    func didSelectReaction(reaction: String, isRemoving: Bool, inPosition position: Int)
    func didSelectAnyEmoji()
}

class MessageReactionPicker: UIStackView {
    static let anyEmojiName = "any"
    weak var delegate: MessageReactionPickerDelegate?

    let pickerDiameter: CGFloat = UIDevice.current.isNarrowerThanIPhone6 ? 50 : 56
    let reactionFontSize: CGFloat = UIDevice.current.isNarrowerThanIPhone6 ? 30 : 32
    let pickerPadding: CGFloat = 6
    var reactionHeight: CGFloat { return pickerDiameter - (pickerPadding * 2) }
    var selectedBackgroundHeight: CGFloat { return pickerDiameter - 4 }
    let configureMode: Bool

    private var buttonForEmoji = [(emoji: String, button: OWSFlatButton)]()
    private var selectedEmoji: EmojiWithSkinTones?
    private var backgroundView: UIView?
    init(selectedEmoji: String?, delegate: MessageReactionPickerDelegate?, configureMode: Bool = false, forceDarkTheme: Bool = false) {
        self.configureMode = configureMode

        if let selectedEmoji = selectedEmoji {
            self.selectedEmoji = EmojiWithSkinTones(rawValue: selectedEmoji)
            owsAssertDebug(self.selectedEmoji != nil)
        } else {
            self.selectedEmoji = nil
        }
        self.delegate = delegate

        super.init(frame: .zero)

        backgroundView = addBackgroundView(
            withBackgroundColor: forceDarkTheme ? .ows_gray75 : Theme.actionSheetBackgroundColor,
            cornerRadius: pickerDiameter / 2
        )
        backgroundView?.layer.shadowColor = UIColor.ows_black.cgColor
        backgroundView?.layer.shadowRadius = 4
        backgroundView?.layer.shadowOpacity = 0.05
        backgroundView?.layer.shadowOffset = .zero

        let shadowView = UIView()
        shadowView.backgroundColor = forceDarkTheme ? .ows_gray75 : Theme.actionSheetBackgroundColor
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

        var emojiSet: [EmojiWithSkinTones] = SDSDatabaseStorage.shared.read { transaction in
            let customSetStrings = ReactionManager.customEmojiSet(transaction: transaction) ?? []
            let customSet = customSetStrings.lazy.map { EmojiWithSkinTones(rawValue: $0) }

            // Any holes or invalid choices are filled in with the default reactions.
            // This could happen if another platform supports an emoji that we don't yet (say, because there's a newer
            // version of Unicode), or if a bug results in a string that's not valid at all, or fewer entries than the
            // default.
            return ReactionManager.defaultEmojiSet.enumerated().map { (i, defaultEmoji) -> EmojiWithSkinTones in
                // Treat "out-of-bounds index" and "in-bounds but not valid" the same way.
                if let customReaction = customSet[safe: i] ?? nil {
                    return customReaction
                } else {
                    return EmojiWithSkinTones(rawValue: defaultEmoji)!
                }
            }
        }

        var addAnyButton = !self.configureMode

        if !self.configureMode, let selectedEmoji = self.selectedEmoji {
            // If the local user reacted with any of the default emoji set,
            // we should show it in the normal place in the picker bar.
            // NOTE: This used to match independent of skin tone, but we decided to drop that behavior.
            if let index = emojiSet.firstIndex(of: selectedEmoji) {
                emojiSet[index] = selectedEmoji
            } else {
                emojiSet.append(selectedEmoji)
                addAnyButton = false
            }
        }

        for (index, emoji) in emojiSet.enumerated() {
            let button = OWSFlatButton()
            button.autoSetDimensions(to: CGSize(square: reactionHeight))
            button.setTitle(title: emoji.rawValue, font: .systemFont(ofSize: reactionFontSize), titleColor: forceDarkTheme ? Theme.darkThemePrimaryColor : Theme.primaryTextColor)
            button.setPressedBlock { [weak self] in
                // current title of button may have changed in the meantime
                if let currentEmoji = button.button.title(for: .normal) {
                    self?.delegate?.didSelectReaction(reaction: currentEmoji, isRemoving: currentEmoji == self?.selectedEmoji?.rawValue, inPosition: index)
                }
            }
            buttonForEmoji.append((emoji.rawValue, button))
            addArrangedSubview(button)

            // Add a circle behind the currently selected emoji
            if self.selectedEmoji == emoji {
                let selectedBackgroundView = UIView()
                selectedBackgroundView.backgroundColor = Theme.isDarkThemeEnabled || forceDarkTheme ? .ows_gray60 : .ows_gray05
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
            button.setImage(Theme.isDarkThemeEnabled || forceDarkTheme ? #imageLiteral(resourceName: "any-emoji-32-dark") : #imageLiteral(resourceName: "any-emoji-32-light"))
            button.setPressedBlock { [weak self] in
                self?.delegate?.didSelectAnyEmoji()
            }
            buttonForEmoji.append((MessageReactionPicker.anyEmojiName, button))
            addArrangedSubview(button)
        }
    }

    public func replaceEmojiReaction(_ oldEmoji: String, newEmoji: String, inPosition position: Int) {
        let buttonTuple = buttonForEmoji[position]
        let button = buttonTuple.button
        button.setTitle(title: newEmoji, font: .systemFont(ofSize: reactionFontSize), titleColor: Theme.primaryTextColor)
        buttonForEmoji.replaceSubrange(position...position, with: [(newEmoji, button)])
    }

    public func currentEmojiSet() -> [String] {
        var emojiSet: [String] = []
        for view in arrangedSubviews {
            if let button = view as? OWSFlatButton, let emoji = button.button.title(for: .normal) {
                emojiSet.append(emoji)
            }
        }
        return emojiSet
    }

    public func startReplaceAnimation(focusedEmoji: String, inPosition position: Int) {
        var buttonToWiggle: OWSFlatButton?
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            for (index, view) in self.arrangedSubviews.enumerated() {
                if let button = view as? OWSFlatButton {
                    // Shrink and fade
                    if index != position {
                        button.alpha = 0.3
                        button.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                    } else { // Expand and wiggle
                        button.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                        buttonToWiggle = button
                    }
                }
            }
        } completion: { finished in
            if finished, let buttonToWiggle = buttonToWiggle {
                let leftRotationValue = NSValue(caTransform3D: CATransform3DConcat(CATransform3DMakeScale(1.3, 1.3, 1), CATransform3DMakeRotation(-0.08, 0, 0, 1)))
                let rightRotationValue = NSValue(caTransform3D: CATransform3DConcat(CATransform3DMakeScale(1.3, 1.3, 1), CATransform3DMakeRotation(0.08, 0, 0, 1)))
                let animation = CAKeyframeAnimation(keyPath: "transform")
                animation.values = [leftRotationValue, rightRotationValue]
                animation.autoreverses = true
                animation.duration = 0.2
                animation.repeatCount = MAXFLOAT
                buttonToWiggle.layer.add(animation, forKey: "wiggle")
            }
        }
    }

    public func endReplaceAnimation() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            for view in self.arrangedSubviews {
                if let button = view as? OWSFlatButton {
                    button.alpha = 1
                    button.transform = CGAffineTransform.identity
                    button.layer.removeAnimation(forKey: "wiggle")
                }
            }
        } completion: { _ in }
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
        UIView.animate(withDuration: duration) { self.alpha = 0 } completion: { _ in
            completion()
        }
    }

    var focusedEmoji: String?
    func updateFocusPosition(_ position: CGPoint, animated: Bool) {
        var previouslyFocusedButton: OWSFlatButton?
        var focusedButton: OWSFlatButton?

        if let focusedEmoji = focusedEmoji, let focusedButton = buttonForEmoji.first(where: { $0.emoji == focusedEmoji})?.button {
            previouslyFocusedButton = focusedButton
        }

        focusedEmoji = nil

        for (emoji, button) in buttonForEmoji {
            guard focusArea(for: button).contains(position) else { continue }
            focusedEmoji = emoji
            focusedButton = buttonForEmoji.first(where: { $0.emoji == emoji })?.button
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
