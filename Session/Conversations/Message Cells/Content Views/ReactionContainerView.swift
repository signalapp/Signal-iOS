
final class ReactionContainerView : UIView {
    private lazy var containerView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.spacing = Values.smallSpacing
        result.alignment = .center
        return result
    }()
    
    private var showingAllReactions = false
    
    // MARK: Lifecycle
    init() {
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(viewItem:textColor:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(viewItem:textColor:) instead.")
    }
    
    private func setUpViewHierarchy() {
        addSubview(containerView)
        containerView.pin(to: self)
    }
    
    public func update(_ reactions: [(String, (Int, Bool))]) {
        for subview in containerView.arrangedSubviews {
            containerView.removeArrangedSubview(subview)
        }
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Values.smallSpacing
        stackView.alignment = .center
        for reaction in reactions {
            let reactionView = ReactionView(emoji: reaction.0, value: reaction.1)
            stackView.addArrangedSubview(reactionView)
        }
        containerView.addArrangedSubview(stackView)
    }
}


