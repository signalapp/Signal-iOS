
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
            subview.removeFromSuperview()
        }
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Values.smallSpacing
        stackView.alignment = .center
        
        var displayedReactions: [(String, (Int, Bool))]
        var expandButtonReactions: [String]
        
        if reactions.count >= 6 {
            displayedReactions = Array(reactions[0...2])
            expandButtonReactions = Array(reactions[3...5]).map{ $0.0 }
        } else {
            displayedReactions = reactions
            expandButtonReactions = []
        }
        
        for reaction in displayedReactions {
            let reactionView = ReactionView(emoji: reaction.0, value: reaction.1)
            stackView.addArrangedSubview(reactionView)
        }
        if expandButtonReactions.count > 0 {
            let expandButton = ExpandingReactionButton(emojis: expandButtonReactions)
            stackView.addArrangedSubview(expandButton)
        }
        containerView.addArrangedSubview(stackView)
    }
}


