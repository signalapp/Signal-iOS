//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

public class CircleView: UIView {

    @available(*, unavailable, message: "use other constructor instead.")
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
    }

    public init(diameter: CGFloat) {
        super.init(frame: .zero)

        autoSetDimensions(to: CGSize(square: diameter))
    }

    override public var frame: CGRect {
        didSet {
            updateRadius()
        }
    }

    override public var bounds: CGRect {
        didSet {
            updateRadius()
        }
    }

    private func updateRadius() {
        self.layer.cornerRadius = self.bounds.size.height / 2
    }
}

public class CircleBlurView: UIVisualEffectView {

    @available(*, unavailable, message: "use other constructor instead.")
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public init(effect: UIVisualEffect?) {
        super.init(effect: effect)
        frame = .zero
    }

    public init(effect: UIVisualEffect, diameter: CGFloat) {
        super.init(effect: effect)
        frame = .zero

        autoSetDimensions(to: CGSize(square: diameter))
    }

    override public var frame: CGRect {
        didSet {
            updateRadius()
        }
    }

    override public var bounds: CGRect {
        didSet {
            updateRadius()
        }
    }

    private func updateRadius() {
        layer.cornerRadius = bounds.size.height / 2
        clipsToBounds = true
    }
}

open class PillView: UIView {

    override public init(frame: CGRect) {
        super.init(frame: frame)

        layer.masksToBounds = true

        // Constrain to be a pill that is at least a circle, and maybe wider.
        autoPin(toAspectRatio: 1.0, relation: .greaterThanOrEqual)

        // low priority constraint to ensure the pill
        // is no taller than necessary
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            self.autoSetDimension(.height, toSize: 0)
        }
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var frame: CGRect {
        didSet {
            updateRadius()
        }
    }

    override public var bounds: CGRect {
        didSet {
            updateRadius()
        }
    }

    private func updateRadius() {
        layer.cornerRadius = bounds.size.height / 2
    }
}

public class RingView: UIView {

    override public class var layerClass: AnyClass {
        CAShapeLayer.self
    }

    private var shapeLayer: CAShapeLayer { layer as! CAShapeLayer }

    public var lineWidth: CGFloat {
        get {
            shapeLayer.lineWidth
        }
        set {
            shapeLayer.lineWidth = newValue
            updatePath()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        shapeLayer.fillColor = UIColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var frame: CGRect {
        didSet {
            if bounds.size != oldValue.size {
                updatePath()
            }
        }
    }

    override public var tintColor: UIColor! {
        didSet {
            updateColor()
        }
    }

    override public func tintColorDidChange() {
        super.tintColorDidChange()
        updateColor()
    }

    private func updatePath() {
        let inset = lineWidth / 2
        let insetRect = layer.bounds.insetBy(dx: inset, dy: inset)
        shapeLayer.path = UIBezierPath(ovalIn: insetRect).cgPath
    }

    private func updateColor() {
        shapeLayer.strokeColor = tintColor?.cgColor
    }
}
