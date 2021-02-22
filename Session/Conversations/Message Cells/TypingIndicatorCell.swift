
// Assumptions
// • We'll never encounter an outgoing typing indicator.
// • Typing indicators are only sent in contact threads.

final class TypingIndicatorCell : MessageCell {

    private var positionInCluster: Position? {
        guard let viewItem = viewItem else { return nil }
        if viewItem.isFirstInCluster { return .top }
        if viewItem.isLastInCluster { return .bottom }
        return .middle
    }
    
    private var isOnlyMessageInCluster: Bool { viewItem?.isFirstInCluster == true && viewItem?.isLastInCluster == true }

    // MARK: UI Components
    private lazy var bubbleView: UIView = {
        let result = UIView()
        result.layer.cornerRadius = VisibleMessageCell.smallCornerRadius
        result.backgroundColor = Colors.receivedMessageBackground
        return result
    }()

    private let bubbleViewMaskLayer = CAShapeLayer()

    private lazy var typingIndicatorView = TypingIndicatorView()

    // MARK: Settings
    override class var identifier: String { "TypingIndicatorCell" }

    // MARK: Direction & Position
    enum Position { case top, middle, bottom }

    // MARK: Lifecycle
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

    // MARK: Updating
    override func update() {
        guard let viewItem = viewItem, viewItem.interaction is TypingIndicatorInteraction else { return }
        // Bubble view
        updateBubbleViewCorners()
        // Typing indicator view
        typingIndicatorView.startAnimation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateBubbleViewCorners()
    }

    private func updateBubbleViewCorners() {
        let maskPath = UIBezierPath(roundedRect: bubbleView.bounds, byRoundingCorners: getCornersToRound(),
            cornerRadii: CGSize(width: VisibleMessageCell.largeCornerRadius, height: VisibleMessageCell.largeCornerRadius))
        bubbleViewMaskLayer.path = maskPath.cgPath
        bubbleView.layer.mask = bubbleViewMaskLayer
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        typingIndicatorView.stopAnimation()
    }

    // MARK: Convenience
    private func getCornersToRound() -> UIRectCorner {
        guard !isOnlyMessageInCluster else { return .allCorners }
        let result: UIRectCorner
        switch positionInCluster {
        case .top: result = [ .topLeft, .topRight, .bottomRight ]
        case .middle: result = [ .topRight, .bottomRight ]
        case .bottom: result = [ .topRight, .bottomRight, .bottomLeft ]
        case nil: result = .allCorners
        }
        return result
    }
}
