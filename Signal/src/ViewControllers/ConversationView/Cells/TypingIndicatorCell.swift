//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

    private let kMinBubbleHeight: CGFloat = 36

    private let stackView = UIStackView()
    private let avatarContainer = UIView()
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

        stackView.axis = .horizontal
        stackView.spacing = ConversationStyle.messageStackSpacing
        stackView.isLayoutMarginsRelativeArrangement = true
        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()

        avatarView.autoSetDimensions(to: CGSize(square: ConversationStyle.groupMessageAvatarDiameter))
        avatarContainer.addSubview(avatarView)
        avatarView.autoPinWidthToSuperview()
        avatarView.autoVCenterInSuperview()
        stackView.addArrangedSubview(avatarContainer)

        bubbleView.layoutMargins = .zero
        bubbleView.addSubview(typingIndicatorView)
        stackView.addArrangedSubview(bubbleView)

        stackView.addArrangedSubview(UIView.hStretchingSpacer())
    }

    @objc
    public override func loadForDisplay() {
        guard let conversationStyle = self.conversationStyle else {
            owsFailDebug("Missing conversationStyle")
            return
        }

        stackView.layoutMargins = UIEdgeInsets(
            top: 0,
            leading: conversationStyle.gutterLeading,
            bottom: 0,
            trailing: conversationStyle.gutterTrailing
        )

        bubbleView.fillColor = conversationStyle.bubbleColor(isIncoming: true)
        typingIndicatorView.startAnimation()

        viewConstraints.append(contentsOf: [
            typingIndicatorView.autoPinEdge(toSuperviewEdge: .leading, withInset: conversationStyle.textInsetHorizontal),
            typingIndicatorView.autoPinEdge(toSuperviewEdge: .trailing, withInset: conversationStyle.textInsetHorizontal),
            typingIndicatorView.autoPinTopToSuperviewMargin(withInset: conversationStyle.textInsetTop),
            typingIndicatorView.autoPinBottomToSuperviewMargin(withInset: conversationStyle.textInsetBottom)
        ])

        avatarContainer.isHidden = !configureAvatarView()
    }

    private func configureAvatarView() -> Bool {
        guard let viewItem = self.viewItem else {
            owsFailDebug("Missing viewItem")
            return false
        }
        guard let typingIndicators = viewItem.interaction as? TypingIndicatorInteraction else {
            owsFailDebug("Missing typingIndicators")
            return false
        }
        guard shouldShowAvatar() else {
            return false
        }
        guard let colorName = viewItem.authorConversationColorName else {
            owsFailDebug("Missing authorConversationColorName")
            return false
        }
        guard let authorAvatarImage =
            OWSContactAvatarBuilder(address: typingIndicators.address,
                                    colorName: ConversationColorName(rawValue: colorName),
                                    diameter: UInt(ConversationStyle.groupMessageAvatarDiameter)).build() else {
                                        owsFailDebug("Could build avatar image")
                                        return false
        }
        avatarView.image = authorAvatarImage
        return true
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
            return CGSizeCeil(CGSize(width: ConversationStyle.groupMessageAvatarDiameter + ConversationStyle.messageStackSpacing + bubbleSize.width,
                                     height: max(kMinBubbleHeight, bubbleSize.height)))
        } else {
            return CGSizeCeil(CGSize(width: bubbleSize.width,
                                     height: max(kMinBubbleHeight, bubbleSize.height)))
        }
    }

    @objc
    public override func prepareForReuse() {
        super.prepareForReuse()

        NSLayoutConstraint.deactivate(viewConstraints)
        viewConstraints = [NSLayoutConstraint]()

        avatarView.image = nil

        typingIndicatorView.stopAnimation()
    }
}
