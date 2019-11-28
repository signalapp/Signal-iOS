
@objc(LKGradient)
public final class Gradient : NSObject {
    public let start: UIColor
    public let end: UIColor
    
    private override init() { preconditionFailure("Use init(start:end:) instead.") }
    
    @objc public init(start: UIColor, end: UIColor) {
        self.start = start
        self.end = end
        super.init()
    }
}

@objc public extension UIView {
    
    @objc func setGradient(_ gradient: Gradient) { // Doesn't need to be declared public because the extension is already public
        let layer = CAGradientLayer()
        layer.frame = UIScreen.main.bounds
        layer.colors = [ gradient.start.cgColor, gradient.end.cgColor ]
        layer.startPoint = CGPoint(x: 0.5, y: 0)
        layer.endPoint = CGPoint(x: 0.5, y: 1)
        let index = UInt32((self.layer.sublayers ?? []).count)
        self.layer.insertSublayer(layer, at: index)
    }
}

@objc(LKGradients)
public final class Gradients : NSObject {
    
    @objc public static let defaultLokiBackground = Gradient(start: UIColor(hex: 0x171717), end: UIColor(hex:0x121212))
}
