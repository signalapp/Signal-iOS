
final class InfoBanner : UIView {
    private let message: String
    private let snBackgroundColor: UIColor
    
    init(message: String, backgroundColor: UIColor) {
        self.message = message
        self.snBackgroundColor = backgroundColor
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(message:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(coder:) instead.")
    }
    
    private func setUpViewHierarchy() {
        backgroundColor = snBackgroundColor
        let label = UILabel()
        label.text = message
        label.font = .boldSystemFont(ofSize: Values.smallFontSize)
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        addSubview(label)
        label.pin(to: self, withInset: Values.mediumSpacing)
    }
}
