// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

public struct ReactionViewModel: Hashable {
    let emoji: EmojiWithSkinTones
    let number: Int
    let showBorder: Bool
}

final class ReactionButton: UIView {
    let viewModel: ReactionViewModel
    let showNumber: Bool
    
    // MARK: - Settings
    
    private var height: CGFloat = 22
    private var fontSize: CGFloat = Values.verySmallFontSize
    private var spacing: CGFloat = Values.verySmallSpacing
    
    // MARK: - Lifecycle
    
    init(viewModel: ReactionViewModel, showNumber: Bool = true) {
        self.viewModel = viewModel
        self.showNumber = showNumber
        
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
        let emojiLabel = UILabel()
        emojiLabel.text = viewModel.emoji.rawValue
        emojiLabel.font = .systemFont(ofSize: fontSize)
        
        let stackView = UIStackView(arrangedSubviews: [ emojiLabel ])
        stackView.axis = .horizontal
        stackView.spacing = spacing
        stackView.alignment = .center
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: Values.smallSpacing, bottom: 0, right: Values.smallSpacing)
        stackView.isLayoutMarginsRelativeArrangement = true
        addSubview(stackView)
        stackView.pin(to: self)
        
        set(.height, to: self.height)
        backgroundColor = Colors.receivedMessageBackground
        layer.cornerRadius = self.height / 2
        
        if viewModel.showBorder {
            self.addBorder(with: Colors.accent)
        }
        
        if showNumber || viewModel.number > 1 {
            let numberLabel = UILabel()
            numberLabel.text = viewModel.number < 1000 ? "\(viewModel.number)" : String(format: "%.1f", Float(viewModel.number) / 1000) + "k"
            numberLabel.font = .systemFont(ofSize: fontSize)
            numberLabel.textColor = Colors.text
            stackView.addArrangedSubview(numberLabel)
        }
    }
}

final class ExpandingReactionButton: UIView {
    private let emojis: [EmojiWithSkinTones]
    
    // MARK: - Settings
    
    private let size: CGFloat = 22
    private let margin: CGFloat = 15
    
    // MARK: - Lifecycle
    
    init(emojis: [EmojiWithSkinTones]) {
        self.emojis = emojis
        
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
        var rightMargin: CGFloat = 0
        
        for emoji in self.emojis.reversed() {
            let container = UIView()
            container.set(.width, to: size)
            container.set(.height, to: size)
            container.backgroundColor = Colors.receivedMessageBackground
            container.layer.cornerRadius = size / 2
            container.layer.borderWidth = 1
            // FIXME: This is going to have issues when swapping between light/dark mode
            container.layer.borderColor = (isDarkMode ? UIColor.black.cgColor : UIColor.white.cgColor)
            
            let emojiLabel = UILabel()
            emojiLabel.text = emoji.rawValue
            emojiLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
            
            container.addSubview(emojiLabel)
            emojiLabel.center(in: container)
            
            addSubview(container)
            container.pin([ UIView.VerticalEdge.top, UIView.VerticalEdge.bottom ], to: self)
            container.pin(.right, to: .right, of: self, withInset: -rightMargin)
            rightMargin += margin
        }
        
        set(.width, to: rightMargin - margin + size)
    }
}
