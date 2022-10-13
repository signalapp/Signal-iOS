//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public typealias CVStackViewConfig = OWSStackView.Config

// MARK: -

public extension UIStackView {

    static func measure(config: CVStackViewConfig,
                        subviewSizes: [CGSize],
                        verboseLogging: Bool = false) -> CGSize {

        let spacingCount = max(0, subviewSizes.count - 1)

        var size = CGSize.zero
        switch config.axis {
        case .horizontal:
            size.width = subviewSizes.map { $0.width }.reduce(0, +)
            size.height = subviewSizes.map { $0.height }.reduce(0, max)

            if verboseLogging {
                Logger.verbose("size of subviews: \(size)")
            }

            size.width += CGFloat(spacingCount) * config.spacing

            if verboseLogging {
                Logger.verbose("size of subviews and spacing: \(size)")
            }
        case .vertical:
            size.width = subviewSizes.map { $0.width }.reduce(0, max)
            size.height = subviewSizes.map { $0.height }.reduce(0, +)

            if verboseLogging {
                Logger.verbose("size of subviews: \(size)")
            }

            size.height += CGFloat(spacingCount) * config.spacing

            if verboseLogging {
                Logger.verbose("size of subviews and spacing: \(size)")
            }
        @unknown default:
            owsFailDebug("Unknown axis: \(config.axis)")
        }

        size.width += config.layoutMargins.left + config.layoutMargins.right
        size.height += config.layoutMargins.top + config.layoutMargins.bottom

        if verboseLogging {
            Logger.verbose("size of subviews and spacing and layoutMargins: \(size)")
        }
        return size
    }

    func apply(config: CVStackViewConfig) {
        if self.axis != config.axis {
            self.axis = config.axis
        }
        if self.alignment != config.alignment {
            self.alignment = config.alignment
        }
        if self.spacing != config.spacing {
            self.spacing = config.spacing
        }
        if self.layoutMargins != config.layoutMargins {
            self.layoutMargins = config.layoutMargins
        }
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
