//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

// ManualStackView (like ManualLayoutView) uses a CATransformLayer
// by default.  CATransformLayer does not render.
//
// If you need to use properties like backgroundColor, border,
// masksToBounds, shadow, etc. you should use this subclass instead.
//
// See: https://developer.apple.com/documentation/quartzcore/catransformlayer
open class ManualStackViewWithLayer: ManualStackView {
    override open class var layerClass: AnyClass {
        CALayer.self
    }
}

// MARK: -

open class ManualStackView: ManualLayoutView {

    public typealias Measurement = ManualStackMeasurement

    private var arrangedSubviews = [UIView]()

    public var measurement: Measurement?

    public required init(name: String, arrangedSubviews: [UIView] = []) {
        super.init(name: name)

        addArrangedSubviews(arrangedSubviews)
    }

    @available(*, unavailable, message: "use other constructor instead.")
    public required init(name: String) {
        fatalError("init(name:) has not been implemented")
    }

    // MARK: - Config

    public var axis: NSLayoutConstraint.Axis = .horizontal
    public var alignment: UIStackView.Alignment = .center
    public var spacing: CGFloat = 0

    public typealias Config = OWSStackView.Config

    public func apply(config: Config) {
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

    public var asConfig: Config {
        Config(axis: self.axis,
               alignment: self.alignment,
               spacing: self.spacing,
               layoutMargins: self.layoutMargins)
    }

    // MARK: - Arrangement

    private struct ArrangementItem {
        let subview: UIView
        let frame: CGRect

        init(subview: UIView, frame: CGRect) {
            self.subview = subview
            self.frame = frame
        }

        func apply() {
            if subview.frame != frame {
                ManualLayoutView.setSubviewFrame(subview: subview, frame: frame)
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
    private var arrangement: Arrangement? {
        didSet {
            if arrangement != nil {
                invalidateIntrinsicContentSize()
                setNeedsLayout()
            }
        }
    }

    override func viewSizeDidChange() {
        invalidateArrangement()

        super.viewSizeDidChange()
    }

    public func invalidateArrangement() {
        arrangement = nil
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard !isHidden else {
            return .zero
        }
        guard let measurement = measurement else {
            owsFailDebug("Missing measurement: \(self.name).")
            return super.sizeThatFits(size)
        }
        return measurement.measuredSize
    }

    public override func addSubview(_ view: UIView) {
        owsAssertDebug(!subviews.contains(view))
        super.addSubview(view)
        invalidateArrangement()
    }

    // NOTE: This method does _NOT_ call the superclass implementation.
    public func addArrangedSubview(_ view: UIView) {
        addSubview(view)
        owsAssertDebug(!arrangedSubviews.contains(view))

        view.translatesAutoresizingMaskIntoConstraints = false

        arrangedSubviews.append(view)
    }

    func addArrangedSubviews(_ subviews: [UIView], reverseOrder: Bool = false) {
        var subviews = subviews
        if reverseOrder {
            subviews.reverse()
        }
        for subview in subviews {
            addArrangedSubview(subview)
        }
    }

    public override func willRemoveSubview(_ view: UIView) {
        arrangedSubviews = self.arrangedSubviews.filter { view != $0 }
        super.willRemoveSubview(view)
        invalidateArrangement()
    }

    public func removeArrangedSubview(_ view: UIView) {
        view.removeFromSuperview()

        arrangedSubviews = arrangedSubviews.filter { $0 != view }
    }

    public override func layoutSubviews() {
        AssertIsOnMainThread()

        // We apply the layout blocks _after_ the arrangement.
        super.layoutSubviews(skipLayoutBlocks: true)

        guard bounds.width > 0, bounds.height > 0 else {
            for subview in subviews {
                subview.frame = .zero
            }
            return
        }

        ensureArrangement()?.apply()

        applyLayoutBlocks()
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

    public func configureForReuse(config: Config, measurement: Measurement) {
        apply(config: config)
        self.measurement = measurement

        invalidateArrangement()

        layoutSubviews()
    }

    private func ensureArrangement() -> Arrangement? {
        if let arrangement = arrangement {
            return arrangement
        }
        guard let measurement = measurement else {
            owsFailDebug("\(name): Missing measurement.")
            return nil
        }
        // Ignore hidden subviews.
        let arrangedSubviews = self.arrangedSubviews.filter { !$0.isHidden }
        if arrangedSubviews.count > measurement.subviewInfos.count {
            owsFailDebug("\(name): arrangedSubviews: \(arrangedSubviews.count) != subviewInfos: \(measurement.subviewInfos.count)")
        }
        let isHorizontal = axis == .horizontal
        let count = min(arrangedSubviews.count, measurement.subviewInfos.count)
        // Build the list of subviews to layout and find their layout info.
        var layoutItems = [LayoutItem]()
        for index in 0..<count {
            guard let subview = arrangedSubviews[safe: index] else {
                owsFailDebug("\(name): Missing subview.")
                break
            }
            guard let subviewInfo = measurement.subviewInfos[safe: index] else {
                owsFailDebug("\(name): Missing measuredSize.")
                break
            }
            owsAssertDebug(!subview.isHidden)
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

        let isRTL: Bool
        switch semanticContentAttribute {
        case .forceLeftToRight, .spatial, .playback:
            isRTL = false
        case .forceRightToLeft:
            isRTL = true
        case .unspecified:
            isRTL = CurrentAppContext().isRTL
        @unknown default:
            isRTL = CurrentAppContext().isRTL
        }

        let isHorizontal = axis == .horizontal

        // If we're horizontal *and* RTL, we want to reverse the order
        // of the layout items so they layout from RTL instead of LTR.
        var layoutItems = layoutItems
        if isRTL, isHorizontal { layoutItems = layoutItems.reversed() }

        let layoutMargins = self.layoutMargins
        let layoutSize = (bounds.size - layoutMargins.totalSize).max(.zero)

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
        //
        // If a stack's contents do not fit within the stack's bounds, they "overflow".
        // If a stack's contents are smaller than the stack's bounds, they "underflow".
        let fuzzyTolerance: CGFloat = 0.001
        if abs(onAxisSizeTotal - onAxisMaxSize) < fuzzyTolerance {
            // Exact match; no adjustments necessary.
        } else if onAxisSizeTotal < onAxisMaxSize {
            // Underflow case
            //
            // Underflow is expected; a stack view is often larger than
            // the minimum size of its contents.  The stack view will
            // expand the layout of its contents to take advantage of
            // the extra space.
            let underflow = onAxisMaxSize - onAxisSizeTotal

            // TODO: We could weight re-distribution by contentHuggingPriority.
            var underflowLayoutItems = layoutItems.filter {
                $0.subviewInfo.canExpandOnAxis(isHorizontalLayout: isHorizontal)
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
            // Overflow case
            //
            // Overflow should be rare, at least in the conversation view cells.
            // It is expected in some cases, e.g. when animating an orientation
            // change when the new layout hasn't landed yet.
            let overflow = onAxisSizeTotal - onAxisMaxSize
            if DebugFlags.internalLogging {
                Logger.warn("\(name): overflow[\(name)]: \(overflow)")
            }

            // TODO: We could weight re-distribution by compressionResistence.
            var overflowLayoutItems = layoutItems.filter {
                $0.subviewInfo.canCompressOnAxis(isHorizontalLayout: isHorizontal)
            }
            if overflowLayoutItems.isEmpty {
                if DebugFlags.internalLogging {
                    Logger.warn("\(name): No overflowLayoutItems.")
                }
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
        for layoutItem in layoutItems {
            if layoutItem.offAxisMeasuredSize > offAxisMaxSize {
                Logger.verbose("\(name): Off-axis overflow: offAxisMeasuredSize: \(layoutItem.offAxisMeasuredSize) > offAxisMaxSize: \(offAxisMaxSize)")
            }
            var offAxisSize: CGFloat = min(layoutItem.offAxisMeasuredSize, offAxisMaxSize)
            if offAxisAlignment == .fill,
               layoutItem.subviewInfo.canExpandOffAxis(isHorizontalLayout: isHorizontal) {
                offAxisSize = offAxisMaxSize
            }
            layoutItem.offAxisSize = offAxisSize

            switch offAxisAlignment {
            case .minimum:
                layoutItem.offAxisLocation = 0
            case .maximum:
                layoutItem.offAxisLocation = offAxisMaxSize - offAxisSize
            case .center, .fill:
                layoutItem.offAxisLocation = (offAxisMaxSize - offAxisSize) * 0.5
            }
        }

        // Apply layoutMargins and locationOffset.
        for layoutItem in layoutItems {
            layoutItem.frame.x += layoutMargins.left + layoutItem.subviewInfo.locationOffset.x
            layoutItem.frame.y += layoutMargins.top + layoutItem.subviewInfo.locationOffset.y
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
            if isHorizontal {
                return measuredSize.width
            } else {
                return measuredSize.height
            }
        }

        var offAxisMeasuredSize: CGFloat {
            if isHorizontal {
                return measuredSize.height
            } else {
                return measuredSize.width
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

    public static func measure(config: Config,
                               subviewInfos: [ManualStackSubviewInfo],
                               verboseLogging: Bool = false) -> Measurement {

        let subviewSizes = subviewInfos.map { $0.measuredSize.max(.zero) }

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

        size.width += config.layoutMargins.totalWidth
        size.height += config.layoutMargins.totalHeight

        if verboseLogging {
            Logger.verbose("size of subviews and spacing and layoutMargins: \(size)")
        }

        size = size.ceil

        return Measurement(measuredSize: size, subviewInfos: subviewInfos)
    }

    open override func reset() {
        AssertIsOnMainThread()

        super.reset()

        alignment = .fill
        axis = .vertical
        spacing = 0

        self.measurement = nil
    }
}

// MARK: -

//// TODO: Can this be moved to UIView+OWS.swift?
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

// MARK: -

// Analogous to UIView.compressionResistence and .contentHugging.
//
// If a stack's contents do not fit within the stack's bounds, they "overflow".
// If a stack's contents are smaller than the stack's bounds, they "underflow".
public enum ManualFlowBehavior {
    case fixed
    case canExpand
    case canCompress
    case canExpandAndCompress

    var canExpand: Bool {
        switch self {
        case .fixed, .canCompress:
            return false
        case .canExpand, .canExpandAndCompress:
            return true
        }
    }

    var canCompress: Bool {
        switch self {
        case .fixed, .canExpand:
            return false
        case .canCompress, .canExpandAndCompress:
            return true
        }
    }
}

// MARK: -

public struct ManualStackSubviewInfo: Equatable {
    let measuredSize: CGSize

    let horizontalFlowBehavior: ManualFlowBehavior
    let verticalFlowBehavior: ManualFlowBehavior

    let locationOffset: CGPoint

    public init(measuredSize: CGSize,
                horizontalFlowBehavior: ManualFlowBehavior,
                verticalFlowBehavior: ManualFlowBehavior,
                locationOffset: CGPoint = .zero) {
        self.measuredSize = measuredSize
        self.horizontalFlowBehavior = horizontalFlowBehavior
        self.verticalFlowBehavior = verticalFlowBehavior
        self.locationOffset = locationOffset
    }

    public init(measuredSize: CGSize,
                hasFixedWidth: Bool = false,
                hasFixedHeight: Bool = false,
                locationOffset: CGPoint = .zero) {
        self.measuredSize = measuredSize
        self.horizontalFlowBehavior = hasFixedWidth ? .fixed : .canExpandAndCompress
        self.verticalFlowBehavior = hasFixedHeight ? .fixed : .canExpandAndCompress
        self.locationOffset = locationOffset
    }

    public init(measuredSize: CGSize,
                hasFixedSize: Bool,
                locationOffset: CGPoint = .zero) {
        self.measuredSize = measuredSize
        self.horizontalFlowBehavior = hasFixedSize ? .fixed : .canExpandAndCompress
        self.verticalFlowBehavior = hasFixedSize ? .fixed : .canExpandAndCompress
        self.locationOffset = locationOffset
    }

    public init(measuredSize: CGSize, subview: UIView) {
        self.measuredSize = measuredSize

        let hasFixedWidth = subview.contentHuggingPriority(for: .horizontal) != .defaultHigh
        let hasFixedHeight = subview.contentHuggingPriority(for: .vertical) != .defaultHigh
        self.horizontalFlowBehavior = hasFixedWidth ? .fixed : .canExpandAndCompress
        self.verticalFlowBehavior = hasFixedHeight ? .fixed : .canExpandAndCompress

        self.locationOffset = .zero
    }

    private static func setSubviewFrame(subview: UIView, frame: CGRect) {
        guard subview.frame != frame else {
            return
        }
        subview.frame = frame
    }

    public static var empty: ManualStackSubviewInfo {
        ManualStackSubviewInfo(measuredSize: .zero)
    }

    func canExpandOnAxis(isHorizontalLayout: Bool) -> Bool {
        (isHorizontalLayout ? horizontalFlowBehavior : verticalFlowBehavior).canExpand
    }

    func canCompressOnAxis(isHorizontalLayout: Bool) -> Bool {
        (isHorizontalLayout ? horizontalFlowBehavior : verticalFlowBehavior).canCompress
    }

    func canExpandOffAxis(isHorizontalLayout: Bool) -> Bool {
        (isHorizontalLayout ? verticalFlowBehavior : horizontalFlowBehavior).canExpand
    }

    func canCompressOffAxis(isHorizontalLayout: Bool) -> Bool {
        (isHorizontalLayout ? verticalFlowBehavior : horizontalFlowBehavior).canCompress
    }
}

// MARK: -

public extension CGSize {
    var asManualSubviewInfo: ManualStackSubviewInfo {
        ManualStackSubviewInfo(measuredSize: self)
    }

    func asManualSubviewInfo(hasFixedWidth: Bool = false,
                             hasFixedHeight: Bool = false,
                             locationOffset: CGPoint = .zero) -> ManualStackSubviewInfo {
        ManualStackSubviewInfo(measuredSize: self,
                               hasFixedWidth: hasFixedWidth,
                               hasFixedHeight: hasFixedHeight,
                               locationOffset: locationOffset)
    }

    func asManualSubviewInfo(hasFixedSize: Bool,
                             locationOffset: CGPoint = .zero) -> ManualStackSubviewInfo {
        ManualStackSubviewInfo(measuredSize: self,
                               hasFixedSize: hasFixedSize,
                               locationOffset: locationOffset)
    }

    func asManualSubviewInfo(horizontalFlowBehavior: ManualFlowBehavior,
                             verticalFlowBehavior: ManualFlowBehavior,
                             locationOffset: CGPoint = .zero) -> ManualStackSubviewInfo {
        ManualStackSubviewInfo(measuredSize: self,
                               horizontalFlowBehavior: horizontalFlowBehavior,
                               verticalFlowBehavior: verticalFlowBehavior,
                               locationOffset: locationOffset)
    }
}

// MARK: -

public struct ManualStackMeasurement: Equatable {
    public let measuredSize: CGSize

    fileprivate let subviewInfos: [ManualStackSubviewInfo]

    init(measuredSize: CGSize, subviewInfos: [ManualStackSubviewInfo]) {
        self.measuredSize =  measuredSize
        self.subviewInfos = subviewInfos
    }
    fileprivate var subviewMeasuredSizes: [CGSize] {
        subviewInfos.map { $0.measuredSize }
    }

    public static func build(measuredSize: CGSize) -> ManualStackMeasurement {
        ManualStackMeasurement(measuredSize: measuredSize, subviewInfos: [])
    }
}

// MARK: -

public extension ManualStackView {
    @discardableResult
    func configure(
        config: Config,
        subviews: [UIView],
        subviewInfos: [ManualStackSubviewInfo]
    ) -> Measurement {
        let measurement = ManualStackView.measure(config: config, subviewInfos: subviewInfos)
        self.configure(config: config, measurement: measurement, subviews: subviews)
        return measurement
    }
}
