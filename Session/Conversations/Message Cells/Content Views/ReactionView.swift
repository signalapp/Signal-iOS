import UIKit

final class ReactionView : UIView {
    private let emoji: String
    private let number: Int
    
    // MARK: Settings
    private static let height: CGFloat = 22
    
    // MARK: Lifecycle
    init(emoji: String, number: Int) {
        self.emoji = emoji
        self.number = number
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
        emojiLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        
        let numberLabel = UILabel()
        numberLabel.text = self.number < 1000 ? "\(number)" : String(format: "%.2f", Float(number) / 1000) + "k"
        numberLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        numberLabel.textColor = Colors.text
        
        let stackView = UIStackView(arrangedSubviews: [ emojiLabel, numberLabel ])
        stackView.axis = .horizontal
        stackView.spacing = Values.verySmallSpacing
        stackView.alignment = .center
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: Values.smallSpacing, bottom: 0, right: Values.smallSpacing)
        stackView.isLayoutMarginsRelativeArrangement = true
        addSubview(stackView)
        stackView.pin(to: self)
        
        set(.height, to: ReactionView.height)
        backgroundColor = Colors.receivedMessageBackground
        layer.cornerRadius = ReactionView.height / 2
    }
}
