
@objc(LKGradient)
final class Gradient : NSObject {
    let start: UIColor
    let end: UIColor
    
    private override init() { preconditionFailure("Use init(start:end:) instead.") }
    
    @objc init(start: UIColor, end: UIColor) {
        self.start = start
        self.end = end
        super.init()
    }
}

@objc extension UIView {
    
    @objc func setGradient(_ gradient: Gradient) {
        let layer = CAGradientLayer()
        layer.frame = UIScreen.main.bounds
        layer.colors = [ gradient.start.cgColor, gradient.end.cgColor ]
        self.layer.insertSublayer(layer, at: 0)
    }
}

@objc(LKGradients)
final class Gradients : NSObject {
    
    @objc static let defaultLokiBackground = Gradient(start: UIColor(hex: 0x171717), end: UIColor(hex: 0x121212))
    @objc static let transparentToBlack75 = Gradient(start: UIColor(red: 0, green: 0, blue: 0, alpha: 0), end: UIColor(red: 0, green: 0, blue: 0, alpha: 0.75))
}
