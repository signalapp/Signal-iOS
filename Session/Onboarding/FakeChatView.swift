
final class FakeChatView : UIView {
    private let spacing = Values.mediumSpacing
    
    var contentOffset: CGPoint {
        get { return scrollView.contentOffset }
        set { scrollView.contentOffset = newValue }
    }
    
    private lazy var chatBubbles = [
        getChatBubble(withText: NSLocalizedString("view_fake_chat_bubble_1", comment: ""), wasSentByCurrentUser: true),
        getChatBubble(withText: NSLocalizedString("view_fake_chat_bubble_2", comment: ""), wasSentByCurrentUser: false),
        getChatBubble(withText: NSLocalizedString("view_fake_chat_bubble_3", comment: ""), wasSentByCurrentUser: true),
        getChatBubble(withText: NSLocalizedString("view_fake_chat_bubble_4", comment: ""), wasSentByCurrentUser: false),
        getChatBubble(withText: NSLocalizedString("view_fake_chat_bubble_5", comment: ""), wasSentByCurrentUser: false)
    ]
    
    private lazy var scrollView: UIScrollView = {
        let result = UIScrollView()
        result.showsHorizontalScrollIndicator = false
        result.showsVerticalScrollIndicator = false
        return result
    }()
    
    private static let bubbleWidth = CGFloat(224)
    private static let bubbleCornerRadius = CGFloat(10)
    private static let startDelay: TimeInterval = 1
    private static let animationDuration: TimeInterval = 0.4
    private static let chatDelay: TimeInterval = 1.5
    private static let popAnimationStartScale: CGFloat = 0.6
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViewHierarchy()
        animate()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
        animate()
    }
    
    private func setUpViewHierarchy() {
        let stackView = UIStackView(arrangedSubviews: chatBubbles)
        stackView.axis = .vertical
        stackView.spacing = spacing
        stackView.alignment = .fill
        let vInset = Values.smallSpacing
        stackView.layoutMargins = UIEdgeInsets(top: vInset, leading: Values.veryLargeSpacing, bottom: vInset, trailing: Values.veryLargeSpacing)
        stackView.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(stackView)
        stackView.pin(to: scrollView)
        stackView.set(.width, to: .width, of: scrollView)
        addSubview(scrollView)
        scrollView.pin(to: self)
        let height = chatBubbles.reduce(0) { $0 + $1.systemLayoutSizeFitting(UIView.layoutFittingExpandedSize).height } + CGFloat(chatBubbles.count - 1) * spacing + 2 * vInset
        scrollView.contentSize = CGSize(width: UIScreen.main.bounds.width, height: height)
    }
    
    private func getChatBubble(withText text: String, wasSentByCurrentUser: Bool) -> UIView {
        let result = UIView()
        let bubbleView = UIView()
        bubbleView.set(.width, to: FakeChatView.bubbleWidth)
        bubbleView.layer.cornerRadius = FakeChatView.bubbleCornerRadius
        bubbleView.layer.shadowColor = UIColor.black.cgColor
        bubbleView.layer.shadowRadius = isLightMode ? 4 : 8
        bubbleView.layer.shadowOpacity = isLightMode ? 0.16 : 0.24
        bubbleView.layer.shadowOffset = CGSize.zero
        let backgroundColor = wasSentByCurrentUser ? Colors.fakeChatBubbleBackground : Colors.accent
        bubbleView.backgroundColor = backgroundColor
        let label = UILabel()
        let textColor = wasSentByCurrentUser ? Colors.text : Colors.fakeChatBubbleText
        label.textColor = textColor
        label.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.text = text
        bubbleView.addSubview(label)
        label.pin(to: bubbleView, withInset: 12)
        result.addSubview(bubbleView)
        bubbleView.pin(.top, to: .top, of: result)
        result.pin(.bottom, to: .bottom, of: bubbleView)
        if wasSentByCurrentUser {
            bubbleView.pin(.trailing, to: .trailing, of: result)
        } else {
            result.pin(.leading, to: .leading, of: bubbleView)
        }
        return result
    }
    
    private func animate() {
        let animationDuration = FakeChatView.animationDuration
        let delayBetweenMessages = FakeChatView.chatDelay
        chatBubbles.forEach { $0.alpha = 0 }
        Timer.scheduledTimer(withTimeInterval: FakeChatView.startDelay, repeats: false) { [weak self] _ in
            self?.showChatBubble(at: 0)
            Timer.scheduledTimer(withTimeInterval: 1.5 * delayBetweenMessages, repeats: false) { _ in
                self?.showChatBubble(at: 1)
                Timer.scheduledTimer(withTimeInterval: 1.5 * delayBetweenMessages, repeats: false) { _ in
                    self?.showChatBubble(at: 2)
                    UIView.animate(withDuration: animationDuration) {
                        guard let self = self else { return }
                        self.scrollView.contentOffset = CGPoint(x: 0, y: self.chatBubbles[0].height() + self.spacing)
                    }
                    Timer.scheduledTimer(withTimeInterval: 1.5 * delayBetweenMessages, repeats: false) { _ in
                        self?.showChatBubble(at: 3)
                        UIView.animate(withDuration: animationDuration) {
                            guard let self = self else { return }
                            self.scrollView.contentOffset = CGPoint(x: 0, y: self.chatBubbles[0].height() + self.spacing + self.chatBubbles[1].height() + self.spacing)
                        }
                        Timer.scheduledTimer(withTimeInterval: delayBetweenMessages, repeats: false) { _ in
                            self?.showChatBubble(at: 4)
                            UIView.animate(withDuration: animationDuration) {
                                guard let self = self else { return }
                                self.scrollView.contentOffset = CGPoint(x: 0, y: self.scrollView.contentSize.height - self.scrollView.bounds.height)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func showChatBubble(at index: Int) {
        let chatBubble = chatBubbles[index]
        UIView.animate(withDuration: FakeChatView.animationDuration) {
            chatBubble.alpha = 1
        }
        let scale = FakeChatView.popAnimationStartScale
        chatBubble.transform = CGAffineTransform(scaleX: scale, y: scale)
        UIView.animate(withDuration: FakeChatView.animationDuration, delay: 0, usingSpringWithDamping: 0.68, initialSpringVelocity: 4, options: .curveEaseInOut, animations: {
            chatBubble.transform = CGAffineTransform(scaleX: 1, y: 1)
        }, completion: nil)
    }
}
