//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public struct ManualStackSubviewInfo: Equatable {
    let measuredSize: CGSize
    let hasFixedWidth: Bool
    let hasFixedHeight: Bool

    public init(measuredSize: CGSize,
                hasFixedWidth: Bool = false,
                hasFixedHeight: Bool = false) {
        self.measuredSize = measuredSize
        self.hasFixedWidth = hasFixedWidth
        self.hasFixedHeight = hasFixedHeight
    }

    public init(measuredSize: CGSize, hasFixedSize: Bool) {
        self.measuredSize = measuredSize
        self.hasFixedWidth = hasFixedSize
        self.hasFixedHeight = hasFixedSize
    }

    public init(measuredSize: CGSize, subview: UIView) {
        self.measuredSize = measuredSize

        self.hasFixedWidth = subview.contentHuggingPriority(for: .horizontal) != .defaultHigh
        self.hasFixedHeight = subview.contentHuggingPriority(for: .vertical) != .defaultHigh
    }

    public static var empty: ManualStackSubviewInfo {
        ManualStackSubviewInfo(measuredSize: .zero)
    }

    func hasFixedSizeOnAxis(isHorizontalLayout: Bool) -> Bool {
        isHorizontalLayout ? hasFixedWidth : hasFixedHeight
    }

    func hasFixedSizeOffAxis(isHorizontalLayout: Bool) -> Bool {
        isHorizontalLayout ? hasFixedHeight : hasFixedWidth
    }
}

// MARK: -

public extension CGSize {
    var asManualSubviewInfo: ManualStackSubviewInfo {
        ManualStackSubviewInfo(measuredSize: self)
    }

    func asManualSubviewInfo(hasFixedWidth: Bool = false,
                             hasFixedHeight: Bool = false) -> ManualStackSubviewInfo {
        ManualStackSubviewInfo(measuredSize: self,
                               hasFixedWidth: hasFixedWidth,
                               hasFixedHeight: hasFixedHeight)
    }

    func asManualSubviewInfo(hasFixedSize: Bool) -> ManualStackSubviewInfo {
        ManualStackSubviewInfo(measuredSize: self, hasFixedSize: hasFixedSize)
    }
}

// MARK: -

public struct ManualStackMeasurement: Equatable {
    public let measuredSize: CGSize

    fileprivate let subviewInfos: [ManualStackSubviewInfo]

    fileprivate var subviewMeasuredSizes: [CGSize] {
        subviewInfos.map { $0.measuredSize }
    }

    public static func build(measuredSize: CGSize) -> ManualStackMeasurement {
        ManualStackMeasurement(measuredSize: measuredSize, subviewInfos: [])
    }
}

// MARK: -

@objc
open class ManualStackView: OWSStackView {

    public typealias Measurement = ManualStackMeasurement

    public var name: String { accessibilityLabel ?? "Unknown" }

    private var managedSubviews = [UIView]()

    public var measurement: Measurement?

    private var layoutBlocks = [LayoutBlock]()

    @objc
    public required init(name: String, arrangedSubviews: [UIView] = []) {
        super.init(name: name, arrangedSubviews: arrangedSubviews)

        translatesAutoresizingMaskIntoConstraints = false
    }

    private struct ArrangementItem {
        let subview: UIView
        let frame: CGRect

        func apply() {
            if subview.frame != frame {
                ManualStackView.setSubviewFrame(subview: subview, frame: frame)
            }
        }
    }

    private struct Arrangement {
        let items: [ArrangementItem]

        func apply() {
            for item in items {
                item.apply()
            }
        }
    }

    // We cache the resolved layout of the subviews.
    private var arrangement: Arrangement?

    public override var bounds: CGRect {
        didSet {
            if oldValue.size != bounds.size {
                invalidateArrangement()
            }
        }
    }

    public override var frame: CGRect {
        didSet {
            if oldValue.size != frame.size {
                invalidateArrangement()
            }
        }
    }

    public func invalidateArrangement() {
        arrangement = nil
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let measurement = measurement else {
            owsFailDebug("Missing measurement.")
            return .zero
        }
        return measurement.measuredSize
    }

    public override var intrinsicContentSize: CGSize {
        return sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    }

    @objc
    public override func addSubview(_ view: UIView) {
        owsAssertDebug(!subviews.contains(view))
        super.addSubview(view)
        invalidateArrangement()
    }

    // NOTE: This method does _NOT_ call the superclass implementation.
    @objc
    public override func addArrangedSubview(_ view: UIView) {
        addSubview(view)
        owsAssertDebug(!managedSubviews.contains(view))

        view.translatesAutoresizingMaskIntoConstraints = false

        managedSubviews.append(view)
    }

    @objc
    public override func willRemoveSubview(_ view: UIView) {
        managedSubviews = self.managedSubviews.filter { view != $0 }
        super.willRemoveSubview(view)
        invalidateArrangement()
    }

    @objc
    public override func removeArrangedSubview(_ view: UIView) {
        view.removeFromSuperview()
    }

    @objc
    public override func setNeedsLayout() {
        super.setNeedsLayout()
    }

    @objc
    public override func layoutSubviews() {
        AssertIsOnMainThread()

        super.layoutSubviews()

        ensureArrangement()?.apply()

        layoutBlock?(self)

        for layoutBlock in layoutBlocks {
            layoutBlock(self)
        }
    }

    public func configure(config: Config,
                          measurement: Measurement,
                          subviews: [UIView]) {
        owsAssertDebug(self.measurement == nil)

        apply(config: config)
        self.measurement = measurement
        for subview in subviews {
            addArrangedSubview(subview)
        }

        invalidateArrangement()
    }

    private func ensureArrangement() -> Arrangement? {
        if let arrangement = arrangement {
            return arrangement
        }
        guard let measurement = measurement else {
            owsFailDebug("\(name): Missing measurement.")
            return nil
        }
        if managedSubviews.count > measurement.subviewInfos.count {
            owsFailDebug("\(name): managedSubviews: \(managedSubviews.count) != subviewInfos: \(measurement.subviewInfos.count)")
        }
        let isHorizontal = axis == .horizontal
        let count = min(managedSubviews.count, measurement.subviewInfos.count)
        // Build the list of subviews to layout and find their layout info.
        var layoutItems = [LayoutItem]()
        for index in 0..<count {
            guard let subview = managedSubviews[safe: index] else {
                owsFailDebug("\(name): Missing subview.")
                break
            }
            guard let subviewInfo = measurement.subviewInfos[safe: index] else {
                owsFailDebug("\(name): Missing measuredSize.")
                break
            }
            guard !subview.isHidden else {
                // Ignore hidden subviews.
                continue
            }
            layoutItems.append(LayoutItem(subview: subview,
                                          subviewInfo: subviewInfo,
                                          isHorizontal: isHorizontal))
        }
        return buildArrangement(measurement: measurement, layoutItems: layoutItems)
    }

    // An alignment enum that can be used whether the layout axis
    // is horizontal or vertical.
    private enum OffAxisAlignment: CustomStringConvertible {
        case minimum, center, maximum, fill

        public var description: String {
            switch self {
            case .minimum:
                return ".minimum"
            case .center:
                return ".center"
            case .maximum:
                return ".maximum"
            case .fill:
                return ".fill"
            }
        }
    }

    private func buildArrangement(measurement: Measurement,
                                  layoutItems: [LayoutItem]) -> Arrangement {

        guard !layoutItems.isEmpty else {
            return Arrangement(items: [])
        }

        let isHorizontal = axis == .horizontal
        let layoutMargins = self.layoutMargins
        let layoutSize = (bounds.size - layoutMargins.totalSize).max(.zero)
        let isRTL = CurrentAppContext().isRTL

        let onAxisMaxSize: CGFloat
        let offAxisMaxSize: CGFloat
        var offAxisAlignment: OffAxisAlignment
        if isHorizontal {
            onAxisMaxSize = layoutSize.width
            offAxisMaxSize = layoutSize.height

            switch alignment {
            case .top:
                offAxisAlignment = .minimum
            case .center:
                offAxisAlignment = .center
            case .bottom:
                offAxisAlignment = .maximum
            case .fill:
                offAxisAlignment = .fill
            default:
                owsFailDebug("\(name): Invalid alignment: \(alignment.rawValue).")
                offAxisAlignment = .center
            }
        } else {
            onAxisMaxSize = layoutSize.height
            offAxisMaxSize = layoutSize.width

            switch alignment {
            case .leading:
                offAxisAlignment = isRTL ? .maximum : .minimum
            case .center:
                offAxisAlignment = .center
            case .trailing:
                offAxisAlignment = isRTL ? .minimum : .maximum
            case .fill:
                offAxisAlignment = .fill
            default:
                owsFailDebug("Invalid alignment: \(alignment.rawValue).")
                offAxisAlignment = .center
            }
        }

        // Initialize onAxisLocation.
        var onAxisSizeTotal: CGFloat = 0
        for (index, layoutItem) in layoutItems.enumerated() {
            if index > 0 {
                onAxisSizeTotal += spacing
            }
            layoutItem.onAxisSize = layoutItem.onAxisMeasuredSize
            onAxisSizeTotal += layoutItem.onAxisMeasuredSize
        }

        // Handle underflow and overflow.
        let fuzzyTolerance: CGFloat = 0.001
        if abs(onAxisSizeTotal - onAxisMaxSize) < fuzzyTolerance {
            // Exact match.
        } else if onAxisSizeTotal < onAxisMaxSize {
            let underflow = onAxisMaxSize - onAxisSizeTotal
            Logger.warn("\(name): underflow[\(name)]: \(underflow)")

            // TODO: This approach is pretty crude.
            // We could weight re-distribution by contentHuggingPriority.
            var underflowLayoutItems = layoutItems.filter {
                !$0.subviewInfo.hasFixedSizeOnAxis(isHorizontalLayout: isHorizontal)
            }
            if underflowLayoutItems.isEmpty {
                owsFailDebug("\(name): No underflowLayoutItems.")
                underflowLayoutItems = layoutItems
            }

            let adjustment = underflow / CGFloat(underflowLayoutItems.count)
            for layoutItem in underflowLayoutItems {
                layoutItem.onAxisSize = max(0, layoutItem.onAxisSize + adjustment)
            }
        } else if onAxisSizeTotal > onAxisMaxSize {
            let overflow = onAxisSizeTotal - onAxisMaxSize
            Logger.warn("\(name): overflow[\(name)]: \(overflow)")

            // TODO: This approach is pretty crude.
            // We could weight re-distribution by compressionResistence.
            var overflowLayoutItems = layoutItems.filter {
                !$0.subviewInfo.hasFixedSizeOnAxis(isHorizontalLayout: isHorizontal)
            }
            if overflowLayoutItems.isEmpty {
                owsFailDebug("\(name): No overflowLayoutItems.")
                overflowLayoutItems = layoutItems
            }

            let adjustment = overflow / CGFloat(overflowLayoutItems.count)
            for layoutItem in overflowLayoutItems {
                layoutItem.onAxisSize = max(0, layoutItem.onAxisSize - adjustment)
            }
        }

        // Determine onAxisLocation.
        var onAxisLocation: CGFloat = 0
        for layoutItem in layoutItems {
            layoutItem.onAxisLocation = onAxisLocation
            onAxisLocation += layoutItem.onAxisSize + spacing
        }

        // Determine offAxisSize and offAxisLocation.
        for (index, layoutItem) in layoutItems.enumerated() {
            if layoutItem.offAxisMeasuredSize > offAxisMaxSize {
                Logger.warn("\(name): Off-axis overflow: offAxisMeasuredSize: \(layoutItem.offAxisMeasuredSize) > offAxisMaxSize: \(offAxisMaxSize)")
            }
            var offAxisSize: CGFloat = min(layoutItem.offAxisMeasuredSize, offAxisMaxSize)
            if offAxisAlignment == .fill,
               !layoutItem.subviewInfo.hasFixedSizeOffAxis(isHorizontalLayout: isHorizontal) {
                offAxisSize = offAxisMaxSize
            }
            layoutItem.offAxisSize = offAxisSize

            switch offAxisAlignment {
            case .minimum, .fill:
                layoutItem.offAxisLocation = 0
            case .maximum:
                layoutItem.offAxisLocation = offAxisMaxSize - offAxisSize
            case .center:
                layoutItem.offAxisLocation = (offAxisMaxSize - offAxisSize) * 0.5
            }
        }

        // Apply layoutMargins.
        for layoutItem in layoutItems {
            layoutItem.frame.x += layoutMargins.left
            layoutItem.frame.y += layoutMargins.top
        }

        let arrangementItems = layoutItems.map { $0.asArrangementItem }
        return Arrangement(items: arrangementItems)
    }

    private class LayoutItem {
        let subview: UIView
        let subviewInfo: ManualStackSubviewInfo
        let isHorizontal: Bool
        var frame: CGRect = .zero

        var measuredSize: CGSize { subviewInfo.measuredSize }

        var onAxisMeasuredSize: CGFloat {
            get {
                if isHorizontal {
                    return measuredSize.width
                } else {
                    return measuredSize.height
                }
            }
        }

        var offAxisMeasuredSize: CGFloat {
            get {
                if isHorizontal {
                    return measuredSize.height
                } else {
                    return measuredSize.width
                }
            }
        }

        var onAxisSize: CGFloat {
            get {
                if isHorizontal {
                    return frame.width
                } else {
                    return frame.height
                }
            }
            set {
                if isHorizontal {
                    frame.width = newValue
                } else {
                    frame.height = newValue
                }
            }
        }

        var offAxisSize: CGFloat {
            get {
                if isHorizontal {
                    return frame.height
                } else {
                    return frame.width
                }
            }
            set {
                if isHorizontal {
                    frame.height = newValue
                } else {
                    frame.width = newValue
                }
            }
        }

        var onAxisLocation: CGFloat {
            get {
                if isHorizontal {
                    return frame.x
                } else {
                    return frame.y
                }
            }
            set {
                if isHorizontal {
                    frame.x = newValue
                } else {
                    frame.y = newValue
                }
            }
        }

        var offAxisLocation: CGFloat {
            get {
                if isHorizontal {
                    return frame.y
                } else {
                    return frame.x
                }
            }
            set {
                if isHorizontal {
                    frame.y = newValue
                } else {
                    frame.x = newValue
                }
            }
        }

        init(subview: UIView,
             subviewInfo: ManualStackSubviewInfo,
             isHorizontal: Bool) {

            self.subview = subview
            self.subviewInfo = subviewInfo
            self.isHorizontal = isHorizontal
        }

        var asArrangementItem: ArrangementItem {
            ArrangementItem(subview: subview, frame: frame)
        }
    }

    public static func measure(config: Config, subviewInfos: [ManualStackSubviewInfo]) -> Measurement {

        let subviewSizes = subviewInfos.map { $0.measuredSize.max(.zero) }

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

        size.width += config.layoutMargins.totalWidth
        size.height += config.layoutMargins.totalHeight

        size = size.ceil

        return Measurement(measuredSize: size, subviewInfos: subviewInfos)
    }

    open override func reset() {
        super.reset()

        self.measurement = nil
        self.layoutBlocks.removeAll()
    }

    // MARK: -

    public func addSubview(_ subview: UIView,
                           withLayoutBlock layoutBlock: @escaping LayoutBlock) {
        owsAssertDebug(subview.superview == nil)

        subview.translatesAutoresizingMaskIntoConstraints = false

        addSubview(subview)

        addLayoutBlock(layoutBlock)
    }

    public func addLayoutBlock(_ layoutBlock: @escaping LayoutBlock) {
        layoutBlocks.append(layoutBlock)
    }

    public func centerSubviewWithLayoutBlock(_ subview: UIView,
                                             onSiblingView siblingView: UIView,
                                             size: CGSize) {
        owsAssertDebug(subview.superview != nil)
        owsAssertDebug(subview.superview == siblingView.superview)

        subview.translatesAutoresizingMaskIntoConstraints = false

        addLayoutBlock { _ in
            guard let superview = subview.superview else {
                owsFailDebug("Missing superview.")
                return
            }
            owsAssertDebug(superview == siblingView.superview)

            let siblingCenter = superview.convert(siblingView.center,
                                                  from: siblingView.superview)
            let subviewFrame = CGRect(origin: CGPoint(x: siblingCenter.x - subview.width * 0.5,
                                                      y: siblingCenter.y - subview.height * 0.5),
                                      size: size)
            Self.setSubviewFrame(subview: subview, frame: subviewFrame)
        }
    }

    private static func setSubviewFrame(subview: UIView, frame: CGRect) {
        guard subview.frame != frame else {
            return
        }
        subview.frame = frame
        // TODO: Remove?
        subview.setNeedsLayout()
    }

    public func addSubviewToCenterOnSuperview(_ subview: UIView, size: CGSize) {
        owsAssertDebug(subview.superview == nil)

        addSubview(subview)

        centerSubviewOnSuperviewWithLayoutBlock(subview, size: size)
    }

    public func centerSubviewOnSuperviewWithLayoutBlock(_ subview: UIView, size: CGSize) {
        owsAssertDebug(subview.superview != nil)

        subview.translatesAutoresizingMaskIntoConstraints = false

        addLayoutBlock { _ in
            guard let superview = subview.superview else {
                owsFailDebug("Missing superview.")
                return
            }

            let superviewBounds = superview.bounds
            let subviewFrame = CGRect(origin: CGPoint(x: (superviewBounds.width - subview.width) * 0.5,
                                                      y: (superviewBounds.height - subview.height) * 0.5),
                                      size: size)
            Self.setSubviewFrame(subview: subview, frame: subviewFrame)
        }
    }

    public func addSubviewToFillSuperviewEdges(_ subview: UIView) {
        owsAssertDebug(subview.superview == nil)

        addSubview(subview)

        layoutSubviewToFillSuperviewBoundsWithLayoutBlock(subview)
    }

    public func layoutSubviewToFillSuperviewBoundsWithLayoutBlock(_ subview: UIView) {
        owsAssertDebug(subview.superview != nil)

        subview.translatesAutoresizingMaskIntoConstraints = false

        addLayoutBlock { _ in
            guard let superview = subview.superview else {
                owsFailDebug("Missing superview.")
                return
            }

            Self.setSubviewFrame(subview: subview, frame: superview.bounds)
        }
    }
}

// MARK: -

// TODO: Can this be moved to UIView+OWS.swift?
fileprivate extension CGRect {

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
