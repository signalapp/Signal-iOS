//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// While rendering message bubbles, we often need to render
// into a subregion of the bubble that reflects the intersection
// of some subview (e.g. a media view) and the bubble shape
// (including its rounding).
@objc
public class OWSBubbleShapeView: UIView, OWSBubbleViewPartner {

    // This view support multiple kinds of rendering.
    public enum Mode {
        case stroke(strokeColor: UIColor, strokeThickness: CGFloat)
        case fill(fillColor: UIColor)
        case strokeAndFill(fillColor: UIColor, strokeColor: UIColor, strokeThickness: CGFloat)
        // Casts a shadow over a subregion of the bubble shape.
        case shadow(fillColor: UIColor?)
        // Clipping subviews to subregion of the bubble shape.
        case clip
        case innerShadow(color: UIColor, radius: CGFloat, opacity: Float)
    }

    private let mode: Mode

    private let shapeLayer = CAShapeLayer()
    private let maskLayer = CAShapeLayer()

    private weak var bubbleView: OWSBubbleView? {
        didSet {
            updateLayers()
        }
    }

    private var isConfigured = false

    public required init(mode: Mode) {
        self.mode = mode

        super.init(frame: .zero)

        self.isOpaque = false
        self.backgroundColor = .clear
        self.layoutMargins = .zero

        layer.addSublayer(shapeLayer)

        isConfigured = true

        updateLayers()
    }

    @available(*, unavailable, message: "use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }
//    
//    - (void)setFillColor:(nullable UIColor *)fillColor
//    {
//    _fillColor = fillColor;
//    
//    [self updateLayers];
//    }
//    
//    - (void)setStrokeColor:(nullable UIColor *)strokeColor
//    {
//    _strokeColor = strokeColor;
//    
//    [self updateLayers];
//    }
//    
//    - (void)setStrokeThickness:(CGFloat)strokeThickness
//    {
//    _strokeThickness = strokeThickness;
//    
//    [self updateLayers];
//    }
//    
//    - (void)setInnerShadowColor:(nullable UIColor *)innerShadowColor
//    {
//    _innerShadowColor = innerShadowColor;
//    
//    [self updateLayers];
//    }
//    
//    - (void)setInnerShadowRadius:(CGFloat)innerShadowRadius
//    {
//    _innerShadowRadius = innerShadowRadius;
//    
//    [self updateLayers];
//    }
//    
//    - (void)setInnerShadowOpacity:(float)innerShadowOpacity
//    {
//    _innerShadowOpacity = innerShadowOpacity;
//    
//    [self updateLayers];
//    }

    public override var bounds: CGRect {
        didSet {
            if oldValue.size != bounds.size {
                viewSizeDidChange()
            }
        }
    }

    public override var frame: CGRect {
        didSet {
            if oldValue.size != frame.size {
                viewSizeDidChange()
            }
        }
    }

    private func viewSizeDidChange() {
        updateLayers()
    }

    // MARK: - OWSBubbleViewPartner

    public func setBubbleView(_ bubbleView: OWSBubbleView?) {
        self.bubbleView = bubbleView
    }

    public func updateLayers() {
        guard isConfigured,
              let bubbleView = bubbleView else {
            return
        }

        // Prevent the layer from animating changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let bezierPath = UIBezierPath()

        // Add the bubble view's path to the local path.
        let bubbleBezierPath: UIBezierPath = bubbleView.maskPath()
        // We need to convert between coordinate systems using layers, not views.
        let bubbleOffset: CGPoint = layer.convert(CGPoint.zero, from: bubbleView.layer)
        let transform: CGAffineTransform = CGAffineTransform.translate(bubbleOffset)
        bubbleBezierPath.apply(transform)
        bezierPath.append(bubbleBezierPath)

        func configureForDrawing(fillColor: UIColor? = nil,
                                 strokeColor: UIColor? = nil,
                                 strokeThickness: CGFloat = 0) {

            bezierPath.append(UIBezierPath(rect: bounds))

            clipsToBounds = true

            if let strokeColor = strokeColor {
                shapeLayer.strokeColor = strokeColor.cgColor
                shapeLayer.lineWidth = strokeThickness
                shapeLayer.zPosition = 100
            } else {
                shapeLayer.strokeColor = nil
                shapeLayer.lineWidth = 0
            }

            if let fillColor = fillColor {
                shapeLayer.fillColor = fillColor.cgColor
            } else {
                shapeLayer.fillColor = nil
            }

            shapeLayer.path = bezierPath.cgPath
        }

        switch mode {
        case .stroke(let strokeColor, let strokeThickness):
            configureForDrawing(strokeColor: strokeColor, strokeThickness: strokeThickness)
        case .fill(let fillColor):
            configureForDrawing(fillColor: fillColor)
        case .strokeAndFill(let fillColor, let strokeColor, let strokeThickness):
            configureForDrawing(fillColor: fillColor, strokeColor: strokeColor, strokeThickness: strokeThickness)
        case .shadow(let fillColor):
            clipsToBounds = false

            if let fillColor = fillColor {
                shapeLayer.fillColor = fillColor.cgColor
            } else {
                shapeLayer.fillColor = nil
            }

            shapeLayer.path = bezierPath.cgPath
            shapeLayer.frame = bounds
            shapeLayer.masksToBounds = true
            shapeLayer.shadowPath = bezierPath.cgPath

        case .clip:
            maskLayer.path = bezierPath.cgPath
            layer.mask = maskLayer
        case .innerShadow(let color, let radius, let opacity):
            // Inner shadow.
            // This should usually not be visible; it is used to distinguish
            // profile pics from the background if they are similar.
            shapeLayer.frame = bounds
            shapeLayer.masksToBounds = true
            let shadowBounds = self.bounds
            let shadowPath = bezierPath.copy() as! UIBezierPath
            // This can be any value large enough to cast a sufficiently large shadow.
            let shadowInset = radius * -4
            let outerRect = shadowBounds.inset(by: UIEdgeInsets(hMargin: shadowInset,
                                                                vMargin: shadowInset))
            let outerPath = UIBezierPath(rect: outerRect)
            // -[CALayer shadowPath] uses the non-zero winding rule
            // Reverse the path to make the directions line up correctly.
            shadowPath.append(outerPath.reversing())

            // This can be any color since the fill should be clipped.
            shapeLayer.fillColor = UIColor.black.cgColor
            shapeLayer.path = shadowPath.cgPath
            shapeLayer.shadowColor = color.cgColor
            shapeLayer.shadowRadius = radius
            shapeLayer.shadowOpacity = opacity
            shapeLayer.shadowOffset = .zero
            shapeLayer.shadowPath = shadowPath.cgPath
        }

        CATransaction.commit()
    }
}
