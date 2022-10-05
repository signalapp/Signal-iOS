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
    
    public static var height: CGFloat = 22
    private var fontSize: CGFloat = Values.verySmallFontSize
    private var spacing: CGFloat = Values.verySmallSpacing
    
    // MARK: - UI
    
    private lazy var emojiLabel: UILabel = {
        let result: UILabel = UILabel()
        result.setContentHuggingPriority(.required, for: .horizontal)
        result.setContentCompressionResistancePriority(.required, for: .horizontal)
        result.font = .systemFont(ofSize: fontSize)
        
        return result
    }()
    
    private lazy var numberLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .systemFont(ofSize: fontSize)
        result.themeTextColor = .textPrimary
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    init(viewModel: ReactionViewModel, showNumber: Bool = true) {
        self.viewModel = viewModel
        self.showNumber = showNumber
        
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy()
        update(with: viewModel, showNumber: showNumber)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(viewItem:textColor:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(viewItem:textColor:) instead.")
    }
    
    private func setUpViewHierarchy() {
        emojiLabel.text = viewModel.emoji.rawValue
        
        let stackView: UIStackView = UIStackView(arrangedSubviews: [ emojiLabel, numberLabel ])
        stackView.axis = .horizontal
        stackView.spacing = spacing
        stackView.alignment = .center
        addSubview(stackView)
        stackView.pin(.top, to: .top, of: self)
        stackView.pin(.leading, to: .leading, of: self, withInset: Values.smallSpacing)
        stackView.pin(.trailing, to: .trailing, of: self, withInset: -Values.smallSpacing)
        stackView.pin(.bottom, to: .bottom, of: self)
        
        themeBorderColor = (viewModel.showBorder ? .primary : .clear)
        themeBackgroundColor = .messageBubble_incomingBackground
        layer.cornerRadius = (ReactionButton.height / 2)
        layer.borderWidth = 1   // Intentionally 1pt (instead of 'Values.separatorThickness')
        set(.height, to: ReactionButton.height)
        
        numberLabel.isHidden = (!showNumber && viewModel.number <= 1)
    }
    
    func update(with viewModel: ReactionViewModel, showNumber: Bool) {
        _ = updating(with: viewModel, showNumber: showNumber)
    }
    
    func updating(with viewModel: ReactionViewModel, showNumber: Bool) -> ReactionButton {
        emojiLabel.text = viewModel.emoji.rawValue
        numberLabel.text = (viewModel.number < 1000 ?
            "\(viewModel.number)" :
            String(format: "%.1f", Float(viewModel.number) / 1000) + "k"
        )
        numberLabel.isHidden = (!showNumber && viewModel.number <= 1)
        
        UIView.performWithoutAnimation {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        
        return self
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
            let container: UIView = UIView()
            container.set(.width, to: size)
            container.set(.height, to: size)
            container.themeBorderColor = .backgroundPrimary
            container.themeBackgroundColor = .messageBubble_incomingBackground
            container.layer.cornerRadius = size / 2
            container.layer.borderWidth = 1 // Intentionally 1pt (instead of 'Values.separatorThickness')
            
            let emojiLabel: UILabel = UILabel()
            emojiLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
            emojiLabel.text = emoji.rawValue
            
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
