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
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        self.addGestureRecognizer(tapGesture)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - Actions

    @objc
    func didTap() {
        Logger.verbose("")

        addRandomStroke()
    }

    private func addRandomStroke() {
        let randomUnitValue = { () -> CGFloat in
            let scale: UInt32 = 32
            let value = CGFloat(arc4random_uniform(scale)) / CGFloat(scale)
            return value
        }
        let randomSample = {
            return CGPoint(x: randomUnitValue(), y: randomUnitValue())
        }
        let item = ImageEditorStrokeItem(color: UIColor.red,
                                         unitSamples: [randomSample(), randomSample(), randomSample() ],
                                         unitStrokeWidth: ImageEditorStrokeItem.defaultUnitStrokeWidth())
        model.append(item: item)
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
            guard let layer = layerForItem(item: item) else {
                Logger.error("Couldn't create layer for item.")
                continue
            }

            self.layer.addSublayer(layer)
        }

        CATransaction.commit()
    }

    private func layerForItem(item: ImageEditorItem) -> CALayer? {
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
            return strokeLayerForItem(item: strokeItem)
        }
    }

    private func strokeLayerForItem(item: ImageEditorStrokeItem) -> CALayer? {
        AssertIsOnMainThread()

        let viewSize = bounds.size
        let strokeWidth = ImageEditorStrokeItem.strokeWidth(forUnitStrokeWidth: item.unitStrokeWidth,
                                                            dstSize: viewSize)
        let unitSamples = item.unitSamples
        guard unitSamples.count > 1 else {
            return nil
        }

        let shapeLayer = CAShapeLayer()
        shapeLayer.lineWidth = strokeWidth
        shapeLayer.strokeColor = item.color.cgColor
        shapeLayer.frame = self.bounds

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
}
