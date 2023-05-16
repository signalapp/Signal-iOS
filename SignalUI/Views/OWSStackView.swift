//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

open class OWSStackView: UIStackView {

    public struct Config {
        public let axis: NSLayoutConstraint.Axis
        public let alignment: UIStackView.Alignment
        public let spacing: CGFloat
        public let layoutMargins: UIEdgeInsets

        public init(axis: NSLayoutConstraint.Axis,
                    alignment: UIStackView.Alignment,
                    spacing: CGFloat,
                    layoutMargins: UIEdgeInsets) {
            self.axis = axis
            self.alignment = alignment
            self.spacing = spacing
            self.layoutMargins = layoutMargins
        }

        public func withSpacing(_ spacing: CGFloat) -> Config {
            Config(axis: self.axis,
                   alignment: self.alignment,
                   spacing: spacing,
                   layoutMargins: self.layoutMargins)
        }

        public var debugDescription: String {
            let components: [String] = [
                "axis: \(axis)",
                "alignment: \(alignment)",
                "spacing: \(spacing)",
                "layoutMargins: \(layoutMargins)"
            ]
            return "[" + components.joined(separator: ", ") + "]"
        }
    }

    // MARK: -

    public typealias LayoutBlock = (UIView) -> Void

    public var layoutBlock: LayoutBlock?

    public required init(name: String, arrangedSubviews: [UIView] = []) {
        super.init(frame: .zero)

        for subview in arrangedSubviews {
            addArrangedSubview(subview)
        }

        #if TESTABLE_BUILD
        self.accessibilityLabel = name
        #endif
    }

    @available(*, unavailable, message: "use other constructor instead.")
    public required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        AssertIsOnMainThread()

        super.layoutSubviews()

        layoutBlock?(self)
    }

    open func reset() {
        alignment = .fill
        axis = .vertical
        spacing = 0
        isLayoutMarginsRelativeArrangement = false

        removeAllSubviews()

        layoutBlock = nil

        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

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
        let isLayoutMarginsRelativeArrangement = layoutMargins != .zero
        if self.isLayoutMarginsRelativeArrangement != isLayoutMarginsRelativeArrangement {
            self.isLayoutMarginsRelativeArrangement = isLayoutMarginsRelativeArrangement
        }
    }

    public var asConfig: Config {
        Config(axis: self.axis,
               alignment: self.alignment,
               spacing: self.spacing,
               layoutMargins: self.layoutMargins)
    }

    public typealias TapBlock = () -> Void
    private var tapBlock: TapBlock?

    public func addTapGesture(_ tapBlock: @escaping TapBlock) {
        owsAssertDebug(self.tapBlock == nil)

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
        self.tapBlock = tapBlock
    }

    @objc
    private func didTap() {
        owsAssertDebug(tapBlock != nil)

        tapBlock?()
    }
}

// MARK: -

extension NSLayoutConstraint.Axis: CustomStringConvertible {
    public var description: String {
        switch self {
        case .horizontal:
            return "horizontal"
        case .vertical:
            return "vertical"
        @unknown default:
            owsFailDebug("unexpected value: \(self.rawValue)")
            return "unknown"
        }
    }
}

// MARK: -

extension UIStackView.Alignment: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fill:
            return "fill"
        case .leading:
            return "leading"
        case .firstBaseline:
            return "firstBaseline"
        case .center:
            return "center"
        case .trailing:
            return "trailing"
        case .lastBaseline:
            return "lastBaseline"
        @unknown default:
            owsFailDebug("unexpected value: \(self.rawValue)")
            return "unknown"
        }
    }
}
