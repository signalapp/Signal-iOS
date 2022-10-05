// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SignalUtilitiesKit

final class ReactionContainerView: UIView {
    var showingAllReactions = false
    private var showNumbers = true
    private var maxEmojisPerLine = UIDevice.current.isIPad ? 10 : (isIPhone6OrSmaller ? 5 : 6)
    private var oldSize: CGSize = .zero
    
    var reactions: [ReactionViewModel] = []
    var reactionViews: [ReactionButton] = []
    
    // MARK: - UI
    
    private lazy var mainStackView: UIStackView = {
        let result: UIStackView = UIStackView(arrangedSubviews: [ reactionContainerView, collapseButton ])
        result.axis = .vertical
        result.spacing = Values.smallSpacing
        result.alignment = .center
        
        return result
    }()
    
    private lazy var reactionContainerView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.axis = .vertical
        result.spacing = Values.smallSpacing
        result.alignment = .leading
        
        return result
    }()
    
    var expandButton: ExpandingReactionButton?
    
    var collapseButton: UIStackView = {
        let arrow = UIImageView(
            image: UIImage(named: "ic_chevron_up")?
                .resizedImage(to: CGSize(width: 15, height: 13))?
                .withRenderingMode(.alwaysTemplate)
        )
        arrow.themeTintColor = .textPrimary
        
        let textLabel: UILabel = UILabel()
        textLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        textLabel.text = "EMOJI_REACTS_SHOW_LESS".localized()
        textLabel.themeTextColor = .textPrimary
        
        let leftSpacer: UIView = UIView.hStretchingSpacer()
        let rightSpacer: UIView = UIView.hStretchingSpacer()
        let result: UIStackView = UIStackView(arrangedSubviews: [
            leftSpacer,
            arrow,
            textLabel,
            rightSpacer
        ])
        result.isLayoutMarginsRelativeArrangement = true
        result.spacing = Values.verySmallSpacing
        result.alignment = .center
        result.isHidden = true
        rightSpacer.set(.width, to: .width, of: leftSpacer)
        
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
        collapseButton.set(.width, to: .width, of: mainStackView)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Note: We update the 'collapseButton.layoutMargins' to try to make the "show less"
        // button appear horizontally centered (if we don't do this it gets offset to one side)
        guard frame != CGRect.zero, frame.size != oldSize else { return }
        
        collapseButton.layoutMargins = UIEdgeInsets(
            top: 0,
            leading: -frame.minX,
            bottom: 0,
            trailing: -((superview?.frame.width ?? 0) - frame.maxX)
        )
        oldSize = frame.size
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
            collapseButton.isHidden = false
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
        
        collapseButton.isHidden = true
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


