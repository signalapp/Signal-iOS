//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

class MediaTransitionImageView: UIImageView {

    var shape: MediaViewShape = .rectangle(0) {
        willSet {
            guard layer.mask == nil, case .variableRoundedCorners(let roundedCorners) = newValue else { return }

            // Only use masking layer if desired appearance cannot be achieved
            // by modifying `CALayer.cornerRadius` and `CALayer.maskedCorners`,
            // ie there is more than one corner radius being used.
            // Prepare by setting up a masking layer that, once created, will be used exclusively.
            if roundedCorners.groupedNonZeroCorners().keys.count > 1 {
                let maskLayer = CAShapeLayer()
                updateMaskLayer(maskLayer)
                layer.mask = maskLayer
            }
        }
        didSet {
            // Layer needs to be updated on bounds/frame change if:
            // * shape is circle - corner radius is a function of layer's size.
            // * masking layer is being used.
            switch shape {
            case .circle: updateShapeOnBoundsChange = true
            default: updateShapeOnBoundsChange = layer.mask != nil
            }

            if !updateShapeOnBoundsChange {
                updateShape()
            }
        }
    }
    private var updateShapeOnBoundsChange = false

    override var bounds: CGRect {
        didSet {
            if updateShapeOnBoundsChange {
                updateShape()
            }
        }
    }

    override var frame: CGRect {
        didSet {
            if updateShapeOnBoundsChange {
                updateShape()
            }
        }
    }

    private func updateShape() {
        // If there is a masking layer - use that to create shape.
        // Masking layer would be created in `shape.willSet` for `variableRoundedCorners` case.
        if let maskLayer = layer.mask as? CAShapeLayer {
            layer.cornerRadius = 0
            layer.maskedCorners = .all

            // Unfortunately masking layer's path is not implicitly animatable.
            // The workaround is to grab animation attached to view's layer,
            // copy it and use for animating masking path.
            let maskAnimation: CABasicAnimation?
            if let animation = layer.animation(forKey: "bounds.size") as? CABasicAnimation {
                maskAnimation = animation.copy() as? CABasicAnimation
            } else {
                maskAnimation = nil
            }
            updateMaskLayer(maskLayer, using: maskAnimation)
            return
        }

        // No masking layer means simpler cases of corner rounding - use CALayer.cornerRadius.
        // Note that we don't try and find an attached animation because `CALayer.cornerRadius`
        // is an implicitly animatable property.
        switch shape {
        case .rectangle(let cornerRadius):
            layer.cornerRadius = cornerRadius
            if cornerRadius > 0 {
                // CoreAnimation doesn't properly animate transition from some rounded
                // corners to all rounded corners - change below would take affect immediately.
                // Luckily for us media is always animated from some (or all) rounded corners
                // to no rounded corners (and back) which means `maskedCorners` can stay whatever it was.
                layer.maskedCorners = .all
            }

        case .circle:
            layer.cornerRadius = 0.5 * min(layer.bounds.width, layer.bounds.height)
            layer.maskedCorners = .all

        case .variableRoundedCorners(let roundedCorners):
            let roundedCornersGroupedByRadius = roundedCorners.groupedNonZeroCorners()
            owsAssertBeta(roundedCornersGroupedByRadius.count == 1)
            guard let cornerInfo = roundedCornersGroupedByRadius.first else { return }
            layer.cornerRadius = cornerInfo.key
            layer.maskedCorners = cornerInfo.value
        }

    }

    private func updateMaskLayer(_ maskLayer: CAShapeLayer, using animation: CABasicAnimation? = nil) {
        maskLayer.frame = layer.bounds

        let roundedCorners: RoundedCorners = {
            switch shape {
            case .circle:
                return .all(0.5 * min(maskLayer.bounds.width, maskLayer.bounds.height))

            case .rectangle(let cornerRadius):
                return .all(cornerRadius)

            case .variableRoundedCorners(let roundedCorners):
                return roundedCorners
            }
        }()

        // Note that path must be constructed using the same method even if there are no rounded corners,
        // otherwise animation would be incorrect.
        let maskPath = UIBezierPath.roundedRect(
            maskLayer.bounds,
            topLeftRounding: roundedCorners.topLeft,
            topRightRounding: roundedCorners.topRight,
            bottomRightRounding: roundedCorners.bottomRight,
            bottomLeftRounding: roundedCorners.bottomLeft
        )

        if let animation {
            animation.keyPath = "path"
            animation.fromValue = maskLayer.path
            animation.toValue = maskPath.cgPath
            maskLayer.add(animation, forKey: "path")
            maskLayer.path = maskPath.cgPath
        } else {
            maskLayer.path = maskPath.cgPath
        }
    }
}

private extension RoundedCorners {

    func groupedNonZeroCorners() -> [CGFloat: CACornerMask] {
        var result = [CGFloat: CACornerMask]()
        let populateResult: (CGFloat, CACornerMask) -> Void = { cornerRadius, corner in
            guard cornerRadius > 0 else { return }
            if var cornerMask = result[cornerRadius] {
                cornerMask.insert(corner)
                result[cornerRadius] = cornerMask
            } else {
                result[cornerRadius] = [ corner ]
            }
        }
        populateResult(topLeft, .layerMinXMinYCorner)
        populateResult(topRight, .layerMaxXMinYCorner)
        populateResult(bottomRight, .layerMaxXMaxYCorner)
        populateResult(bottomLeft, .layerMinXMaxYCorner)
        return result
    }
}
