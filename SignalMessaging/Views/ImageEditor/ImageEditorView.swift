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

        return shapeLayer
    }
}
