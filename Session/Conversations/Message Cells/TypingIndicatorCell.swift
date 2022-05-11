// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

// Assumptions
// • We'll never encounter an outgoing typing indicator.
// • Typing indicators are only sent in contact threads.
final class TypingIndicatorCell: MessageCell {
    // MARK: - UI
    
    private lazy var bubbleView: UIView = {
        let result: UIView = UIView()
        result.layer.cornerRadius = VisibleMessageCell.smallCornerRadius
        result.backgroundColor = Colors.receivedMessageBackground
        
        return result
    }()

    private let bubbleViewMaskLayer: CAShapeLayer = CAShapeLayer()

    private lazy var typingIndicatorView: TypingIndicatorView = TypingIndicatorView()

    // MARK: - Lifecycle
    
    override func setUpViewHierarchy() {
        super.setUpViewHierarchy()
        
        // Bubble view
        addSubview(bubbleView)
        bubbleView.pin(.left, to: .left, of: self, withInset: VisibleMessageCell.contactThreadHSpacing)
        bubbleView.pin(.top, to: .top, of: self, withInset: 1)
        
        // Typing indicator view
        bubbleView.addSubview(typingIndicatorView)
        typingIndicatorView.pin(to: bubbleView, withInset: 12)
    }

    // MARK: - Updating
    
    override func update(with item: ConversationViewModel.Item, mediaCache: NSCache<NSString, AnyObject>, playbackInfo: ConversationViewModel.PlaybackInfo?, lastSearchText: String?) {
        guard item.cellType == .typingIndicator else { return }
        
        self.item = item
        
        // Bubble view
        updateBubbleViewCorners()
        
        // Typing indicator view
        typingIndicatorView.startAnimation()
    }
    
    override func dynamicUpdate(with item: ConversationViewModel.Item, playbackInfo: ConversationViewModel.PlaybackInfo?) {
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        updateBubbleViewCorners()
    }

    private func updateBubbleViewCorners() {
        let maskPath = UIBezierPath(
            roundedRect: bubbleView.bounds,
            byRoundingCorners: getCornersToRound(),
            cornerRadii: CGSize(
                width: VisibleMessageCell.largeCornerRadius,
                height: VisibleMessageCell.largeCornerRadius)
        )
        
        bubbleViewMaskLayer.path = maskPath.cgPath
        bubbleView.layer.mask = bubbleViewMaskLayer
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        
        typingIndicatorView.stopAnimation()
    }

    // MARK: - Convenience
    
    private func getCornersToRound() -> UIRectCorner {
        guard item?.isOnlyMessageInCluster == false else { return .allCorners }
        
        switch item?.positionInCluster {
            case .top: return [ .topLeft, .topRight, .bottomRight ]
            case .middle: return [ .topRight, .bottomRight ]
            case .bottom: return [ .topRight, .bottomRight, .bottomLeft ]
            case .none: return .allCorners
        }
    }
}
