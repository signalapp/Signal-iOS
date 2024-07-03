//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

public extension UIStackView {

    func addArrangedSubviews(_ subviews: [UIView]) {
        for subview in subviews {
            addArrangedSubview(subview)
        }
    }

    func removeArrangedSubviewsAfter(_ subview: UIView) {
        guard let subviewIndex = arrangedSubviews.firstIndex(of: subview) else { return }

        let viewsToRemove = arrangedSubviews.suffix(from: subviewIndex.advanced(by: 1))
        for view in viewsToRemove {
            removeArrangedSubview(view)
        }
    }

    func addHairline(with color: UIColor) {
        insertHairline(with: color, at: arrangedSubviews.count)
    }

    func insertHairline(with color: UIColor, at index: Int) {
        let hairlineView = UIView()
        hairlineView.backgroundColor = color
        hairlineView.autoSetDimension(.height, toSize: 1)
        insertArrangedSubview(hairlineView, at: index)
    }

    func addBackgroundView(_ backgroundView: UIView) {
        addSubview(backgroundView)
        sendSubviewToBack(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()
    }

    @discardableResult
    func addBackgroundView(withBackgroundColor backgroundColor: UIColor, cornerRadius: CGFloat = 0) -> UIView {
        let backgroundView = UIView(frame: bounds)
        backgroundView.backgroundColor = backgroundColor
        backgroundView.layer.cornerRadius = cornerRadius
        self.addBackgroundView(backgroundView)
        return backgroundView
    }

    /// Adds a `UIVisualEffectView` with a `UIBlurEffect` as a background to the view.
    /// - Parameters:
    ///   - blur: The blur effect style to use.
    ///   - accessibilityFallbackColor: An optional fallback color when the
    ///   system "Reduce Transparency" accessibility feature is enabled. If this
    ///   is not set, the system automatically calculates a color to use.
    ///   - cornerRadius: The corner radius the background view should have.
    /// - Returns: The background subview which has been added and pinned to the superview.
    @discardableResult
    func addBackgroundBlurView(
        blur: UIBlurEffect.Style,
        accessibilityFallbackColor: UIColor? = nil,
        cornerRadius: CGFloat = 0
    ) -> UIView {
        if
            UIAccessibility.isReduceTransparencyEnabled,
            let accessibilityFallbackColor
        {
            return self.addBackgroundView(
                withBackgroundColor: accessibilityFallbackColor,
                cornerRadius: cornerRadius
            )
        } else {
            let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: blur))
            self.addBackgroundView(blurEffectView)
            return blurEffectView
        }
    }

    @discardableResult
    func addBorderView(withColor color: UIColor, strokeWidth: CGFloat, cornerRadius: CGFloat = 0) -> UIView {
        let borderView = UIView(frame: bounds)
        borderView.isUserInteractionEnabled = false
        borderView.backgroundColor = .clear
        borderView.isOpaque = false
        borderView.layer.borderColor = color.cgColor
        borderView.layer.borderWidth = strokeWidth
        borderView.layer.cornerRadius = cornerRadius
        addSubview(borderView)
        borderView.autoPinEdgesToSuperviewEdges()
        return borderView
    }

    @discardableResult
    func addPillBackgroundView(backgroundColor: UIColor) -> UIView {
        let backgroundView = OWSLayerView.pillView()
        backgroundView.backgroundColor = backgroundColor
        self.addBackgroundView(backgroundView)
        return backgroundView
    }
}

public extension UIView {

    /// A Boolean value that determines whether the view is hidden while working
    /// around a UIStackView bug where hidden subviews sometimes re-appear.
    var isHiddenInStackView: Bool {
        get { isHidden }
        set {
            // Setting isHidden to true when already hidden can cause layout issues
            if isHidden != newValue {
                isHidden = newValue
            }
            alpha = newValue ? 0 : 1
        }
    }
}
