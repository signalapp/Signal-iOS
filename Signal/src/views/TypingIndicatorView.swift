//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

@objc class TypingIndicatorView: UIStackView {
    // This represents the spacing between the dots
    // _at their max size_.
    private static let kDotMaxHSpacing: CGFloat = 3

    @objc
    public static let kMinRadiusPt: CGFloat = 6
    @objc
    public static let kMaxRadiusPt: CGFloat = 8

    private let dot1 = DotView(dotType: .dotType1)
    private let dot2 = DotView(dotType: .dotType2)
    private let dot3 = DotView(dotType: .dotType3)

    @available(*, unavailable, message:"use other constructor instead.")
    required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @available(*, unavailable, message:"use other constructor instead.")
    override init(frame: CGRect) {
        notImplemented()
    }

    @objc
    public init() {
        super.init(frame: .zero)

        // init(arrangedSubviews:...) is not a designated initializer.
        for dot in dots() {
            addArrangedSubview(dot)
        }

        self.axis = .horizontal
        self.spacing = Self.kDotMaxHSpacing
        self.alignment = .center

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Notifications

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        // CoreAnimation animations are stopped in the background, so ensure
        // animations are restored if necessary.
        if isAnimating {
            startAnimation()
        }
    }

    // MARK: -

    @objc
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        Self.measureSize
    }

    @objc
    public static var measureSize: CGSize {
        return CGSize(width: TypingIndicatorView.kMaxRadiusPt * 3 + kDotMaxHSpacing * 2, height: TypingIndicatorView.kMaxRadiusPt)
    }

    private func dots() -> [DotView] {
        return [dot1, dot2, dot3]
    }

    private var isAnimating = false

    @objc
    public func startAnimation() {
        isAnimating = true

        for dot in dots() {
            dot.startAnimation()
        }
    }

    @objc
    public func stopAnimation() {
        isAnimating = false

        for dot in dots() {
            dot.stopAnimation()
        }
    }

    private enum DotType {
        case dotType1
        case dotType2
        case dotType3
    }

    private class DotView: UIView {
        private let dotType: DotType

        private let shapeLayer = CAShapeLayer()

        @available(*, unavailable, message:"use other constructor instead.")
        required init?(coder aDecoder: NSCoder) {
            notImplemented()
        }

        @available(*, unavailable, message:"use other constructor instead.")
        override init(frame: CGRect) {
            notImplemented()
        }

        init(dotType: DotType) {
            self.dotType = dotType

            super.init(frame: .zero)

            autoSetDimension(.width, toSize: kMaxRadiusPt)
            autoSetDimension(.height, toSize: kMaxRadiusPt)

            layer.addSublayer(shapeLayer)
        }

        fileprivate func startAnimation() {
            stopAnimation()

            let baseColor = (Theme.isDarkThemeEnabled
            ? UIColor(rgbHex: 0xBBBDBE)
            : UIColor(rgbHex: 0x636467))
            let timeIncrement: CFTimeInterval = 0.15
            var colorValues = [CGColor]()
            var pathValues = [CGPath]()
            var keyTimes = [CFTimeInterval]()
            var animationDuration: CFTimeInterval = 0

            let addDotKeyFrame = { (keyFrameTime: CFTimeInterval, progress: CGFloat) in
                let dotColor = baseColor.withAlphaComponent(CGFloatLerp(0.4, 1.0, CGFloatClamp01(progress)))
                colorValues.append(dotColor.cgColor)
                let radius = CGFloatLerp(TypingIndicatorView.kMinRadiusPt, TypingIndicatorView.kMaxRadiusPt, CGFloatClamp01(progress))
                let margin = (TypingIndicatorView.kMaxRadiusPt - radius) * 0.5
                let bezierPath = UIBezierPath(ovalIn: CGRect(x: margin, y: margin, width: radius, height: radius))
                pathValues.append(bezierPath.cgPath)

                keyTimes.append(keyFrameTime)
                animationDuration = max(animationDuration, keyFrameTime)
            }

            // All animations in the group apparently need to have the same number
            // of keyframes, and use the same timing.
            switch dotType {
            case .dotType1:
                addDotKeyFrame(0 * timeIncrement, 0.0)
                addDotKeyFrame(1 * timeIncrement, 0.5)
                addDotKeyFrame(2 * timeIncrement, 1.0)
                addDotKeyFrame(3 * timeIncrement, 0.5)
                addDotKeyFrame(4 * timeIncrement, 0.0)
                addDotKeyFrame(5 * timeIncrement, 0.0)
                addDotKeyFrame(6 * timeIncrement, 0.0)
                addDotKeyFrame(10 * timeIncrement, 0.0)
                break
            case .dotType2:
                addDotKeyFrame(0 * timeIncrement, 0.0)
                addDotKeyFrame(1 * timeIncrement, 0.0)
                addDotKeyFrame(2 * timeIncrement, 0.5)
                addDotKeyFrame(3 * timeIncrement, 1.0)
                addDotKeyFrame(4 * timeIncrement, 0.5)
                addDotKeyFrame(5 * timeIncrement, 0.0)
                addDotKeyFrame(6 * timeIncrement, 0.0)
                addDotKeyFrame(10 * timeIncrement, 0.0)
                break
            case .dotType3:
                addDotKeyFrame(0 * timeIncrement, 0.0)
                addDotKeyFrame(1 * timeIncrement, 0.0)
                addDotKeyFrame(2 * timeIncrement, 0.0)
                addDotKeyFrame(3 * timeIncrement, 0.5)
                addDotKeyFrame(4 * timeIncrement, 1.0)
                addDotKeyFrame(5 * timeIncrement, 0.5)
                addDotKeyFrame(6 * timeIncrement, 0.0)
                addDotKeyFrame(10 * timeIncrement, 0.0)
                break
            }

            let makeAnimation: (String, [Any]) -> CAKeyframeAnimation = { (keyPath, values) in
                let animation = CAKeyframeAnimation()
                animation.keyPath = keyPath
                animation.values = values
                animation.duration = animationDuration
                return animation
            }

            let groupAnimation = CAAnimationGroup()
            groupAnimation.animations = [
                makeAnimation("fillColor", colorValues),
                makeAnimation("path", pathValues)
            ]
            groupAnimation.duration = animationDuration
            groupAnimation.repeatCount = MAXFLOAT

            shapeLayer.add(groupAnimation, forKey: UUID().uuidString)
        }

        fileprivate func stopAnimation() {
            shapeLayer.removeAllAnimations()
        }
    }
}
