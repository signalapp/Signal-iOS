//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentTypingIndicator: CVComponentBase, CVRootComponent {

    public var cellReuseIdentifier: CVCellReuseIdentifier {
        CVCellReuseIdentifier.typingIndicator
    }

    public let isDedicatedCell = true

    private let typingIndicator: CVComponentState.TypingIndicator

    required init(itemModel: CVItemModel,
                  typingIndicator: CVComponentState.TypingIndicator) {
        self.typingIndicator = typingIndicator

        super.init(itemModel: itemModel)
    }

    public func configure(cellView: UIView,
                          cellMeasurement: CVCellMeasurement,
                          componentDelegate: CVComponentDelegate,
                          cellSelection: CVCellSelection,
                          swipeToReplyState: CVSwipeToReplyState,
                          componentView: CVComponentView) {

        configureForRendering(componentView: componentView,
                              cellMeasurement: cellMeasurement,
                              componentDelegate: componentDelegate)

        let rootView = componentView.rootView
        if rootView.superview == nil {
            owsAssertDebug(cellView.layoutMargins == .zero)
            owsAssertDebug(cellView.subviews.isEmpty)

            cellView.addSubview(rootView)
            rootView.autoPinEdgesToSuperviewMargins()
        }
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewTypingIndicator()
    }

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentView as? CVComponentViewTypingIndicator else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let stackView = componentView.stackView
        let bubbleView = componentView.bubbleView

        stackView.apply(config: outerStackViewConfig)

        bubbleView.fillColor = conversationStyle.bubbleColor(isIncoming: true)

        typealias AvatarLayoutBlock = () -> Void
        let avatarView = componentView.avatarView

        var hasAvatar = false
        if let avatarImage = typingIndicator.avatar {
            avatarView.image = avatarImage
            hasAvatar = true
        }
        avatarView.isHidden = !hasAvatar

        let typingIndicatorView = componentView.typingIndicatorView

        let isReusing = stackView.superview != nil
        if !isReusing {
            stackView.addSubview(avatarView)
            stackView.addSubview(bubbleView)
            stackView.addSubview(typingIndicatorView)
        }

        let outerStackViewConfig = self.outerStackViewConfig
        let innerLayoutMargins = self.innerLayoutMargins
        let outerLayoutMargins = self.outerLayoutMargins
        let avatarDiameter = ConversationStyle.groupMessageAvatarDiameter
        let avatarSize = CGSize(square: avatarDiameter)
        let typingIndicatorSize = TypingIndicatorView.measureSize
        let minBubbleHeight = self.minBubbleHeight
        stackView.layoutBlock = { (superview: UIView) in
            var outerFrame = superview.bounds.inset(by: outerLayoutMargins)

            if hasAvatar {
                var avatarFrame = CGRect.zero
                avatarFrame.x = outerFrame.x
                avatarFrame.y = (outerFrame.height - avatarDiameter) * 0.5
                avatarFrame.size = avatarSize
                avatarView.frame = avatarFrame

                let inset = avatarDiameter + outerStackViewConfig.spacing
                outerFrame.x += inset
                outerFrame.width -= inset
            }

            var bubbleFrame = CGRect.zero
            bubbleFrame.size = typingIndicatorSize.plus(innerLayoutMargins.asSize)
            bubbleFrame.height = max(bubbleFrame.height, minBubbleHeight)
            bubbleFrame.x = outerFrame.x
            bubbleFrame.y = (outerFrame.height - bubbleFrame.height) * 0.5
            bubbleView.frame = bubbleFrame

            var typingIndicatorViewFrame = CGRect.zero
            typingIndicatorViewFrame.width = typingIndicatorSize.width
            typingIndicatorViewFrame.height = bubbleFrame.height - innerLayoutMargins.asSize.height
            typingIndicatorViewFrame.x = outerFrame.x + innerLayoutMargins.left
            typingIndicatorViewFrame.y = (outerFrame.height - typingIndicatorViewFrame.height) * 0.5
            typingIndicatorView.frame = typingIndicatorViewFrame
        }
    }

    private var outerStackViewConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .fill,
                          spacing: ConversationStyle.messageStackSpacing,
                          layoutMargins: outerLayoutMargins)
    }

    private var outerLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(top: 0,
                     leading: conversationStyle.gutterLeading,
                     bottom: 0,
                     trailing: conversationStyle.gutterTrailing)
    }

    private var innerLayoutMargins: UIEdgeInsets {
        conversationStyle.textInsets
    }

    private let minBubbleHeight: CGFloat = 36

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let insetsSize = innerLayoutMargins.asSize
        let typingIndicatorSize = TypingIndicatorView.measureSize
        let bubbleSize = CGSizeAdd(insetsSize, typingIndicatorSize)

        let width: CGFloat
        if typingIndicator.avatar != nil {
            width = ConversationStyle.groupMessageAvatarDiameter + ConversationStyle.messageStackSpacing + bubbleSize.width
        } else {
            width = bubbleSize.width
        }

        let height = max(minBubbleHeight, bubbleSize.height)
        return CGSize(width: width, height: height).ceil
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewTypingIndicator: NSObject, CVComponentView {

        fileprivate let stackView = OWSStackView(name: "Typing indicator")

        fileprivate let avatarView = AvatarImageView()
        fileprivate let bubbleView = OWSBubbleView()
        fileprivate let typingIndicatorView = TypingIndicatorView()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            stackView
        }

        // MARK: -

        public func setIsCellVisible(_ isCellVisible: Bool) {
            if isCellVisible {
                typingIndicatorView.startAnimation()
            } else {
                typingIndicatorView.stopAnimation()
            }
        }

        public func reset() {
            owsAssertDebug(isDedicatedCellView)

            if !isDedicatedCellView {
                stackView.reset()
            }
            stackView.layoutBlock = nil

            avatarView.image = nil

            typingIndicatorView.stopAnimation()
        }
    }
}
