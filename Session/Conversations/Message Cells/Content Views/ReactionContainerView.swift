// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

final class ReactionContainerView: UIView {
    var showingAllReactions = false
    private var showNumbers = true
    private var maxEmojisPerLine = isIPhone6OrSmaller ? 5 : 6
    
    var reactions: [ReactionViewModel] = []
    var reactionViews: [ReactionButton] = []
    
    // MARK: - UI
    
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
    
    var expandButton: ExpandingReactionButton?
    
    var collapseButton: UIStackView = {
        let arrow = UIImageView(image: UIImage(named: "ic_chevron_up")?.resizedImage(to: CGSize(width: 15, height: 13))?.withRenderingMode(.alwaysTemplate))
        arrow.tintColor = Colors.text
        
        let textLabel = UILabel()
        textLabel.text = "EMOJI_REACTS_SHOW_LESS".localized()
        textLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        textLabel.textColor = Colors.text
        
        let result = UIStackView(arrangedSubviews: [ UIView.hStretchingSpacer(), arrow, textLabel, UIView.hStretchingSpacer() ])
        result.spacing = Values.verySmallSpacing
        result.alignment = .center
        return result
    }()
    
    // MARK: - Lifecycle
    
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
    
    public func update(_ reactions: [ReactionViewModel], showNumbers: Bool) {
        self.reactions = reactions
        self.showNumbers = showNumbers
        
        prepareForUpdate()
        
        if showingAllReactions {
            updateAllReactions()
        }
        else {
            updateCollapsedReactions(reactions)
        }
    }
    
    private func updateCollapsedReactions(_ reactions: [ReactionViewModel]) {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Values.smallSpacing
        stackView.alignment = .center
        
        var displayedReactions: [ReactionViewModel]
        var expandButtonReactions: [EmojiWithSkinTones]
        
        if reactions.count > maxEmojisPerLine {
            displayedReactions = Array(reactions[0...(maxEmojisPerLine - 3)])
            expandButtonReactions = Array(reactions[(maxEmojisPerLine - 2)...maxEmojisPerLine])
                .map { $0.emoji }
        }
        else {
            displayedReactions = reactions
            expandButtonReactions = []
        }
        
        for reaction in displayedReactions {
            let reactionView = ReactionButton(viewModel: reaction, showNumber: showNumbers)
            stackView.addArrangedSubview(reactionView)
            reactionViews.append(reactionView)
        }
        
        if expandButtonReactions.count > 0 {
            let expandButton: ExpandingReactionButton = ExpandingReactionButton(emojis: expandButtonReactions)
            stackView.addArrangedSubview(expandButton)
            
            self.expandButton = expandButton
        }
        else {
            expandButton = nil
        }
        
        reactionContainerView.addArrangedSubview(stackView)
    }
    
    private func updateAllReactions() {
        var reactions = self.reactions
        var numberOfLines = 0
        
        while reactions.count > 0 {
            var line: [ReactionViewModel] = []
            
            while reactions.count > 0 && line.count < maxEmojisPerLine {
                line.append(reactions.removeFirst())
            }
            
            updateCollapsedReactions(line)
            numberOfLines += 1
        }
        
        if numberOfLines > 1 {
            mainStackView.addArrangedSubview(collapseButton)
        }
        else {
            showingAllReactions = false
        }
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
        update(reactions, showNumbers: showNumbers)
    }
    
    public func showLessEmojis() {
        guard showingAllReactions else { return }
        
        showingAllReactions = false
        update(reactions, showNumbers: showNumbers)
    }
}


