//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

protocol MessageReactionPickerDelegate: AnyObject {
    func didSelectReaction(reaction: String, isRemoving: Bool, inPosition position: Int)
    func didSelectAnyEmoji()
}

class MessageReactionPicker: UIStackView {
    /// A style for a message reaction picker.
    enum Style: Equatable {
        /// An overlay context menu for selecting a saved or default reaction
        case contextMenu(allowGlass: Bool)
        /// Editor for the saved reactions
        case configure
        /// A horizontally-scrolling picker with both saved/default and recent reactions
        case inline

        var isConfigure: Bool { self == .configure }
        var isInline: Bool { self == .inline }
    }

    weak var delegate: MessageReactionPickerDelegate?

    let pickerDiameter: CGFloat = UIDevice.current.isNarrowerThanIPhone6 ? 50 : 56
    let reactionFontSize: CGFloat = UIDevice.current.isNarrowerThanIPhone6 ? 30 : 32
    let pickerPadding: CGFloat = 6
    var reactionHeight: CGFloat { return pickerDiameter - (pickerPadding * 2) }
    var selectedBackgroundHeight: CGFloat { return pickerDiameter - 4 }

    enum Emoji: Equatable {
        case emoji(String)
        case more
    }

    private enum Button: Equatable {
        case emoji(emoji: String, button: OWSFlatButton)
        case more(UIView)

        var emoji: Emoji {
            switch self {
            case .emoji(let emoji, _): .emoji(emoji)
            case .more: .more
            }
        }

        var emojiButton: OWSFlatButton? {
            switch self {
            case .emoji(_, let button): button
            case .more: nil
            }
        }

        var view: UIView {
            switch self {
            case let .emoji(_, button): button
            case let .more(button): button
            }
        }
    }

    private let emojiStackView: UIStackView = UIStackView()
    private var buttonForEmoji = [Button]()
    private var selectedEmoji: EmojiWithSkinTones?
    private var backgroundView: UIView?

    private let style: Style

    /// The individual emoji buttons and the Any button from `buttonForEmoji`
    private var buttonViews: [UIView] {
        return buttonForEmoji.map(\.view)
    }

    init(
        selectedEmoji: String?,
        delegate: MessageReactionPickerDelegate?,
        style: Style,
    ) {
        if let selectedEmoji {
            self.selectedEmoji = EmojiWithSkinTones(rawValue: selectedEmoji)
            owsAssertDebug(self.selectedEmoji != nil)
        } else {
            self.selectedEmoji = nil
        }
        self.delegate = delegate
        self.style = style

        super.init(frame: .zero)

        let liquidGlassIsAvailable: Bool = if #available(iOS 26, *) {
            true
        } else {
            false
        }

        var backgroundContentView: UIView?

        switch (style, liquidGlassIsAvailable) {
        case (.inline, _):
            break
        case (.configure, true), (.contextMenu(allowGlass: true), true):
            guard #available(iOS 26, *) else { break }
            let glassEffect = UIGlassEffect(style: .regular)
            let visualEffectView = UIVisualEffectView(effect: glassEffect)
            visualEffectView.cornerConfiguration = .capsule()
            addBackgroundView(visualEffectView)
            backgroundView = visualEffectView
            backgroundContentView = visualEffectView.contentView
        case (.configure, false), (.contextMenu(allowGlass: _), _):
            backgroundView = addBackgroundView(
                withBackgroundColor: .Signal.secondaryGroupedBackground,
                cornerRadius: pickerDiameter / 2,
            )
            backgroundView?.layer.cornerCurve = .continuous
            backgroundView?.layer.shadowColor = UIColor.black.cgColor
            backgroundView?.layer.shadowRadius = 4
            backgroundView?.layer.shadowOpacity = 0.05
            backgroundView?.layer.shadowOffset = .zero

            let shadowView = UIView()
            shadowView.backgroundColor = .Signal.secondaryGroupedBackground
            shadowView.layer.cornerRadius = pickerDiameter / 2
            shadowView.layer.shadowColor = UIColor.black.cgColor
            shadowView.layer.shadowRadius = 12
            shadowView.layer.shadowOpacity = 0.3
            shadowView.layer.shadowOffset = CGSize(width: 0, height: 4)
            backgroundView?.addSubview(shadowView)
            shadowView.autoPinEdgesToSuperviewEdges()
            backgroundContentView = backgroundView
        }

        autoSetDimension(.height, toSize: pickerDiameter)

        isLayoutMarginsRelativeArrangement = true
        // Inline picker's scroll view should go to the edge
        layoutMargins = .init(
            top: pickerPadding,
            leading: style.isInline ? 0 : pickerPadding,
            bottom: pickerPadding,
            trailing: style.isInline ? 4 : pickerPadding,
        )

        let emojiSet = currentEmojiSetOnDisk(style: style)

        var addAnyButton = !style.isConfigure

        if
            !style.isConfigure,
            let selectedEmoji = self.selectedEmoji,
            nil == emojiSet.firstIndex(of: selectedEmoji)
        {
            addAnyButton = false
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
            button.setTitle(
                title: emoji.rawValue,
                font: .systemFont(ofSize: reactionFontSize),
                titleColor: .Signal.label,
            )
            button.setPressedBlock { [weak self] in
                // current title of button may have changed in the meantime
                if let currentEmoji = button.button.title(for: .normal) {
                    ImpactHapticFeedback.impactOccurred(style: .light)
                    self?.delegate?.didSelectReaction(reaction: currentEmoji, isRemoving: currentEmoji == self?.selectedEmoji?.rawValue, inPosition: index)
                }
            }
            buttonForEmoji.append(.emoji(emoji: emoji.rawValue, button: button))
            emojiStackView.addArrangedSubview(button)

            // Add a circle behind the currently selected emoji
            if self.selectedEmoji == emoji {
                let selectedBackgroundView = UIView()
                selectedBackgroundView.backgroundColor = .Signal.secondaryFill
                selectedBackgroundView.clipsToBounds = true
                selectedBackgroundView.layer.cornerRadius = selectedBackgroundHeight / 2
                backgroundContentView?.addSubview(selectedBackgroundView)
                selectedBackgroundView.autoSetDimensions(to: CGSize(square: selectedBackgroundHeight))
                selectedBackgroundView.autoAlignAxis(.horizontal, toSameAxisOf: button)
                selectedBackgroundView.autoAlignAxis(.vertical, toSameAxisOf: button)
            }
        }

        if addAnyButton {
            let button = OWSButton { [weak self] in
                self?.delegate?.didSelectAnyEmoji()
            }
            button.autoSetDimensions(to: CGSize(square: reactionHeight))
            button.dimsWhenHighlighted = true

            let imageView = UIImageView(image: UIImage(resource: .more))
            imageView.contentMode = .scaleAspectFit
            imageView.tintColor = .Signal.secondaryLabel

            let imageBackground = UIView()
            imageBackground.backgroundColor = .Signal.primaryFill

            // Fill colors are translucent, so place over a normal background
            // so it looks solid when being pushed up.
            let backgroundBackground = UIView()
            backgroundBackground.backgroundColor = .Signal.background

            backgroundBackground.addSubview(imageBackground)
            imageBackground.autoPinEdgesToSuperviewEdges()

            backgroundBackground.addSubview(imageView)
            imageView.autoPinEdgesToSuperviewEdges(with: .init(margin: 2))

            button.addSubview(backgroundBackground)
            let size: CGFloat = 32
            backgroundBackground.autoSetDimensions(to: .square(size))
            backgroundBackground.layer.cornerRadius = size / 2
            backgroundBackground.clipsToBounds = true
            backgroundBackground.autoCenterInSuperview()
            backgroundBackground.isUserInteractionEnabled = false

            buttonForEmoji.append(.more(button))
            self.addArrangedSubview(button)
        }
    }

    private func currentEmojiSetOnDisk(style: Style) -> [EmojiWithSkinTones] {
        var emojiSet = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let customSetStrings = ReactionManager.customEmojiSet(transaction: transaction) ?? []
            let customSet = customSetStrings.lazy.map { EmojiWithSkinTones(rawValue: $0) }

            // Any holes or invalid choices are filled in with the default reactions.
            // This could happen if another platform supports an emoji that we don't yet (say, because there's a newer
            // version of Unicode), or if a bug results in a string that's not valid at all, or fewer entries than the
            // default.
            let savedReactions = ReactionManager.defaultEmojiSet.enumerated().map { i, defaultEmoji -> EmojiWithSkinTones in
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

        if !style.isConfigure, let selectedEmoji = self.selectedEmoji {
            // If the local user reacted with any of the default emoji set,
            // we should show it in the normal place in the picker bar.
            // NOTE: This used to match independent of skin tone, but we decided to drop that behavior.
            if let index = emojiSet.firstIndex(of: selectedEmoji) {
                emojiSet[index] = selectedEmoji
            } else {
                emojiSet.append(selectedEmoji)
            }
        }

        return emojiSet
    }

    func updateReactionPickerEmojis() {
        let currentEmojis = currentEmojiSetOnDisk(style: self.style)
        for (index, emoji) in self.currentEmojiSet().enumerated() {
            if let newEmoji = currentEmojis[safe: index]?.rawValue {
                self.replaceEmojiReaction(emoji, newEmoji: newEmoji, inPosition: index)
            }
        }
    }

    func replaceEmojiReaction(_ oldEmoji: String, newEmoji: String, inPosition position: Int) {
        guard let button = buttonForEmoji[position].emojiButton else { return }
        button.setTitle(title: newEmoji, font: .systemFont(ofSize: reactionFontSize), titleColor: .Signal.label)
        buttonForEmoji.replaceSubrange(
            position...position,
            with: [.emoji(emoji: newEmoji, button: button)],
        )
    }

    func currentEmojiSet() -> [String] {
        buttonForEmoji.compactMap { button in
            switch button {
            case .emoji(let emoji, _):
                emoji
            case .more:
                nil
            }
        }
    }

    func startReplaceAnimation(focusedEmoji: String, inPosition position: Int) {
        var buttonToWiggle: UIView?
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            for (index, button) in self.buttonViews.enumerated() {
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
            if finished, let buttonToWiggle {
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

    func endReplaceAnimation() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            for button in self.buttonViews {
                button.alpha = 1
                button.transform = CGAffineTransform.identity
                button.layer.removeAnimation(forKey: "wiggle")
            }
        } completion: { _ in }
    }

    func playPresentationAnimation(duration: TimeInterval, completion: (() -> Void)? = nil) {
        CATransaction.begin()
        if let completion {
            CATransaction.setCompletionBlock(completion)
        }
        if let backgroundView {
            backgroundView.alpha = 0
            UIView.animate(withDuration: duration) { backgroundView.alpha = 1 }
        }

        var delay: TimeInterval = 0
        for view in self.buttonViews {
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: 24)
            UIView.animate(withDuration: duration, delay: delay, options: .curveEaseIn, animations: {
                view.transform = .identity
                view.alpha = 1
            })
            delay += 0.01
        }
        CATransaction.commit()
    }

    func playDismissalAnimation(duration: TimeInterval, completion: @escaping () -> Void) {
        UIView.animate(withDuration: duration) {
            // This allows the glass effect to transition out
            (self.backgroundView as? UIVisualEffectView)?.effect = nil
            self.alpha = 0
        } completion: { _ in
            completion()
        }
    }

    var focusedEmoji: Emoji?
    func updateFocusPosition(_ position: CGPoint, animated: Bool) {
        var previouslyFocusedButton: UIView?
        var focusedButton: UIView?

        if
            let focusedEmoji,
            let focusedButton = buttonForEmoji.first(where: { $0.emoji == focusedEmoji })?.view
        {
            previouslyFocusedButton = focusedButton
        }

        focusedEmoji = nil

        for button in buttonForEmoji {
            guard focusArea(for: button.view).contains(position) else { continue }
            focusedEmoji = button.emoji
            focusedButton = button.view
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
        var fadeLocation: CGFloat = 31 / 32
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
