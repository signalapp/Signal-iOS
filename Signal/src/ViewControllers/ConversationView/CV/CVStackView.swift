//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public typealias CVStackViewConfig = OWSStackView.Config

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

// MARK: -

public extension ManualStackView {

    func configure(config: Config,
                   cellMeasurement: CVCellMeasurement,
                   measurementKey: String,
                   subviews: [UIView]) {
        guard let measurement = cellMeasurement.measurement(key: measurementKey) else {
            owsFailDebug("Missing measurement.")
            return
        }
        configure(config: config,
                  measurement: measurement,
                  subviews: subviews)
    }

    static func measure(config: Config,
                        measurementBuilder: CVCellMeasurement.Builder,
                        measurementKey: String,
                        subviewInfos: [ManualStackSubviewInfo]) -> Measurement {
        let measurement = Self.measure(config: config, subviewInfos: subviewInfos)
        measurementBuilder.setMeasurement(key: measurementKey, value: measurement)
        return measurement
    }
}
