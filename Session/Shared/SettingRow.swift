
final class SettingRow : UIView {
    private let autoSize: Bool

    lazy var contentView: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.buttonBackground
        result.layer.cornerRadius = 8
        result.layer.masksToBounds = true
        return result
    }()

    init(autoSize: Bool) {
        self.autoSize = autoSize
        super.init(frame: CGRect.zero)
        setUpUI()
    }

    override init(frame: CGRect) {
        autoSize = false
        super.init(frame: frame)
        setUpUI()
    }

    required init?(coder: NSCoder) {
        autoSize = false
        super.init(coder: coder)
        setUpUI()
    }

    private func setUpUI() {
        // Height
        if !autoSize {
            let height = Values.defaultSettingRowHeight
            set(.height, to: height)
        }
        // Shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize.zero
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 4
        // Content view
        addSubview(contentView)
        contentView.pin(to: self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 8).cgPath
    }
}
