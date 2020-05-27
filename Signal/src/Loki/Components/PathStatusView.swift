
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
        let glowConfiguration = UIView.CircularGlowConfiguration(size: size, color: Colors.accent, isAnimated: false, radius: isLightMode ? 6 : 8)
        setCircularGlow(with: glowConfiguration)
        layer.masksToBounds = false
    }
}
