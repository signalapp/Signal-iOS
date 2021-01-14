//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public struct CVStackViewConfig {
    let axis: NSLayoutConstraint.Axis
    let alignment: UIStackView.Alignment
    let spacing: CGFloat
    let layoutMargins: UIEdgeInsets
}

// MARK: -

class CVStackView {

    public static func measure(config: CVStackViewConfig,
                               subviewSizes: [CGSize]) -> CGSize {

        let spacingCount = max(0, subviewSizes.count - 1)

        var size = CGSize.zero
        switch config.axis {
        case .horizontal:
            size.width = subviewSizes.map { $0.width }.reduce(0, +)
            size.height = subviewSizes.map { $0.height }.reduce(0, max)

            size.width += CGFloat(spacingCount) * config.spacing
        case .vertical:
            size.width = subviewSizes.map { $0.width }.reduce(0, max)
            size.height = subviewSizes.map { $0.height }.reduce(0, +)

            size.height += CGFloat(spacingCount) * config.spacing
        @unknown default:
            owsFailDebug("Unknown axis: \(config.axis)")
        }

        size.width += config.layoutMargins.left + config.layoutMargins.right
        size.height += config.layoutMargins.top + config.layoutMargins.bottom

        return size
    }
}

// MARK: -

// TODO: Can this be moved to UIView+OWS.swift?
public extension CGRect {

    var width: CGFloat {
        get {
            size.width
        }
        set {
            size.width = newValue
        }
    }

    var height: CGFloat {
        get {
            size.height
        }
        set {
            size.height = newValue
        }
    }
}
