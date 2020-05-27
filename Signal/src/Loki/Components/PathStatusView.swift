
final class PathStatusView : UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        backgroundColor = Colors.accent
        let size = Values.pathStatusViewSize
        layer.cornerRadius = size / 2
        setGlow(to: size, with: Colors.accent, animated: false)
        layer.masksToBounds = false
    }
    
    func setGlow(to size: CGFloat, with color: UIColor, animated isAnimated: Bool) {
        let newPath = UIBezierPath(ovalIn: CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: size, height: size))).cgPath
        if isAnimated {
            let pathAnimation = CABasicAnimation(keyPath: "shadowPath")
            pathAnimation.fromValue = layer.shadowPath
            pathAnimation.toValue = newPath
            pathAnimation.duration = 0.25
            layer.add(pathAnimation, forKey: pathAnimation.keyPath)
        }
        layer.shadowPath = newPath
        let newColor = color.cgColor
        if isAnimated {
            let colorAnimation = CABasicAnimation(keyPath: "shadowColor")
            colorAnimation.fromValue = layer.shadowColor
            colorAnimation.toValue = newColor
            colorAnimation.duration = 0.25
            layer.add(colorAnimation, forKey: colorAnimation.keyPath)
        }
        layer.shadowColor = newColor
        layer.shadowOffset = CGSize(width: 0, height: 0.8)
        layer.shadowOpacity = isLightMode ? 0.4 : 1
        layer.shadowRadius = isLightMode ? 6 : 8
    }
}
