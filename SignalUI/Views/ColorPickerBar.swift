//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// We represent picker colors using this (color, phase)
// tuple so that we can consistently restore palette view state.
public struct ColorPickerBarColor {
    public let color: UIColor

    // Colors are chosen from a spectrum of colors.
    // This unit value represents the location of the
    // color within that spectrum.
    let palettePhase: CGFloat

    var cgColor: CGColor {
        return color.cgColor
    }

    static var defaultColor: ColorPickerBarColor {
        return ColorPickerBarColor(color: UIColor(rgbHex: 0xff0000), palettePhase: 1 / 9)
    }

    static var white: ColorPickerBarColor {
        ColorPickerBarColor(color: .white, palettePhase: 1)
    }

    static var black: ColorPickerBarColor {
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
            UIColor(rgbHex: 0xffffff),
        ]
    }

    static var gradientCGColors: [CGColor] {
        return gradientUIColors.map { $0.cgColor }
    }

    static func ==(left: ColorPickerBarColor, right: ColorPickerBarColor) -> Bool {
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

        layoutCallback = { view in
            ColorPreviewView.updateLayers(
                view: view,
                circleLayer: circleLayer,
                teardropLayer: teardropLayer,
            )
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

    static func updateLayers(
        view: UIView,
        circleLayer: CAShapeLayer,
        teardropLayer: CAShapeLayer,
    ) {
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
        teardropPath.addArc(
            withCenter: circleCenter,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true,
        )
        teardropPath.addArc(
            withCenter: teardropTipCenter,
            radius: teardropTipRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true,
        )

        teardropLayer.path = teardropPath.cgPath
        teardropLayer.frame = bounds

        let innerCircleSize = CGSize(square: innerRadius * 2)
        let circleFrame = CGRect(
            origin: circleCenter.minus(innerCircleSize.asPoint.times(0.5)),
            size: innerCircleSize,
        )
        circleLayer.path = UIBezierPath(ovalIn: circleFrame).cgPath
        circleLayer.frame = bounds
    }
}

// MARK: -

public class ColorPickerBar: UIControl {

    public var uiColor: UIColor { color.color }

    var color: ColorPickerBarColor {
        didSet {
            updateState()
        }
    }

    init(color: ColorPickerBarColor? = nil) {
        self.color = color ?? .defaultColor

        super.init(frame: .zero)

        // Ideally we want the image to match bar width, but with all the margins
        // and different screen sizes it's challenging to make this right.
        // This estimate is good enough as we don't need designer level precision.
        colorBarImageView.image = ColorPickerBar.buildPaletteGradientImage(width: 480)
        colorBarImageView.translatesAutoresizingMaskIntoConstraints = false
        colorBarImageView.clipsToBounds = true

        if #available(iOS 26, *) {
            // No border, pill shape using `cornerConfiguration`.
            addSubview(colorBarImageView)
            colorBarImageView.cornerConfiguration = .capsule()
            NSLayoutConstraint.activate([
                colorBarImageView.heightAnchor.constraint(equalToConstant: LayoutMetrics.colorBarHeight),
                colorBarImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                colorBarImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                colorBarImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        } else {
            let borderWidth = LayoutMetrics.borderWidth

            // Create a capsule shape that's larger than color bar by `borderWidth` in every dimension
            // to simulate outer border appearance.
            let backgroundPillView = PillView()
            backgroundPillView.clipsToBounds = true
            backgroundPillView.backgroundColor = .white
            backgroundPillView.translatesAutoresizingMaskIntoConstraints = false
            backgroundPillView.addSubview(colorBarImageView)
            addSubview(backgroundPillView)
            NSLayoutConstraint.activate([
                backgroundPillView.heightAnchor.constraint(equalToConstant: LayoutMetrics.colorBarHeight + 2 * borderWidth),
                backgroundPillView.centerYAnchor.constraint(equalTo: centerYAnchor),
                backgroundPillView.leadingAnchor.constraint(equalTo: leadingAnchor),
                backgroundPillView.trailingAnchor.constraint(equalTo: trailingAnchor),

                colorBarImageView.topAnchor.constraint(
                    equalTo: backgroundPillView.topAnchor,
                    constant: borderWidth,
                ),
                colorBarImageView.leadingAnchor.constraint(
                    equalTo: backgroundPillView.leadingAnchor,
                    constant: borderWidth,
                ),
                colorBarImageView.trailingAnchor.constraint(
                    equalTo: backgroundPillView.trailingAnchor,
                    constant: -borderWidth,
                ),
                colorBarImageView.bottomAnchor.constraint(
                    equalTo: backgroundPillView.bottomAnchor,
                    constant: -borderWidth,
                ),
            ])

            // Corner rounding on the color bar.
            colorBarImageView.layer.cornerRadius = 0.5 * LayoutMetrics.colorBarHeight
        }

        // Thumb view.
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbView)
        let thumbViewPositionConstraint = thumbView.centerXAnchor.constraint(equalTo: colorBarImageView.leadingAnchor)
        NSLayoutConstraint.activate([
            thumbView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbViewPositionConstraint,
        ])
        self.thumbViewPositionConstraint = thumbViewPositionConstraint

        // Preview appears above the color bar while user is touching the control.
        previewView.isHidden = true
        previewView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.bottomAnchor.constraint(
                equalTo: colorBarImageView.topAnchor,
                constant: -24,
            ),
            previewView.centerXAnchor.constraint(equalTo: thumbView.centerXAnchor),
        ])

        addGestureRecognizer(PermissiveGestureRecognizer(target: self, action: #selector(didTouch)))

        updateState()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: LayoutMetrics.thumbSize)
    }

    // MARK: - Layout

    private enum LayoutMetrics {
        static let thumbSize: CGFloat = 24
        static let colorBarHeight: CGFloat = 16
        static let borderWidth: CGFloat = if #available(iOS 26, *) { 0 } else { 1.5 }
    }

    private let colorBarImageView = UIImageView()

    private lazy var thumbView = ThumbView(color: uiColor)
    private var thumbViewPositionConstraint: NSLayoutConstraint?

    private let previewView = ColorPreviewView()

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
            return .defaultColor
        }
        guard
            palettePhase >= segment.palettePhase0,
            palettePhase <= segment.palettePhase1
        else {
            owsFailDebug("Invalid segment.")
            return .defaultColor
        }
        let segmentPhase = palettePhase.inverseLerp(segment.palettePhase0, segment.palettePhase1).clamp01()
        // If CAGradientLayer doesn't do naive RGB color interpolation,
        // this won't be WYSIWYG.
        let color = segment.color0.blended(with: segment.color1, alpha: segmentPhase)
        return ColorPickerBarColor(color: color, palettePhase: palettePhase)
    }

    private func updateState() {
        thumbView.color = uiColor
        previewView.selectedColor = uiColor

        guard let thumbViewPositionConstraint else {
            owsFailDebug("Missing selectionConstraint.")
            return
        }
        let position = colorBarImageView.frame.width * color.palettePhase
        thumbViewPositionConstraint.constant = position
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

        // We only care about `x` component. `y` can be outside of the color bar since it's pretty short in height.
        let touchLocation = gesture.location(in: colorBarImageView)
        let palettePhase = touchLocation.x.inverseLerp(0, colorBarImageView.bounds.width, shouldClamp: true)
        color = value(for: palettePhase)

        sendActions(for: .valueChanged)
    }

    private static func buildPaletteGradientImage(width: CGFloat) -> UIImage {
        let gradientSize = CGSize(width: width, height: LayoutMetrics.colorBarHeight)
        let gradientView = UIView(frame: CGRect(origin: .zero, size: gradientSize))
        let gradientLayer = CAGradientLayer()
        gradientView.layer.addSublayer(gradientLayer)
        gradientLayer.frame = gradientView.layer.bounds
        // See: https://github.com/signalapp/Signal-Android/blob/42e94d8f921aba212b1ffebfae4f2590a6f3385a/res/values/arrays.xml#L267-L277
        gradientLayer.colors = ColorPickerBarColor.gradientCGColors
        gradientLayer.startPoint = CGPoint.zero
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        let displayScale = UITraitCollection.current.displayScale
        return gradientView.renderAsImage(opaque: true, scale: displayScale)
    }

    private class ThumbView: UIView {

        var color: UIColor {
            didSet {
                colorCircleView.backgroundColor = color
            }
        }

        private let colorCircleView = UIView()
        private var backgroundView: UIView? // UIBlurEffect view on pre-iOS 26

        private static let colorCircleSize: CGFloat = 10

        init(color: UIColor) {
            self.color = color

            super.init(frame: .zero)

            colorCircleView.backgroundColor = color
            colorCircleView.translatesAutoresizingMaskIntoConstraints = false
            colorCircleView.clipsToBounds = true

            if #available(iOS 26, *) {
                colorCircleView.cornerConfiguration = .capsule()

                // Glass background on iOS 26+.
                let glassEffectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
                glassEffectView.clipsToBounds = true
                glassEffectView.cornerConfiguration = .capsule()
                glassEffectView.translatesAutoresizingMaskIntoConstraints = false
                addSubview(glassEffectView)
                glassEffectView.contentView.addSubview(colorCircleView)
                NSLayoutConstraint.activate([
                    glassEffectView.topAnchor.constraint(equalTo: topAnchor),
                    glassEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    glassEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    glassEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

                    colorCircleView.widthAnchor.constraint(equalToConstant: Self.colorCircleSize),
                    colorCircleView.heightAnchor.constraint(equalToConstant: Self.colorCircleSize),

                    colorCircleView.centerXAnchor.constraint(equalTo: centerXAnchor),
                    colorCircleView.centerYAnchor.constraint(equalTo: centerYAnchor),
                ])
            } else {
                // Blur background on pre iOS 26.
                let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialLight))
                blurEffectView.clipsToBounds = true
                addSubview(blurEffectView)
                blurEffectView.contentView.addSubview(colorCircleView)

                backgroundView = blurEffectView
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            guard #unavailable(iOS 26), let backgroundView else { return }

            // No auto-layout pre-iOS 26. Set corner radius manually.

            backgroundView.frame = bounds
            backgroundView.layer.cornerRadius = 0.5 * bounds.size.smallerAxis

            colorCircleView.frame.size = .square(Self.colorCircleSize)
            colorCircleView.center = backgroundView.bounds.center
            colorCircleView.layer.cornerRadius = 0.5 * Self.colorCircleSize
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize {
            .square(LayoutMetrics.thumbSize)
        }
    }
}

public extension UIColor {

    func isCloseToColor(_ color: UIColor) -> Bool {
        return isEqualToColor(color, tolerance: 0.1)
    }
}
