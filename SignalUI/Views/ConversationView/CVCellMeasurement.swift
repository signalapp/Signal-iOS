//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

open class CVMeasurementObject: Equatable {

    public init() {}

    // MARK: - Equatable

    public static func == (lhs: CVMeasurementObject, rhs: CVMeasurementObject) -> Bool {
        true
    }
}

// CVCellMeasurement captures the measurement state from the load.
// This lets us pin cell views to their measured sizes.  This is
// necessary because some UIViews (like UIImageView) set up
// layout constraints based on their content that we want to override.
public struct CVCellMeasurement: Equatable {

    public typealias Measurement = ManualStackMeasurement
    public typealias ObjectType = CVMeasurementObject

    public let cellSize: CGSize

    private let sizes: [String: CGSize]
    private let values: [String: CGFloat]
    private let measurements: [String: Measurement]
    private let objects: [String: ObjectType]

    public class Builder {
        public var cellSize: CGSize = .zero

        private var sizes = [String: CGSize]()
        private var values = [String: CGFloat]()
        private var measurements = [String: Measurement]()
        private var objects = [String: ObjectType]()

        public init() {}

        public func build() -> CVCellMeasurement {
            CVCellMeasurement(cellSize: cellSize,
                              sizes: sizes,
                              values: values,
                              measurements: measurements,
                              objects: objects)
        }

        public func setSize(key: String, size: CGSize) {
            owsAssertDebug(sizes[key] == nil)

            sizes[key] = size
        }

        public func setValue(key: String, value: CGFloat) {
            owsAssertDebug(values[key] == nil)

            values[key] = value
        }

        public func getValue(key: String) -> CGFloat? {
            values[key]
        }

        public func setMeasurement(key: String, value: Measurement) {
            owsAssertDebug(measurements[key] == nil)

            measurements[key] = value
        }

        public func getMeasurement(key: String) -> Measurement? {
            measurements[key]
        }

        public func setObject(key: String, value: ObjectType) {
            owsAssertDebug(objects[key] == nil)

            objects[key] = value
        }

        public func getObject(key: String) -> CVMeasurementObject? {
            objects[key]
        }
    }

    public func size(key: String) -> CGSize? {
        sizes[key]
    }

    public func value(key: String) -> CGFloat? {
        values[key]
    }

    public func measurement(key: String) -> Measurement? {
        measurements[key]
    }

    public func object<T>(key: String) -> T? {
        guard let value = objects[key] else {
            return nil
        }
        guard let object = value as? T else {
            owsFailDebug("Missing object: \(key)")
            return nil
        }
        return object
    }

    public var debugDescription: String {
        "[cellSize: \(cellSize), sizes: \(sizes), values: \(values), measurements: \(measurements)]"
    }

    public func debugLog() {
        Logger.verbose("cellSize: \(cellSize)")
        Logger.verbose("sizes: \(sizes)")
        Logger.verbose("values: \(values)")
        Logger.verbose("measurements: \(measurements)")
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

    func configureForReuse(config: Config,
                           cellMeasurement: CVCellMeasurement,
                           measurementKey: String) {
        guard let measurement = cellMeasurement.measurement(key: measurementKey) else {
            owsFailDebug("Missing measurement.")
            return
        }
        configureForReuse(config: config, measurement: measurement)
    }

    static func measure(config: Config,
                        measurementBuilder: CVCellMeasurement.Builder,
                        measurementKey: String,
                        subviewInfos: [ManualStackSubviewInfo],
                        maxWidth: CGFloat? = nil,
                        verboseLogging: Bool = false) -> Measurement {
        let measurement = Self.measure(config: config,
                                       subviewInfos: subviewInfos,
                                       verboseLogging: verboseLogging)
        measurementBuilder.setMeasurement(key: measurementKey, value: measurement)
        if let maxWidth = maxWidth,
           measurement.measuredSize.width > maxWidth {
            #if DEBUG
            Logger.verbose("config: \(config)")
            for subviewInfo in subviewInfos {
                Logger.verbose("subviewInfo: \(subviewInfo.measuredSize)")
            }
            #endif
            owsFailDebug("\(measurementKey): measuredSize \(measurement.measuredSize) > maxWidth: \(maxWidth).")
        }
        return measurement
    }
}
