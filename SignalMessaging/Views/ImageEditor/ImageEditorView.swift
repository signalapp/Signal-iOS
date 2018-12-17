//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class ImageEditorView: UIView, ImageEditorModelDelegate {
    private let model: ImageEditorModel

    @objc
    public required init(model: ImageEditorModel) {
        self.model = model

        super.init(frame: .zero)

        model.delegate = self

        self.isUserInteractionEnabled = true

        let anyTouchGesture = ImageEditorGestureRecognizer(target: self, action: #selector(handleTouchGesture(_:)))
        self.addGestureRecognizer(anyTouchGesture)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - Actions

    // These properties are non-empty while drawing a stroke.
    private var currentStroke: ImageEditorStrokeItem?
    private var currentStrokeSamples = [ImageEditorStrokeItem.StrokeSample]()

    @objc
    public func handleTouchGesture(_ gestureRecognizer: UIGestureRecognizer) {
        AssertIsOnMainThread()


        let removeCurrentStroke = {
            if let stroke = self.currentStroke {
                self.model.remove(item: stroke)
            }
            self.currentStroke = nil
            self.currentStrokeSamples.removeAll()
        }

        let referenceView = self
        let unitSampleForGestureLocation = { () -> CGPoint in
            let location = gestureRecognizer.location(in: referenceView)
            let x = CGFloatClamp01(CGFloatInverseLerp(location.x, 0, referenceView.bounds.width))
            let y = CGFloatClamp01(CGFloatInverseLerp(location.y, 0, referenceView.bounds.height))
            return CGPoint(x: x, y: y)
        }

        // TODO:
        let strokeColor = UIColor.blue
        let unitStrokeWidth = ImageEditorStrokeItem.defaultUnitStrokeWidth()

        switch gestureRecognizer.state {
        case .began:
            removeCurrentStroke()

            currentStrokeSamples.append(unitSampleForGestureLocation())

            let stroke = ImageEditorStrokeItem(color: strokeColor, unitSamples: self.currentStrokeSamples, unitStrokeWidth: unitStrokeWidth)
            self.model.append(item: stroke)
            self.currentStroke = stroke

        case .changed, .ended:
            currentStrokeSamples.append(unitSampleForGestureLocation())

            guard let lastStroke = self.currentStroke else {
                owsFailDebug("Missing last stroke.")
                removeCurrentStroke()
                return
            }

            // Model items are immutable; we _replace_ the
            // stroke item rather than modify it.
            let stroke = ImageEditorStrokeItem(itemId: lastStroke.itemId, color: strokeColor, unitSamples: self.currentStrokeSamples, unitStrokeWidth: unitStrokeWidth)
            self.model.replace(item: stroke)
            self.currentStroke = stroke

            if gestureRecognizer.state == .ended {
                self.currentStroke = nil
                self.currentStrokeSamples.removeAll()
            }
        default:
            removeCurrentStroke()
        }
    }

    // MARK: - ImageEditorModelDelegate

    public func imageEditorModelDidChange() {
        // TODO: We eventually want to narrow our change events
        // to reflect the specific item(s) which changed.
        updateAllContent()
    }

    // MARK: - Accessor Overrides

    @objc public override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                updateAllContent()
            }
        }
    }

    @objc public override var frame: CGRect {
        didSet {
            if oldValue != frame {
                updateAllContent()
            }
        }
    }

    // MARK: - Content

    var contentLayers = [CALayer]()

    internal func updateAllContent() {
        AssertIsOnMainThread()

        for layer in contentLayers {
            layer.removeFromSuperlayer()
        }
        contentLayers.removeAll()

        guard bounds.width > 0,
            bounds.height > 0 else {
                return
        }

        // Don't animate changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for item in model.items() {
            guard let layer = ImageEditorView.layerForItem(item: item,
                                                           viewSize: bounds.size) else {
                Logger.error("Couldn't create layer for item.")
                continue
            }

            self.layer.addSublayer(layer)
            contentLayers.append(layer)
        }

        CATransaction.commit()
    }

    private class func layerForItem(item: ImageEditorItem,
                                    viewSize: CGSize) -> CALayer? {
        AssertIsOnMainThread()

        switch item.itemType {
        case .test:
            owsFailDebug("Unexpected test item.")
            return nil
        case .stroke:
            guard let strokeItem = item as? ImageEditorStrokeItem else {
                owsFailDebug("Item has unexpected type: \(type(of: item)).")
                return nil
            }
            return strokeLayerForItem(item: strokeItem, viewSize: viewSize)
        }
    }

    private class func strokeLayerForItem(item: ImageEditorStrokeItem,
                                          viewSize: CGSize) -> CALayer? {
        AssertIsOnMainThread()

        let strokeWidth = ImageEditorStrokeItem.strokeWidth(forUnitStrokeWidth: item.unitStrokeWidth,
                                                            dstSize: viewSize)
        let unitSamples = item.unitSamples
        guard unitSamples.count > 1 else {
            return nil
        }

        let shapeLayer = CAShapeLayer()
        shapeLayer.lineWidth = strokeWidth
        shapeLayer.strokeColor = item.color.cgColor
        shapeLayer.frame = CGRect(origin: .zero, size: viewSize)

        let transformSampleToPoint = { (unitSample: CGPoint) -> CGPoint in
            return CGPoint(x: viewSize.width * unitSample.x,
                           y: viewSize.height * unitSample.y)
        }

        // TODO: Use bezier curves to smooth stroke.
        let bezierPath = UIBezierPath()

        let points = unitSamples.map { (unitSample) in
            transformSampleToPoint(unitSample)
        }
        var lastForwardVector = CGPoint.zero
        for index in 0..<points.count {
            let point = points[index]

            let forwardVector: CGPoint
            if index == 0 {
                // First sample.
                let nextPoint = points[index + 1]
                forwardVector = CGPointSubtract(nextPoint, point)
            } else if index == unitSamples.count - 1 {
                // Last sample.
                let lastPoint = points[index - 1]
                forwardVector = CGPointSubtract(point, lastPoint)
            } else {
                // Middle samples.
                let lastPoint = points[index - 1]
                let lastForwardVector = CGPointSubtract(point, lastPoint)
                let nextPoint = points[index + 1]
                let nextForwardVector = CGPointSubtract(nextPoint, point)
                forwardVector = CGPointScale(CGPointAdd(lastForwardVector, nextForwardVector), 0.5)
            }

            if index == 0 {
                // First sample.
                bezierPath.move(to: point)
            } else {
                let lastPoint = points[index - 1]
                // This factor controls how much we're smoothing.
                //
                // * 0.0 = No smoothing.
                //
                // TODO: Tune this variable once we have stroke input.
                let controlPointFactor: CGFloat = 0.25
                let controlPoint1 = CGPointAdd(lastPoint, CGPointScale(lastForwardVector, +controlPointFactor))
                let controlPoint2 = CGPointAdd(point, CGPointScale(forwardVector, -controlPointFactor))
                // We're using Cubic curves.  
                bezierPath.addCurve(to: point, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
            }
            lastForwardVector = forwardVector
        }
        var hasSample = false
        for unitSample in unitSamples {
            let point = transformSampleToPoint(unitSample)
            if hasSample {
                bezierPath.addLine(to: point)
            } else {
                bezierPath.move(to: point)
                hasSample = true
            }
        }

        shapeLayer.path = bezierPath.cgPath
        shapeLayer.fillColor = nil
        shapeLayer.lineCap = kCALineCapRound

        return shapeLayer
    }

    // MARK: - Actions

    // Returns nil on error.
    @objc
    public class func renderForOutput(model: ImageEditorModel) -> UIImage? {
        // TODO: Do we want to render off the main thread?
        AssertIsOnMainThread()

        // Render output at same size as source image.
        let dstSizePixels = model.srcImageSizePixels

        let hasAlpha = NSData.hasAlpha(forValidImageFilePath: model.srcImagePath)

        guard let srcImage = UIImage(contentsOfFile: model.srcImagePath) else {
            owsFailDebug("Could not load src image.")
            return nil
        }

        let dstScale: CGFloat = 1.0 // The size is specified in pixels, not in points.
        UIGraphicsBeginImageContextWithOptions(dstSizePixels, !hasAlpha, dstScale)

        guard let context = UIGraphicsGetCurrentContext() else {
            owsFailDebug("Could not create output context.")
            return nil
        }
        context.interpolationQuality = .high

        // Draw source image.
        let dstFrame = CGRect(origin: .zero, size: model.srcImageSizePixels)
        srcImage.draw(in: dstFrame)

        for item in model.items() {
            guard let layer = layerForItem(item: item,
                                           viewSize: dstSizePixels) else {
                Logger.error("Couldn't create layer for item.")
                continue
            }
            // This might be superfluous, but ensure that the layer renders
            // at "point=pixel" scale.
            layer.contentsScale = 1.0

            // TODO:
            Logger.verbose("layer.contentsScale: \(layer.contentsScale)")

            layer.render(in: context)
        }

        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        if scaledImage == nil {
            owsFailDebug("could not generate dst image.")
        }
        UIGraphicsEndImageContext()
        return scaledImage
    }
}
