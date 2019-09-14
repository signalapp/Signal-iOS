//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSTypingIndicatorCell)
public class TypingIndicatorCell: ConversationViewCell {

    @objc
    public static let cellReuseIdentifier = "TypingIndicatorCell"

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    private let kAvatarSize: CGFloat = 36
    private let kAvatarHSpacing: CGFloat = 8

    private let avatarView = AvatarImageView()
    private let bubbleView = OWSBubbleView()
    private let typingIndicatorView = TypingIndicatorView()
    private var viewConstraints = [NSLayoutConstraint]()

    override init(frame: CGRect) {
        super.init(frame: frame)

        commonInit()
    }

    private func commonInit() {
        self.layoutMargins = .zero
        self.contentView.layoutMargins = .zero

        bubbleView.layoutMargins = .zero

        bubbleView.addSubview(typingIndicatorView)
        contentView.addSubview(bubbleView)

        avatarView.autoSetDimension(.width, toSize: kAvatarSize)
        avatarView.autoSetDimension(.height, toSize: kAvatarSize)
    }

    @objc
    public override func loadForDisplay() {
        guard let conversationStyle = self.conversationStyle else {
            owsFailDebug("Missing conversationStyle")
            return
        }

        bubbleView.fillColor = conversationStyle.bubbleColor(isIncoming: true)
        typingIndicatorView.startAnimation()

        viewConstraints.append(contentsOf: [
            bubbleView.autoPinEdge(toSuperviewEdge: .leading, withInset: conversationStyle.gutterLeading),
            bubbleView.autoPinEdge(toSuperviewEdge: .trailing, withInset: conversationStyle.gutterTrailing, relation: .greaterThanOrEqual),
            bubbleView.autoPinTopToSuperviewMargin(withInset: 0),
            bubbleView.autoPinBottomToSuperviewMargin(withInset: 0),

            typingIndicatorView.autoPinEdge(toSuperviewEdge: .leading, withInset: conversationStyle.textInsetHorizontal),
            typingIndicatorView.autoPinEdge(toSuperviewEdge: .trailing, withInset: conversationStyle.textInsetHorizontal),
            typingIndicatorView.autoPinTopToSuperviewMargin(withInset: conversationStyle.textInsetTop),
            typingIndicatorView.autoPinBottomToSuperviewMargin(withInset: conversationStyle.textInsetBottom)
            ])

        if let avatarView = configureAvatarView() {
            contentView.addSubview(avatarView)
            viewConstraints.append(contentsOf: [
                bubbleView.autoPinLeading(toTrailingEdgeOf: avatarView, offset: kAvatarHSpacing),
                bubbleView.autoAlignAxis(.horizontal, toSameAxisOf: avatarView)
                ])

        } else {
            avatarView.removeFromSuperview()
        }
    }

    private func configureAvatarView() -> UIView? {
        guard let viewItem = self.viewItem else {
            owsFailDebug("Missing viewItem")
            return nil
        }
        guard let typingIndicators = viewItem.interaction as? TypingIndicatorInteraction else {
            owsFailDebug("Missing typingIndicators")
            return nil
        }
        guard shouldShowAvatar() else {
            return nil
        }
        guard let colorName = viewItem.authorConversationColorName else {
            owsFailDebug("Missing authorConversationColorName")
            return nil
        }
        guard let authorAvatarImage =
            OWSContactAvatarBuilder(address: typingIndicators.address,
                                    colorName: ConversationColorName(rawValue: colorName),
                                    diameter: UInt(kAvatarSize)).build() else {
                                        owsFailDebug("Could build avatar image")
                                        return nil
        }
        avatarView.image = authorAvatarImage
        return avatarView
    }

    private func shouldShowAvatar() -> Bool {
        guard let viewItem = self.viewItem else {
            owsFailDebug("Missing viewItem")
            return false
        }
        return viewItem.isGroupThread
    }

    @objc
    public override func cellSize() -> CGSize {
        guard let conversationStyle = self.conversationStyle else {
            owsFailDebug("Missing conversationStyle")
            return .zero
        }

        let insetsSize = CGSize(width: conversationStyle.textInsetHorizontal * 2,
                                height: conversationStyle.textInsetTop + conversationStyle.textInsetBottom)
        let typingIndicatorSize = typingIndicatorView.sizeThatFits(.zero)
        let bubbleSize = CGSizeAdd(insetsSize, typingIndicatorSize)

        if shouldShowAvatar() {
            return CGSizeCeil(CGSize(width: kAvatarSize + kAvatarHSpacing + bubbleSize.width,
                                     height: max(kAvatarSize, bubbleSize.height)))
        } else {
            return CGSizeCeil(CGSize(width: bubbleSize.width,
                                     height: max(kAvatarSize, bubbleSize.height)))
        }
    }

    @objc
    public override func prepareForReuse() {
        super.prepareForReuse()

        NSLayoutConstraint.deactivate(viewConstraints)
        viewConstraints = [NSLayoutConstraint]()

        avatarView.image = nil
        avatarView.removeFromSuperview()

        typingIndicatorView.stopAnimation()
    }
}
