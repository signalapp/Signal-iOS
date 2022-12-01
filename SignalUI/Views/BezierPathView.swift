//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

@objc(OWSBezierPathView)
public class BezierPathView: UIView {

    public typealias ShapeLayerConfigurationBlock = (CAShapeLayer, CGRect) -> Void

    // Configure the view with this method if it uses a single Bezier path.
    public var shapeLayerConfigurationBlock: ShapeLayerConfigurationBlock? {
        didSet { updateShapeLayer() }
    }

    @objc(initWithConfigurationBlock:)
    public convenience init(configurationBlock: @escaping ShapeLayerConfigurationBlock) {
        self.init(frame: .zero)
        shapeLayerConfigurationBlock = configurationBlock
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)

        isOpaque = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var frame: CGRect {
        didSet {
            guard oldValue.size != frame.size else { return }
            updateShapeLayer()
        }
    }

    public override var bounds: CGRect {
        didSet {
            guard oldValue.size != bounds.size else { return }
            updateShapeLayer()
        }
    }

    // This method forces the view to reconstruct its layer content.  It shouldn't
    // be necessary to call this unless the ConfigureShapeLayerBlocks depend on external
    // state which has changed.
    private var shapeLayer: CAShapeLayer?
    private func updateShapeLayer() {
        guard bounds.width > 0 && bounds.height > 0 else { return }

        if let shapeLayer {
            shapeLayer.removeFromSuperlayer()
        }

        guard let shapeLayerConfigurationBlock else { return }

        let shapeLayer = CAShapeLayer()
        shapeLayer.disableAnimationsWithDelegate()
        shapeLayerConfigurationBlock(shapeLayer, bounds)
        layer.addSublayer(shapeLayer)
        self.shapeLayer = shapeLayer

        setNeedsDisplay()
    }

    public override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        return nil
    }
}
