
extension UIView {

    struct CircularGlowConfiguration {
        let size: CGFloat
        let color: UIColor
        let isAnimated: Bool
        let animationDuration: TimeInterval
        let offset: CGSize
        let opacity: Float
        let radius: CGFloat

        init(size: CGFloat, color: UIColor, isAnimated: Bool = false, animationDuration: TimeInterval = 0.25, offset: CGSize = CGSize(width: 0, height: 0.8), opacity: Float = isLightMode ? 0.4 : 1, radius: CGFloat) {
            self.size = size
            self.color = color
            self.isAnimated = isAnimated
            self.animationDuration = animationDuration
            self.offset = offset
            self.opacity = opacity
            self.radius = radius
        }
    }

    func setCircularGlow(with configuration: CircularGlowConfiguration) {
        let newSize = configuration.size
        let newPath = UIBezierPath(ovalIn: CGRect(origin: CGPoint.zero, size: CGSize(width: newSize, height: newSize))).cgPath
        if configuration.isAnimated {
            let pathAnimation = CABasicAnimation(keyPath: "shadowPath")
            pathAnimation.fromValue = layer.shadowPath
            pathAnimation.toValue = newPath
            pathAnimation.duration = configuration.animationDuration
            layer.add(pathAnimation, forKey: pathAnimation.keyPath)
        }
        layer.shadowPath = newPath
        let newColor = configuration.color.cgColor
        if configuration.isAnimated {
            let colorAnimation = CABasicAnimation(keyPath: "shadowColor")
            colorAnimation.fromValue = layer.shadowColor
            colorAnimation.toValue = newColor
            colorAnimation.duration = configuration.animationDuration
            layer.add(colorAnimation, forKey: colorAnimation.keyPath)
        }
        layer.shadowColor = newColor
        layer.shadowOffset = configuration.offset
        layer.shadowOpacity = configuration.opacity
        layer.shadowRadius = configuration.radius
    }
}
