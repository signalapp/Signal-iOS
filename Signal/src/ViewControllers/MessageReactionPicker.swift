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
    /// A style for a message reaction picker.
    enum Style {
        /// An overlay context menu for selecting a saved or default reaction
        case contextMenu
        /// Editor for the saved reactions
        case configure
        /// A horizontally-scrolling picker with both saved/default and recent reactions
        case inline

        var isConfigure: Bool { self == .configure }
        var isInline: Bool { self == .inline }
    }

    static let anyEmojiName = "any"
    weak var delegate: MessageReactionPickerDelegate?

    let pickerDiameter: CGFloat = UIDevice.current.isNarrowerThanIPhone6 ? 50 : 56
    let reactionFontSize: CGFloat = UIDevice.current.isNarrowerThanIPhone6 ? 30 : 32
    let pickerPadding: CGFloat = 6
    var reactionHeight: CGFloat { return pickerDiameter - (pickerPadding * 2) }
    var selectedBackgroundHeight: CGFloat { return pickerDiameter - 4 }

    private let emojiStackView: UIStackView = UIStackView()
    private var buttonForEmoji = [(emoji: String, button: OWSFlatButton)]()
    private var selectedEmoji: EmojiWithSkinTones?
    private var backgroundView: UIView?

    /// The individual emoji buttons and the Any button from `buttonForEmoji`
    private var buttons: [OWSFlatButton] {
        return buttonForEmoji.map(\.button)
    }

    init(
        selectedEmoji: String?,
        delegate: MessageReactionPickerDelegate?,
        style: Style = .contextMenu,
        forceDarkTheme: Bool = false
    ) {
        if let selectedEmoji = selectedEmoji {
            self.selectedEmoji = EmojiWithSkinTones(rawValue: selectedEmoji)
            owsAssertDebug(self.selectedEmoji != nil)
        } else {
            self.selectedEmoji = nil
        }
        self.delegate = delegate

        super.init(frame: .zero)

        if !style.isInline {
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
        }

        autoSetDimension(.height, toSize: pickerDiameter)

        isLayoutMarginsRelativeArrangement = true
        // Inline picker's scroll view should go to the edge
        layoutMargins = .init(
            top: pickerPadding,
            leading: style.isInline ? 0 : pickerPadding,
            bottom: pickerPadding,
            trailing: style.isInline ? 4 : pickerPadding
        )

        var emojiSet: [EmojiWithSkinTones] = SDSDatabaseStorage.shared.read { transaction in
            let customSetStrings = ReactionManager.customEmojiSet(transaction: transaction) ?? []
            let customSet = customSetStrings.lazy.map { EmojiWithSkinTones(rawValue: $0) }

            // Any holes or invalid choices are filled in with the default reactions.
            // This could happen if another platform supports an emoji that we don't yet (say, because there's a newer
            // version of Unicode), or if a bug results in a string that's not valid at all, or fewer entries than the
            // default.
            let savedReactions = ReactionManager.defaultEmojiSet.enumerated().map { (i, defaultEmoji) -> EmojiWithSkinTones in
                // Treat "out-of-bounds index" and "in-bounds but not valid" the same way.
                if let customReaction = customSet[safe: i] ?? nil {
                    return customReaction
                } else {
                    return EmojiWithSkinTones(rawValue: defaultEmoji)!
                }
            }

            var recentReactions = [EmojiWithSkinTones]()

            // Add recent emoji to inline picker
            if style.isInline {
                let savedReactionSet = Set(savedReactions)

                recentReactions = EmojiPickerCollectionView
                    .getRecentEmoji(tx: transaction)
                    .filter { !savedReactionSet.contains($0) }
            }

            return savedReactions + recentReactions
        }

        var addAnyButton = !style.isConfigure

        if !style.isConfigure, let selectedEmoji = self.selectedEmoji {
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

        switch style {
        case .contextMenu, .configure:
            self.addArrangedSubview(emojiStackView)
        case .inline:
            let scrollView = FadingHScrollView()
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.addSubview(emojiStackView)
            scrollView.contentInset = .init(top: 0, leading: OWSTableViewController2.defaultHOuterMargin, bottom: 0, trailing: 0)
            emojiStackView.autoPinEdgesToSuperviewEdges()
            self.addArrangedSubview(scrollView)
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
            emojiStackView.addArrangedSubview(button)

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
            self.addArrangedSubview(button)
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
        for button in buttons {
            if let emoji = button.button.title(for: .normal) {
                emojiSet.append(emoji)
            }
        }
        return emojiSet
    }

    public func startReplaceAnimation(focusedEmoji: String, inPosition position: Int) {
        var buttonToWiggle: OWSFlatButton?
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            for (index, button) in self.buttons.enumerated() {
                // Shrink and fade
                if index != position {
                    button.alpha = 0.3
                    button.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                } else { // Expand and wiggle
                    button.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                    buttonToWiggle = button
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
            for button in self.buttons {
                button.alpha = 1
                button.transform = CGAffineTransform.identity
                button.layer.removeAnimation(forKey: "wiggle")
            }
        } completion: { _ in }
    }

    func playPresentationAnimation(duration: TimeInterval) {
        if let backgroundView {
            backgroundView.alpha = 0
            UIView.animate(withDuration: duration) { backgroundView.alpha = 1 }
        }

        var delay: TimeInterval = 0
        for view in self.buttons {
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

        // Encompasses the width of the reaction, plus half of the padding on either side
        focusArea.size.width = reactionHeight + pickerPadding
        focusArea.origin.x -= pickerPadding / 2

        return focusArea
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private class FadingHScrollView: UIScrollView {
        var fadeLocation: CGFloat = 31/32
        private lazy var gradient: GradientView = {
            let view = GradientView(colors: [.black, .clear], locations: [fadeLocation, 1])
            // Blur is at top by default. Rotate to right edge on LTR, left edge on RTL
            view.setAngle(CurrentAppContext().isRTL ? 270 : 90)
            self.mask = view
            return view
        }()

        private var isFirstLayout = true
        override func layoutSubviews() {
            super.layoutSubviews()
            gradient.frame = self.bounds

            // Scroll to the right end on RTL languages
            guard isFirstLayout else { return }
            isFirstLayout = false

            if CurrentAppContext().isRTL {
                let offset = max(0, contentSize.width - bounds.width + contentInset.leading)
                self.contentOffset = CGPoint(x: offset, y: 0)
            }
        }
    }
}
