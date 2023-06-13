//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public protocol ColorPickerBarViewDelegate: AnyObject {
    func colorPickerBarView(_ pickerView: ColorPickerBarView, didSelectColor color: ColorPickerBarColor)
}

// MARK: -

// We represent picker colors using this (color, phase)
// tuple so that we can consistently restore palette view state.
public class ColorPickerBarColor {
    public let color: UIColor

    // Colors are chosen from a spectrum of colors.
    // This unit value represents the location of the
    // color within that spectrum.
    let palettePhase: CGFloat

    var cgColor: CGColor {
        return color.cgColor
    }

    required init(color: UIColor, palettePhase: CGFloat) {
        self.color = color
        self.palettePhase = palettePhase
    }

    class func defaultColor() -> ColorPickerBarColor {
        return ColorPickerBarColor(color: UIColor(rgbHex: 0xff0000), palettePhase: 1/9)
    }

    class var white: ColorPickerBarColor {
        ColorPickerBarColor(color: .white, palettePhase: 1)
    }

    class var black: ColorPickerBarColor {
        ColorPickerBarColor(color: .black, palettePhase: 0)
    }

    static var gradientUIColors: [UIColor] {
        return [
            UIColor(rgbHex: 0x000000),
            UIColor(rgbHex: 0xff5500),
            UIColor(rgbHex: 0xffff00),
            UIColor(rgbHex: 0x00ff00),
            UIColor(rgbHex: 0x00ffff),
            UIColor(rgbHex: 0x0000ff),
            UIColor(rgbHex: 0xff00ff),
            UIColor(rgbHex: 0xff0000),
            UIColor(rgbHex: 0xffffff)
        ]
    }

    static var gradientCGColors: [CGColor] {
        return gradientUIColors.map { $0.cgColor }
    }

    static func == (left: ColorPickerBarColor, right: ColorPickerBarColor) -> Bool {
        return left.palettePhase.fuzzyEquals(right.palettePhase)
    }
}

// MARK: -

private class ColorPreviewView: OWSLayerView {

    private static let innerRadius: CGFloat = 32
    // The distance from the "inner circle" to the "teardrop".
    private static let circleMargin: CGFloat = 3
    private static let teardropTipRadius: CGFloat = 4
    private static let teardropPointiness: CGFloat = 12

    private let teardropColor = UIColor.white
    var selectedColor = UIColor.white {
        didSet {
            circleLayer.fillColor = selectedColor.cgColor
        }
    }

    private let circleLayer: CAShapeLayer
    private let teardropLayer: CAShapeLayer

    override init() {
        let circleLayer = CAShapeLayer()
        let teardropLayer = CAShapeLayer()
        self.circleLayer = circleLayer
        self.teardropLayer = teardropLayer

        super.init()

        circleLayer.strokeColor = nil
        teardropLayer.strokeColor = nil
        // Layer order matters.
        layer.addSublayer(teardropLayer)
        layer.addSublayer(circleLayer)

        teardropLayer.fillColor = teardropColor.cgColor

        layoutCallback = { (view) in
            ColorPreviewView.updateLayers(view: view,
                                          circleLayer: circleLayer,
                                          teardropLayer: teardropLayer)
        }

        // The bounding rect of the teardrop + shadow is non-trivial, so
        // we use a generous size that reserves plenty of space.
        //
        // The size doesn't matter since this view is
        // mostly transparent and isn't hot.
        autoSetDimensions(to: CGSize(square: ColorPreviewView.innerRadius * 4))
    }

    @available(*, unavailable, message: "use other init() instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func updateLayers(view: UIView,
                             circleLayer: CAShapeLayer,
                             teardropLayer: CAShapeLayer) {
        let bounds = view.bounds
        let outerRadius = innerRadius + circleMargin
        let bottomEdge = CGPoint(x: bounds.center.x, y: bounds.maxY)
        let teardropTipCenter = bottomEdge.minus(CGPoint(x: 0, y: teardropTipRadius))
        let circleCenter = teardropTipCenter.minus(CGPoint(x: 0, y: teardropPointiness + innerRadius))

        // The "teardrop" shape is bounded by 2 circles, joined by their tangents.
        //
        // UIBezierPath can be used to draw this using 2 arcs, if we
        // have the angle of the tangents.
        //
        // Finding the tangent between two circles of known distance + radius
        // is pretty straightforward.  We solve for the right triangle that
        // defines the tangents and atan() that triangle to get the angle.
        //
        // 1. Find the length of the hypotenuse.
        let circleCenterDistance = teardropTipCenter.minus(circleCenter).length
        // 2. Find the length of the first side.
        let radiusDiff = outerRadius - teardropTipRadius
        // 3. Find the length of the second side.
        let tangentLength = (circleCenterDistance.square - radiusDiff.square).squareRoot()
        let angle = atan2(tangentLength, radiusDiff)
        let startAngle = angle + .halfPi
        let endAngle = -angle + .halfPi

        let teardropPath = UIBezierPath()
        teardropPath.addArc(withCenter: circleCenter,
                            radius: outerRadius,
                            startAngle: startAngle,
                            endAngle: endAngle,
                            clockwise: true)
        teardropPath.addArc(withCenter: teardropTipCenter,
                            radius: teardropTipRadius,
                            startAngle: endAngle,
                            endAngle: startAngle,
                            clockwise: true)

        teardropLayer.path = teardropPath.cgPath
        teardropLayer.frame = bounds

        let innerCircleSize = CGSize(square: innerRadius * 2)
        let circleFrame = CGRect(origin: circleCenter.minus(innerCircleSize.asPoint.times(0.5)),
                                 size: innerCircleSize)
        circleLayer.path = UIBezierPath(ovalIn: circleFrame).cgPath
        circleLayer.frame = bounds
    }
}

// MARK: -

public class ColorPickerBarView: UIView {

    public weak var delegate: ColorPickerBarViewDelegate?

    public var color: UIColor { selectedValue.color }
    var selectedValue: ColorPickerBarColor {
        didSet {
            updateState()
        }
    }

    required init(currentColor: ColorPickerBarColor? = nil) {
        selectedValue = currentColor ?? ColorPickerBarColor.defaultColor()
        super.init(frame: .zero)
        createContents()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Views

    private let imageView = UIImageView()
    private static let selectionSize: CGFloat = 22
    private static let colorBarWidth: CGFloat = 12
    private var selectionView: UIView = {
        let selectionView = CircleView(diameter: selectionSize)
        // Use separate view to create border effect because
        // setting up border on the same view creates a weird glow around the border.
        let borderView = CircleView(diameter: selectionSize + 1)
        borderView.layer.borderColor = UIColor.white.cgColor
        borderView.layer.borderWidth = 2
        selectionView.addSubview(borderView)
        borderView.autoHCenterInSuperview()
        borderView.autoVCenterInSuperview()
        return selectionView
    }()
    // imageWrapper is used to host the "selection view".
    private let imageWrapper = OWSLayerView()
    private var selectionConstraint: NSLayoutConstraint?
    private let previewView = ColorPreviewView()

    private func createContents() {
        isOpaque = false
        layoutMargins.leading = 0
        layoutMargins.trailing = 0

        let borderWidth: CGFloat = 2
        let image = ColorPickerBarView.buildPaletteGradientImage()
        imageView.image = image
        let imageRadius = image.size.height * 0.5
        imageView.layer.cornerRadius = imageRadius
        imageView.clipsToBounds = true
        addSubview(imageView)
        imageView.autoSetDimension(.height, toSize: ColorPickerBarView.colorBarWidth)
        imageView.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(margin: borderWidth))

        // Create "outer border" that doesn't obscure any colors in the strip.
        let imageViewBorder = PillView()
        imageViewBorder.layer.borderWidth = borderWidth
        imageViewBorder.layer.borderColor = UIColor.white.cgColor
        addSubview(imageViewBorder)
        imageViewBorder.autoPin(toEdgesOf: imageView, with: UIEdgeInsets(margin: -borderWidth))

        imageWrapper.layoutCallback = { [weak self] (_) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateState()
        }
        addSubview(imageWrapper)
        imageWrapper.autoPin(toEdgesOf: imageView)

        imageWrapper.addSubview(selectionView)
        selectionView.autoVCenterInSuperview()

        // There must be a better way to pin the selection view's location,
        // but I can't find it.
        let selectionConstraint = NSLayoutConstraint(item: selectionView, attribute: .centerX, relatedBy: .equal,
                                                     toItem: imageWrapper, attribute: .leading, multiplier: 1, constant: 0)
        selectionConstraint.autoInstall()
        self.selectionConstraint = selectionConstraint

        previewView.isHidden = true
        addSubview(previewView)
        previewView.autoPinEdge(.bottom, to: .top, of: imageView, withOffset: -24)
        previewView.centerXAnchor.constraint(equalTo: selectionView.centerXAnchor).isActive = true

        addGestureRecognizer(PermissiveGestureRecognizer(target: self, action: #selector(didTouch)))

        updateState()
    }

    private func selectColor(atLocationX locationX: CGFloat) {
        let palettePhase = locationX.inverseLerp(0, imageView.width, shouldClamp: true)
        selectedValue = value(for: palettePhase)

        delegate?.colorPickerBarView(self, didSelectColor: selectedValue)
    }

    private func value(for palettePhase: CGFloat) -> ColorPickerBarColor {
        // We find the color in the palette's gradient that corresponds
        // to the "phase".
        //
        // 0 = top of gradient, first color.
        // 1 = bottom of gradient, last color.
        struct GradientSegment {
            let color0: UIColor
            let color1: UIColor
            let palettePhase0: CGFloat
            let palettePhase1: CGFloat
        }
        var segments = [GradientSegment]()
        let segmentCount = ColorPickerBarColor.gradientUIColors.count - 1
        var prevColor: UIColor?
        for color in ColorPickerBarColor.gradientUIColors {
            if let color0 = prevColor {
                let index = CGFloat(segments.count)
                let color1 = color
                let palettePhase0: CGFloat = index / CGFloat(segmentCount)
                let palettePhase1: CGFloat = (index + 1) / CGFloat(segmentCount)
                segments.append(GradientSegment(color0: color0, color1: color1, palettePhase0: palettePhase0, palettePhase1: palettePhase1))
            }
            prevColor = color
        }
        var bestSegment = segments.first
        for segment in segments {
            if palettePhase >= segment.palettePhase0 {
                bestSegment = segment
            }
        }
        guard let segment = bestSegment else {
            owsFailDebug("Couldn't find matching segment.")
            return ColorPickerBarColor.defaultColor()
        }
        guard palettePhase >= segment.palettePhase0,
              palettePhase <= segment.palettePhase1 else {
            owsFailDebug("Invalid segment.")
            return ColorPickerBarColor.defaultColor()
        }
        let segmentPhase = palettePhase.inverseLerp(segment.palettePhase0, segment.palettePhase1).clamp01()
        // If CAGradientLayer doesn't do naive RGB color interpolation,
        // this won't be WYSIWYG.
        let color = segment.color0.blended(with: segment.color1, alpha: segmentPhase)
        return ColorPickerBarColor(color: color, palettePhase: palettePhase)
    }

    private func updateState() {
        selectionView.backgroundColor = selectedValue.color
        previewView.selectedColor = selectedValue.color

        guard let selectionConstraint = selectionConstraint else {
            owsFailDebug("Missing selectionConstraint.")
            return
        }
        let selectionX = imageWrapper.width * selectedValue.palettePhase
        selectionConstraint.constant = selectionX
    }

    // MARK: Events

    @objc
    private func didTouch(gesture: UIGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            previewView.isHidden = false
        case .ended:
            previewView.isHidden = true
        default:
            previewView.isHidden = true
            return
        }

        let location = gesture.location(in: imageView)
        selectColor(atLocationX: location.x)
    }

    private static func buildPaletteGradientImage() -> UIImage {
        let gradientSize = CGSize(width: UIScreen.main.bounds.width, height: colorBarWidth)
        let gradientBounds = CGRect(origin: .zero, size: gradientSize)
        let gradientView = UIView()
        gradientView.frame = gradientBounds
        let gradientLayer = CAGradientLayer()
        gradientView.layer.addSublayer(gradientLayer)
        gradientLayer.frame = gradientBounds
        // See: https://github.com/signalapp/Signal-Android/blob/42e94d8f921aba212b1ffebfae4f2590a6f3385a/res/values/arrays.xml#L267-L277
        gradientLayer.colors = ColorPickerBarColor.gradientCGColors
        gradientLayer.startPoint = CGPoint.zero
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        return gradientView.renderAsImage(opaque: true, scale: UIScreen.main.scale)
    }
}

public extension UIColor {

    func isCloseToColor(_ color: UIColor) -> Bool {
        return isEqualToColor(color, tolerance: 0.1)
    }
}
