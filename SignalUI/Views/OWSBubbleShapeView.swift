//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public struct OWSDirectionalRectCorner: OptionSet {
    public let rawValue: Int8

    public init(rawValue: Int8) {
        self.rawValue = rawValue
    }

    public static let topLeading = OWSDirectionalRectCorner(rawValue: 1 << 0)
    public static let topTrailing = OWSDirectionalRectCorner(rawValue: 1 << 1)
    public static let bottomLeading = OWSDirectionalRectCorner(rawValue: 1 << 2)
    public static let bottomTrailing = OWSDirectionalRectCorner(rawValue: 1 << 3)

    public static let allCorners: OWSDirectionalRectCorner = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
}

public protocol OWSBubbleViewHost: AnyObject {
    var maskPath: UIBezierPath { get }
    var bubbleReferenceView: UIView { get }
}

public protocol OWSBubbleViewPartner: AnyObject {
    func updateLayers()
    func setBubbleViewHost(_ bubbleViewHost: OWSBubbleViewHost?)
}

// While rendering message bubbles, we often need to render
// into a subregion of the bubble that reflects the intersection
// of some subview (e.g. a media view) and the bubble shape
// (including its rounding).
public class OWSBubbleShapeView: UIView, OWSBubbleViewPartner {

    // This view support multiple kinds of rendering.
    public enum Mode: Equatable {
        case stroke(strokeColor: UIColor, strokeThickness: CGFloat)
        case fill(fillColor: UIColor)
        case strokeAndFill(fillColor: UIColor, strokeColor: UIColor, strokeThickness: CGFloat)
        // Casts a shadow over a subregion of the bubble shape.
        case shadow(fillColor: UIColor?)
        // Clipping subviews to subregion of the bubble shape.
        case clip
        case innerShadow(color: UIColor, radius: CGFloat, opacity: Float)
    }

    // If we ever make mode a var, we need to clear currentState
    // in a didSet clause.
    private let mode: Mode

    private let shapeLayer = CAShapeLayer()
    private let maskLayer = CAShapeLayer()

    private weak var bubbleViewHost: OWSBubbleViewHost? {
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

        owsAssertDebug(self.layer.delegate === self)
        shapeLayer.disableAnimationsWithDelegate()
        maskLayer.disableAnimationsWithDelegate()

        layer.addSublayer(shapeLayer)

        isConfigured = true

        updateLayers()
    }

    @available(*, unavailable, message: "use other constructor instead.")
    public required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }

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

    public func setBubbleViewHost(_ bubbleViewHost: OWSBubbleViewHost?) {
        self.bubbleViewHost = bubbleViewHost
    }

    public func updateLayers() {
        guard isConfigured,
              let bubbleViewHost = bubbleViewHost else {
            return
        }
        // Add the bubble view's path to the local path.
        let bubbleBezierPath: UIBezierPath = bubbleViewHost.maskPath
        // We need to convert between coordinate systems using layers, not views.
        let bubbleOffset: CGPoint = self.convert(CGPoint.zero, from: bubbleViewHost.bubbleReferenceView)

        let newState = State(bounds: bounds,
                             bubbleOffset: bubbleOffset,
                             bubbleBezierPath: bubbleBezierPath)
        guard newState != currentState else {
            return
        }
        currentState = newState
        Self.updateLayers(mode: mode,
                          state: newState,
                          bubbleShapeView: self)
    }

    private struct State: Equatable {
        let bounds: CGRect
        let bubbleOffset: CGPoint
        let bubbleBezierPath: UIBezierPath
    }

    private var currentState: State?

    private static func updateLayers(mode: Mode,
                                     state: State,
                                     bubbleShapeView: OWSBubbleShapeView) {
        let shapeLayer = bubbleShapeView.shapeLayer
        let maskLayer = bubbleShapeView.maskLayer
        let bounds = state.bounds
        let bubbleOffset = state.bubbleOffset
        let bubbleBezierPath = state.bubbleBezierPath

        let bezierPath = UIBezierPath()

        let transform: CGAffineTransform = CGAffineTransform.translate(bubbleOffset)
        bubbleBezierPath.apply(transform)
        bezierPath.append(bubbleBezierPath)

        func configureForDrawing(fillColor: UIColor? = nil,
                                 strokeColor: UIColor? = nil,
                                 strokeThickness: CGFloat = 0) {

            bezierPath.append(UIBezierPath(rect: bounds))

            bubbleShapeView.clipsToBounds = true

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
            bubbleShapeView.clipsToBounds = false

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
            bubbleShapeView.layer.mask = maskLayer
        case .innerShadow(let color, let radius, let opacity):
            // Inner shadow.
            // This should usually not be visible; it is used to distinguish
            // profile pics from the background if they are similar.
            shapeLayer.frame = bounds
            shapeLayer.masksToBounds = true
            let shadowBounds = bounds
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
    }

    // MARK: - CALayerDelegate

    @objc
    public override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        // Disable all implicit CALayer animations.
        NSNull()
    }
}
