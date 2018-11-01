//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@objc class TypingIndicatorView: UIStackView {
    // This represents the spacing between the dots
    // _at their max size_.
    private let kDotMaxHSpacing: CGFloat = 3

    @objc
    public static let kMinRadiusPt: CGFloat = 6
    @objc
    public static let kMaxRadiusPt: CGFloat = 8

    private let dot1 = DotView(dotType: .dotType1)
    private let dot2 = DotView(dotType: .dotType2)
    private let dot3 = DotView(dotType: .dotType3)

    override public var isHidden: Bool {
        didSet {
            Logger.verbose("\(oldValue) -> \(isHidden)")
        }
    }

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
        addArrangedSubview(dot1)
        addArrangedSubview(dot2)
        addArrangedSubview(dot3)

        self.axis = .horizontal
        self.spacing = kDotMaxHSpacing
        self.alignment = .center
    }

    @objc
    public func startAnimation() {
    }

    @objc
    public func stopAnimation() {
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

            self.layer.addSublayer(shapeLayer)

            updateLayer()
//            self.text = text
//
//            setupSubviews()
        }

        private func updateLayer() {
            shapeLayer.fillColor = UIColor.ows_signalBlue.cgColor

            let margin = (TypingIndicatorView.kMaxRadiusPt - TypingIndicatorView.kMinRadiusPt) * 0.5
            let bezierPath = UIBezierPath(ovalIn: CGRect(x: margin, y: margin, width: TypingIndicatorView.kMinRadiusPt, height: TypingIndicatorView.kMinRadiusPt))
            shapeLayer.path = bezierPath.cgPath

        }
    }
}
