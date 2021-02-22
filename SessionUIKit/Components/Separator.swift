import UIKit

public final class Separator : UIView {
    private let title: String
    
    // MARK: Components
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text.withAlphaComponent(Values.mediumOpacity)
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.textAlignment = .center
        return result
    }()
    
    private lazy var lineLayer: CAShapeLayer = {
        let result = CAShapeLayer()
        result.lineWidth = Values.separatorThickness
        result.strokeColor = Colors.separator.cgColor
        result.fillColor = UIColor.clear.cgColor
        return result
    }()
    
    // MARK: Settings
    private static let height: CGFloat = 24
    
    // MARK: Initialization
    public init(title: String) {
        self.title = title
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    public override init(frame: CGRect) {
        preconditionFailure("Use init(title:) instead.")
    }
    
    public required init?(coder: NSCoder) {
        preconditionFailure("Use init(title:) instead.")
    }
    
    private func setUpViewHierarchy() {
        titleLabel.text = title
        addSubview(titleLabel)
        titleLabel.center(.horizontal, in: self)
        titleLabel.center(.vertical, in: self)
        layer.insertSublayer(lineLayer, at: 0)
        set(.height, to: Separator.height)
    }
    
    // MARK: Updating
    public override func layoutSubviews() {
        super.layoutSubviews()
        updateLineLayer()
    }
    
    private func updateLineLayer() {
        let w = bounds.width
        let h = bounds.height
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: h / 2))
        let titleLabelFrame = titleLabel.frame.insetBy(dx: -10, dy: -6)
        path.addLine(to: CGPoint(x: titleLabelFrame.origin.x, y: h / 2))
        let oval = UIBezierPath(roundedRect: titleLabelFrame, cornerRadius: Separator.height / 2)
        path.append(oval)
        path.move(to: CGPoint(x: titleLabelFrame.origin.x + titleLabelFrame.width, y: h / 2))
        path.addLine(to: CGPoint(x: w, y: h / 2))
        path.close()
        lineLayer.path = path.cgPath
    }
}
