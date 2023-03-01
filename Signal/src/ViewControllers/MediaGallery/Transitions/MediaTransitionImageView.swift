//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

class MediaTransitionImageView: UIImageView {

    var roundedCorners: RoundedCorners = .none

    override var bounds: CGRect {
        get { super.bounds }
        set {
            super.bounds = newValue

            let maskAnimation: CABasicAnimation?
            if let animation = layer.animation(forKey: "bounds.size") as? CABasicAnimation {
                maskAnimation = animation.copy() as? CABasicAnimation
            } else {
                maskAnimation = nil
            }
            updateMask(using: maskAnimation)
        }
    }

    override var frame: CGRect {
        get { super.frame }
        set {
            super.frame = newValue

            let maskAnimation: CABasicAnimation?
            if let animation = layer.animation(forKey: "bounds.size") as? CABasicAnimation {
                maskAnimation = animation.copy() as? CABasicAnimation
            } else {
                maskAnimation = nil
            }
            updateMask(using: maskAnimation)
        }
    }

    private func updateMask(using animation: CABasicAnimation?) {
        let maskLayer: CAShapeLayer
        if let existingMaskLayer = layer.mask as? CAShapeLayer {
            maskLayer = existingMaskLayer
        } else {
            maskLayer = CAShapeLayer()
            layer.mask = maskLayer
        }

        maskLayer.frame = layer.bounds

        // Note that path must be constructed using the same method even if there are no rounded corners,
        // otherwise animation would be incorrect.
        let maskPath: UIBezierPath = {
            return UIBezierPath.roundedRect(
                maskLayer.bounds,
                topLeftRounding: roundedCorners.topLeft,
                topRightRounding: roundedCorners.topRight,
                bottomRightRounding: roundedCorners.bottomRight,
                bottomLeftRounding: roundedCorners.bottomLeft
            )
        }()
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
