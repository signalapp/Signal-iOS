//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class CVChatColorView: ManualLayoutViewWithLayer {

    private weak var referenceView: UIView?
    private var chatColor: CVChatColor?

    private let gradientLayer = CAGradientLayer()

    public init() {
        super.init(name: "CVChatColorView")

        addLayoutBlock { view in
            guard let view = view as? CVChatColorView else { return }
            view.gradientLayer.frame = view.bounds
            view.updateAppearance()
        }
    }

    public func configure(chatColor: CVChatColor, referenceView: UIView) {
        self.chatColor = chatColor
        self.referenceView = referenceView
        updateAppearance()
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String) {
        owsFail("Do not use this initializer.")
    }

    public func updateAppearance() {
        guard let chatColor = self.chatColor,
              let referenceView = self.referenceView else {
            self.backgroundColor = nil
            gradientLayer.removeFromSuperlayer()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch chatColor {
        case .solidColor(let color):
            backgroundColor = color
            gradientLayer.removeFromSuperlayer()
        case .gradient(let color1, let color2, let angleRadians):

            if gradientLayer.superlayer != self.layer {
                gradientLayer.removeFromSuperlayer()
                layer.addSublayer(gradientLayer)
            }

            gradientLayer.frame = self.bounds

            gradientLayer.colors = [
                color1.cgColor,
                color2.cgColor
            ]

            /* The start and end points of the gradient when drawn into the layer's
             * coordinate space. The start point corresponds to the first gradient
             * stop, the end point to the last gradient stop. Both points are
             * defined in a unit coordinate space that is then mapped to the
             * layer's bounds rectangle when drawn. (I.e. [0,0] is the bottom-left
             * corner of the layer, [1,1] is the top-right corner.) The default values
             * are [.5,0] and [.5,1] respectively. Both are animatable. */
            let unitCenter = CGPoint(x: 0.5, y: 0.5)
            // Note the signs.
            let startVector = CGPoint(x: +sin(angleRadians), y: -cos(angleRadians))
            let startScale: CGFloat
            // In rectangle mode, we want the startPoint and endPoint to reside
            // on the edge of the unit square, and thus edge of the rectangle.
            // We therefore scale such that longer axis is a half unit.
            let startSquareScale: CGFloat = max(abs(startVector.x), abs(startVector.y))
            startScale = 0.5 / startSquareScale

            // Control points within the bounding box of the entire gradient.
            // Expressed as unit values with upper-left origin.
            //
            // 0,0
            // ********************** C1 **
            // *                          *
            // *                          *
            // *                          *
            // *                          *
            // *                          *
            // *                          *
            // ** C2 ********************** 1,1
            //
            let startPointGradientUnitsUL = unitCenter + startVector * +startScale
            // The endpoint should be "opposite" the start point,
            // on the opposite edge of the gradient.
            let endPointGradientUnitsUL = unitCenter + startVector * -startScale

            // Each message bubble renders a subsection of the gradient.
            // We need to convert the control points from the bounding box
            // of the gradient to the local unit coordinate space of this view.
            // The reference frame (bounding box of the entire gradient)
            // in local points.
            let referenceFrameLocalPoints = self.convert(referenceView.bounds, from: referenceView)
            // The reference frame (bounding box of the entire gradient)
            // in local unit coordinates.
            let referenceFrameLocalUnits = CGRect(x: referenceFrameLocalPoints.x.inverseLerp(bounds.minX, bounds.maxX),
                                                  y: referenceFrameLocalPoints.y.inverseLerp(bounds.minY, bounds.maxY),
                                                  width: referenceFrameLocalPoints.width / bounds.width,
                                                  height: referenceFrameLocalPoints.height / bounds.height)
            func convertFromGradientToLocal(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x.lerp(referenceFrameLocalUnits.minX, referenceFrameLocalUnits.maxX),
                        y: point.y.lerp(referenceFrameLocalUnits.minY, referenceFrameLocalUnits.maxY))
            }
            // Control points within the local UIView viewport.
            // Expressed as unit values with upper-left origin.
            //
            // ********************** C1 **
            // *                          *
            // *            0,0           *
            // *            ********      *
            // *            *      *      *
            // *            ******** 1,1  *
            // *                          *
            // ** C2 **********************
            //
            let startPointViewportUnitsUL = convertFromGradientToLocal(startPointGradientUnitsUL)
            let endPointViewportUnitsUL = convertFromGradientToLocal(endPointGradientUnitsUL)

            // UIKit/UIView uses an upper-left origin.
            // Core Graphics/CALayer uses a lower-left origin.
            func convertToLayerUnit(_ point: CGPoint) -> CGPoint {
                // TODO: The documentation clearly indicates that
                // CAGradientLayer.startPoint and endPoint use the layer's
                // coordinate space with lower-left origin.  But the
                // observed behavior is that they use an upper-left origin.
                // I can't figure out why.
                if false {
                    return CGPoint(x: point.x, y: (1 - point.y))
                } else {
                    return point
                }
            }
            // Control points within the local CALayer viewport.
            // Expressed as unit values with lower-left origin.
            //
            // ********************** C1 **
            // *                          *
            // *                          *
            // *            ******** 1,1  *
            // *            *      *      *
            // *        0,0 ********      *
            // *                          *
            // ** C2 **********************
            //
            let startPointLayerUnitsLL = convertToLayerUnit(startPointViewportUnitsUL)
            let endPointLayerUnitsLL = convertToLayerUnit(endPointViewportUnitsUL)

            gradientLayer.startPoint = startPointLayerUnitsLL
            gradientLayer.endPoint = endPointLayerUnitsLL
        }

        CATransaction.commit()
    }

    public override func reset() {
        super.reset()

        self.referenceView = nil
        self.chatColor = nil
        self.backgroundColor = nil
        gradientLayer.removeFromSuperlayer()
    }
}
