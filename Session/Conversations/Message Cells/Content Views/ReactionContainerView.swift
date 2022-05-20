
final class ReactionContainerView : UIView {
    private lazy var mainStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ reactionContainerView ])
        result.axis = .vertical
        result.spacing = Values.smallSpacing
        result.alignment = .center
        return result
    }()
    
    private lazy var reactionContainerView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.spacing = Values.smallSpacing
        result.alignment = .leading
        return result
    }()
    
    private var showingAllReactions = false
    
    var reactions: [(String, (Int, Bool))] = []
    var reactionViews: [ReactionView] = []
    var expandButton: ExpandingReactionButton?
    var collapseButton: UIStackView = {
        let arrow = UIImageView(image: UIImage(named: "ic_chevron_up")?.resizedImage(to: CGSize(width: 15, height: 13))?.withRenderingMode(.alwaysTemplate))
        arrow.tintColor = Colors.text
        
        let textLabel = UILabel()
        textLabel.text = "Show less"
        textLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        textLabel.textColor = Colors.text
        
        let result = UIStackView(arrangedSubviews: [ UIView.hStretchingSpacer(), arrow, textLabel, UIView.hStretchingSpacer() ])
        result.spacing = Values.verySmallSpacing
        result.alignment = .center
        return result
    }()
    
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
        addSubview(mainStackView)
        mainStackView.pin(to: self)
    }
    
    public func update(_ reactions: [(String, (Int, Bool))]) {
        self.reactions = reactions
        prepareForUpdate()
        if showingAllReactions {
            updateAllReactions()
        } else {
            updateCollapsedReactions(reactions)
        }
    }
    
    private func updateCollapsedReactions(_ reactions: [(String, (Int, Bool))]) {
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
            reactionViews.append(reactionView)
        }
        if expandButtonReactions.count > 0 {
            expandButton = ExpandingReactionButton(emojis: expandButtonReactions)
            stackView.addArrangedSubview(expandButton!)
        } else {
            expandButton = nil
        }
        reactionContainerView.addArrangedSubview(stackView)
    }
    
    private func updateAllReactions() {
        var reactions = self.reactions
        while reactions.count > 0 {
            var line: [(String, (Int, Bool))] = []
            while reactions.count > 0 && line.count < 5 {
                line.append(reactions.removeFirst())
            }
            updateCollapsedReactions(line)
        }
        mainStackView.addArrangedSubview(collapseButton)
    }
    
    private func prepareForUpdate() {
        for subview in reactionContainerView.arrangedSubviews {
            reactionContainerView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        mainStackView.removeArrangedSubview(collapseButton)
        collapseButton.removeFromSuperview()
        reactionViews = []
    }
    
    public func showAllEmojis() {
        guard !showingAllReactions else { return }
        showingAllReactions = true
        update(reactions)
    }
    
    public func showLessEmojis() {
        guard showingAllReactions else { return }
        showingAllReactions = false
        update(reactions)
    }
}


