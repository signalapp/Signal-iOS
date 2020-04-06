//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CircularProgressView: UIView {

    // MARK: -

    // As a fraction of radius.
    private let thickness: CGFloat

    private let shapeLayer1 = CAShapeLayer()
    private let shapeLayer2 = CAShapeLayer()

    @objc
    public var trackColor: UIColor = UIColor(white: 1.0, alpha: 0.4)
    @objc
    public var progressColor: UIColor = (Theme.isDarkThemeEnabled ? .ows_gray25 : .ows_white)

    public var progress: CGFloat? {
        didSet {
            AssertIsOnMainThread()

            updateLayers()
        }
    }

    @objc
    public required init(thickness: CGFloat = 0.1) {
        self.thickness = thickness.clamp01()

        super.init(frame: .zero)

        shapeLayer1.zPosition = 1
        shapeLayer2.zPosition = 2
        layer.addSublayer(shapeLayer1)
        layer.addSublayer(shapeLayer2)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc public override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                updateLayers()
            }
        }
    }

    @objc public override var frame: CGRect {
        didSet {
            if oldValue != frame {
                updateLayers()
            }
        }
    }

    internal func updateLayers() {
        AssertIsOnMainThread()

        shapeLayer1.frame = self.bounds
        shapeLayer2.frame = self.bounds

        guard let progress = progress else {
            Logger.warn("No progress to render.")
            shapeLayer1.path = nil
            shapeLayer2.path = nil
            return
        }

        // Prevent the shape layer from animating changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let radius: CGFloat = min(self.bounds.width * 0.5,
                                  self.bounds.height * 0.5)
        let center = CGPoint(x: self.bounds.width * 0.5,
                             y: self.bounds.height * 0.5)
        let outerRadius: CGFloat = radius * 1.0
        let innerRadius: CGFloat = radius * (1 - thickness)
        let startAngle: CGFloat = CGFloat.pi * 1.5
        let endAngle: CGFloat = CGFloat.pi * (1.5 + 2 * progress)

        let bezierPath1 = UIBezierPath()
        bezierPath1.append(UIBezierPath(ovalIn: CGRect(origin: center.minus(CGPoint(x: innerRadius,
                                                                                    y: innerRadius)),
                                                       size: CGSize(square: innerRadius * 2))))
        bezierPath1.append(UIBezierPath(ovalIn: CGRect(origin: center.minus(CGPoint(x: outerRadius,
                                                                                    y: outerRadius)),
                                                       size: CGSize(square: outerRadius * 2))))
        shapeLayer1.path = bezierPath1.cgPath
        shapeLayer1.fillColor = trackColor.cgColor
        shapeLayer1.fillRule = .evenOdd

        let bezierPath2 = UIBezierPath()
        bezierPath2.addArc(withCenter: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        bezierPath2.addArc(withCenter: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: false)
        shapeLayer2.path = bezierPath2.cgPath
        shapeLayer2.fillColor = progressColor.cgColor

        CATransaction.commit()
    }
}
