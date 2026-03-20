//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SDWebImage
import SignalServiceKit
import SignalUI

protocol MessageReactionPickerDelegate: AnyObject {
    func didSelectReaction(_ reaction: CustomReactionItem, isRemoving: Bool, inPosition position: Int)
    func didSelectMore()
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

    enum Reaction: Equatable {
        case reaction(CustomReactionItem)
        case more
    }

    private enum Button: Equatable {
        case reaction(item: CustomReactionItem, button: OWSFlatButton)
        case stickerReaction(item: CustomReactionItem, button: OWSButton, imageView: SDAnimatedImageView)
        case more(UIView)

        var focusedReaction: Reaction {
            switch self {
            case .reaction(let item, _): .reaction(item)
            case .stickerReaction(let item, _, _): .reaction(item)
            case .more: .more
            }
        }

        var reactionItem: CustomReactionItem? {
            switch self {
            case .reaction(let item, _): item
            case .stickerReaction(let item, _, _): item
            case .more: nil
            }
        }

        var emojiButton: OWSFlatButton? {
            switch self {
            case .reaction(_, let button): button
            default: nil
            }
        }

        var stickerImageView: SDAnimatedImageView? {
            switch self {
            case .stickerReaction(_, _, let imageView): imageView
            default: nil
            }
        }

        var view: UIView {
            switch self {
            case let .reaction(_, button): button
            case let .stickerReaction(_, button, _): button
            case let .more(button): button
            }
        }

        static func == (lhs: Button, rhs: Button) -> Bool {
            switch (lhs, rhs) {
            case (.reaction(let l, _), .reaction(let r, _)): return l == r
            case (.stickerReaction(let l, _, _), .stickerReaction(let r, _, _)): return l == r
            case (.more, .more): return true
            default: return false
            }
        }
    }

    private let emojiStackView: UIStackView = UIStackView()
    private var buttonForReaction = [Button]()
    private(set) var selectedReaction: CustomReactionItem?
    private var backgroundView: UIView?

    private let style: Style
    private let allowStickers: Bool

    /// The individual reaction buttons and the Any button from `buttonForReaction`
    private var buttonViews: [UIView] {
        return buttonForReaction.map(\.view)
    }

    /// If allowStickers is false, and a sticker is set as one of the default displayed
    /// "custom reaction set" items, will fall back to that sticker's emoji. (And will not
    /// show the sticker picker tab).
    init(
        selectedReaction: CustomReactionItem?,
        delegate: MessageReactionPickerDelegate?,
        style: Style,
        allowStickers: Bool = true,
    ) {
        if let selectedReaction {
            if EmojiWithSkinTones(rawValue: selectedReaction.emoji) == nil {
                owsFailDebug("Invalid (unknown) preselected emoji")
                self.selectedReaction = nil
            } else {
                self.selectedReaction = selectedReaction
            }
        } else {
            self.selectedReaction = nil
        }
        self.delegate = delegate
        self.style = style
        self.allowStickers = allowStickers

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

        let reactionSet = currentReactionSetOnDisk(style: style)

        var addMoreButton = !style.isConfigure

        if
            !style.isConfigure,
            let selected = self.selectedReaction,
            nil == reactionSet.firstIndex(of: selected)
        {
            addMoreButton = false
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

        for (index, item) in reactionSet.enumerated() {
            let buttonView: UIView
            if allowStickers, item.isStickerReaction, let stickerInfo = item.sticker {
                let (button, imageView) = buildStickerButton(item: item, stickerInfo: stickerInfo, index: index)
                buttonView = button
                buttonForReaction.append(.stickerReaction(item: item, button: button, imageView: imageView))
                emojiStackView.addArrangedSubview(button)
            } else {
                let button = buildEmojiButton(item: item, index: index)
                buttonForReaction.append(.reaction(item: item, button: button))
                emojiStackView.addArrangedSubview(button)
                buttonView = button
            }

            // Add a circle behind the currently selected reaction
            if self.selectedReaction == item {
                let selectedBackgroundView = UIView()
                selectedBackgroundView.backgroundColor = .Signal.secondaryFill
                selectedBackgroundView.clipsToBounds = true
                selectedBackgroundView.layer.cornerRadius = selectedBackgroundHeight / 2
                backgroundContentView?.addSubview(selectedBackgroundView)
                selectedBackgroundView.autoSetDimensions(to: CGSize(square: selectedBackgroundHeight))
                selectedBackgroundView.autoAlignAxis(.horizontal, toSameAxisOf: buttonView)
                selectedBackgroundView.autoAlignAxis(.vertical, toSameAxisOf: buttonView)
            }
        }

        if addMoreButton {
            let button = OWSButton { [weak self] in
                self?.delegate?.didSelectMore()
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

            buttonForReaction.append(.more(button))
            self.addArrangedSubview(button)
        }
    }

    private func buildEmojiButton(
        item: CustomReactionItem,
        index: Int
    ) -> OWSFlatButton {
        let button = OWSFlatButton()
        button.autoSetDimensions(to: CGSize(square: reactionHeight))
        button.setTitle(
            title: item.emoji,
            font: .systemFont(ofSize: reactionFontSize),
            titleColor: .Signal.label,
        )
        button.setPressedBlock { [weak self, weak button] in
            guard let self, let currentEmoji = button?.button.title(for: .normal) else { return }
            ImpactHapticFeedback.impactOccurred(style: .light)
            let reaction = CustomReactionItem(emoji: currentEmoji, sticker: nil)
            let isRemoving = self.selectedReaction == reaction
            if self.allowStickers {
                self.delegate?.didSelectReaction(
                    reaction,
                    isRemoving: isRemoving,
                    inPosition: index)
            } else {
                self.delegate?.didSelectReaction(
                    CustomReactionItem(emoji: reaction.emoji, sticker: nil),
                    isRemoving: isRemoving,
                    inPosition: index
                )
            }
        }
        return button
    }

    private func buildStickerButton(
        item: CustomReactionItem,
        stickerInfo: StickerInfo,
        index: Int,
    ) -> (OWSButton, SDAnimatedImageView) {
        let button = OWSButton { [weak self] in
            guard let self else { return }
            ImpactHapticFeedback.impactOccurred(style: .light)
            let isRemoving = self.selectedReaction == item
            self.delegate?.didSelectReaction(item, isRemoving: isRemoving, inPosition: index)
        }
        button.autoSetDimensions(to: CGSize(square: reactionHeight))
        button.dimsWhenHighlighted = true

        let imageView = SDAnimatedImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        button.addSubview(imageView)
        imageView.autoCenterInSuperview()
        let imageSize: CGFloat = reactionHeight - 4
        imageView.autoSetDimensions(to: CGSize(square: imageSize))

        loadStickerImage(stickerInfo: stickerInfo, into: imageView, index: index)

        return (button, imageView)
    }

    private func loadStickerImage(
        stickerInfo: StickerInfo,
        into imageView: SDAnimatedImageView,
        index: Int
    ) {
        Task { [weak self, weak imageView] in
            let image: UIImage? = SSKEnvironment.shared.databaseStorageRef.read { tx in
                guard
                    let metadata = StickerManager.installedStickerMetadata(stickerInfo: stickerInfo, transaction: tx),
                    let data = try? metadata.readStickerData()
                else {
                    return nil
                }
                return SDAnimatedImage(data: data)
            }
            await MainActor.run {
                guard
                    let self,
                    let imageView,
                    let currentSticker = self.buttonForReaction[safe: index]?.reactionItem?.sticker,
                    currentSticker.packId == stickerInfo.packId,
                    currentSticker.stickerId == stickerInfo.stickerId
                else {
                    return
                }
                imageView.image = image
            }
        }
    }

    private func currentReactionSetOnDisk(style: Style) -> [CustomReactionItem] {
        var reactionSet = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let customSet = ReactionManager.customReactionSet(tx: transaction)
                ?? ReactionManager.defaultCustomReactionSet

            // Any holes or invalid choices are filled in with the default reactions.
            // This could happen if another platform supports an emoji that we don't yet (say, because there's a newer
            // version of Unicode), or if a bug results in a string that's not valid at all, or fewer entries than the
            // default.
            let savedReactions = ReactionManager.defaultCustomReactionSet.enumerated().map { i, defaultReaction -> CustomReactionItem in
                // Treat "out-of-bounds index" and "in-bounds but not valid" the same way.
                if let customReaction = customSet[safe: i] ?? nil {
                    return customReaction
                } else {
                    return defaultReaction
                }
            }

            var recentReactions = [CustomReactionItem]()

            // Add recent emoji to inline picker
            if style.isInline {
                let savedReactionSet = Set(savedReactions)

                let recentEmoji = EmojiPickerCollectionView
                    .getRecentEmoji(tx: transaction)
                    .lazy
                    .map { CustomReactionItem(emoji: $0.rawValue, sticker: nil) }
                    .filter { !savedReactionSet.contains($0) }
                let recentStickers = StickerManager
                    .recentStickers(transaction: transaction)
                    .lazy
                    .map {
                        CustomReactionItem(
                            emoji: $0.emojiString ?? ReactionPickerSheet.fallbackStickerEmoji,
                            sticker: $0.info
                        )
                    }
                    .filter { !savedReactionSet.contains($0) }
                for i in 0..<max(recentEmoji.count, recentStickers.count) {
                    // TODO: apply global ordering, not just interleaving
                    recentEmoji[safe: i].map { recentReactions.append($0) }
                    recentStickers[safe: i].map { recentReactions.append($0) }
                }
            }

            return savedReactions + recentReactions
        }

        if !style.isConfigure, let selected = self.selectedReaction {
            if let index = reactionSet.firstIndex(of: selected) {
                reactionSet[index] = selected
            } else {
                reactionSet.append(selected)
            }
        }

        return reactionSet
    }

    func updateReactionPickerItems() {
        let currentItems = currentReactionSetOnDisk(style: self.style)
        for (index, item) in currentReactionItems().enumerated() {
            if let newItem = currentItems[safe: index] {
                self.replaceReaction(item, new: newItem, inPosition: index)
            }
        }
    }

    func replaceReaction(
        _ old: CustomReactionItem,
        new: CustomReactionItem,
        inPosition position: Int
    ) {
        guard let existingButton = buttonForReaction[safe: position] else {
            return
        }
        if allowStickers, let sticker = new.sticker {
            if let imageView = existingButton.stickerImageView, case .stickerReaction(_, let existingBtn, _) = existingButton {
                loadStickerImage(stickerInfo: sticker, into: imageView, index: position)
                buttonForReaction.replaceSubrange(
                    position...position,
                    with: [.stickerReaction(item: new, button: existingBtn, imageView: imageView)],
                )
            } else {
                let (button, imageView) = buildStickerButton(item: new, stickerInfo: sticker, index: position)
                buttonForReaction[position] = .stickerReaction(item: new, button: button, imageView: imageView)
                emojiStackView.arrangedSubviews[position].removeFromSuperview()
                emojiStackView.insertArrangedSubview(button, at: position)
            }
        } else {
            if let button = existingButton.emojiButton {
                button.setTitle(title: new.emoji, font: .systemFont(ofSize: reactionFontSize), titleColor: .Signal.label)
                buttonForReaction.replaceSubrange(
                    position...position,
                    with: [.reaction(item: new, button: button)],
                )
            } else {
                let button = buildEmojiButton(item: new, index: position)
                buttonForReaction[position] = .reaction(item: new, button: button)
                emojiStackView.arrangedSubviews[position].removeFromSuperview()
                emojiStackView.insertArrangedSubview(button, at: position)
            }
        }
    }

    /// Returns all reaction items (emoji + sticker) for non-more buttons.
    func currentReactionItems() -> [CustomReactionItem] {
        buttonForReaction.compactMap(\.reactionItem)
    }

    func startReplaceAnimation(focusedReaction: CustomReactionItem, inPosition position: Int) {
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

    var focusedReaction: Reaction?
    func updateFocusPosition(_ position: CGPoint, animated: Bool) {
        var previouslyFocusedButton: UIView?
        var focusedButton: UIView?

        if
            let focusedReaction,
            let focusedButton = buttonForReaction
                .first(where: { $0.focusedReaction == focusedReaction })?
                .view
        {
            previouslyFocusedButton = focusedButton
        }

        focusedReaction = nil

        for button in buttonForReaction {
            guard focusArea(for: button.view).contains(position) else { continue }
            focusedReaction = button.focusedReaction
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
