import UIKit

final class ReactionButton : UIView {
    let emoji: String
    let number: Int
    let showBorder: Bool
    
    // MARK: Settings
    private var height: CGFloat = 22
    private var fontSize: CGFloat = Values.verySmallFontSize
    
    private var spacing: CGFloat = Values.verySmallSpacing
    
    // MARK: Lifecycle
    init(emoji: String, value: Int, showBorder: Bool = false) {
        self.emoji = emoji
        self.number = value
        self.showBorder = showBorder
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
        emojiLabel.text = emoji
        emojiLabel.font = .systemFont(ofSize: fontSize)
        
        let numberLabel = UILabel()
        numberLabel.text = self.number < 1000 ? "\(number)" : String(format: "%.1f", Float(number) / 1000) + "k"
        numberLabel.font = .systemFont(ofSize: fontSize)
        numberLabel.textColor = Colors.text
        
        let stackView = UIStackView(arrangedSubviews: [ emojiLabel, numberLabel ])
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
        
        if showBorder {
            self.addBorder(with: Colors.accent)
        }
    }
}

final class ExpandingReactionButton: UIView {
    private let emojis: [String]
    
    // MARK: Settings
    private let size: CGFloat = 22
    private let margin: CGFloat = 15
    
    // MARK: Lifecycle
    init(emojis: [String]) {
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
            container.layer.borderColor = isDarkMode ? UIColor.black.cgColor : UIColor.white.cgColor
            
            let emojiLabel = UILabel()
            emojiLabel.text = emoji
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
