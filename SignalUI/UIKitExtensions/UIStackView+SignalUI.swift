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

    @discardableResult
    func addBackgroundView(withBackgroundColor backgroundColor: UIColor, cornerRadius: CGFloat = 0) -> UIView {
        let backgroundView = UIView(frame: bounds)
        backgroundView.backgroundColor = backgroundColor
        backgroundView.layer.cornerRadius = cornerRadius
        addSubview(backgroundView)
        sendSubviewToBack(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()
        return backgroundView
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
        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()
        sendSubviewToBack(backgroundView)
        return backgroundView
    }
}

public extension UIView {

    // This works around a UIStackView bug where hidden subviews sometimes re-appear.
    var isHiddenInStackView: Bool {
        get { isHidden }
        set {
            isHidden = newValue
            alpha = newValue ? 0 : 1
        }
    }
}
