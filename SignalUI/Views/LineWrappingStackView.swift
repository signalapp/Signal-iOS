//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

/// Like a horizontal UIStackView, except if the elements do not fit
/// horizontally it "line wraps" elements to a new line, arranging within a line
/// in left-to-right fashion (regardless of RTL setting).
///
/// Note: I don't guarantee this will work perfectly for every imaginable use case.
/// I wrote it for some specific use case and tried to make it work in the general case,
/// but the combination of constraints one could apply are uncountable. If you reuse this
/// and find it breaks, fix it! You can use `LineWrappingStackViewTestController`
/// to quickly test and iterate.
///
/// One thing this class can't do is detect size changes in subviews. If you change the size,
/// call `setNeedsLayout()` on this view.
public class LineWrappingStackView: UIView {

    // MARK: - Configuration

    /// Horizontal spacing between elements
    public var spacing: CGFloat = 8 {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    /// Vertical spacing between lines
    var lineSpacing: CGFloat = 8 {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    // MARK: - Adding subviews

    public var arrangedSubviews: [UIView] { _arrangedSubviews.lazy.map(\.0) }

    private var _arrangedSubviews = [(UIView, [NSLayoutConstraint])]() {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    public func addArrangedSubview(_ subview: UIView, atIndex index: Int? = nil) {
        addSubview(subview)
        let constraints = [
            subview.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor),
            self.bottomAnchor.constraint(greaterThanOrEqualTo: subview.bottomAnchor),
        ]
        constraints[1].priority = .required
        constraints.forEach({ $0.isActive = true })
        if let index {
            _arrangedSubviews.insert((subview, constraints), at: index)
        } else {
            _arrangedSubviews.append((subview, constraints))
        }
    }

    public func removeArrangedSubview(_ subview: UIView) {
        subview.removeFromSuperview()
        _arrangedSubviews.removeAll(where: { _subview, constraints in
            if _subview === subview {
                constraints.forEach({ $0.isActive = false })
                return true
            } else {
                return false
            }
        })
    }

    // MARK: - Layout

    override public class var requiresConstraintBasedLayout: Bool { true }

    override public func layoutSubviews() {
        super.layoutSubviews()
        zip(arrangedSubviews.filter({ !$0.isHidden }), arrangedSubviewRects()).forEach {
            $0.frame = $1
        }
    }

    override public func updateConstraints() {
        super.updateConstraints()
        zip(arrangedSubviews.filter({ !$0.isHidden }), arrangedSubviewRects()).forEach {
            $0.frame = $1
        }
    }

    override public func sizeThatFits(_ size: CGSize) -> CGSize {
        return CGSize(
            width: bounds.width,
            height: arrangedSubviewRects().lazy.map(\.maxY).max() ?? 0,
        )
    }

    override public var intrinsicContentSize: CGSize {
        return sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
    }

    private func arrangedSubviewRects() -> [CGRect] {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        return arrangedSubviews
            .lazy
            .filter({ !$0.isHidden })
            .map { subview in
                // Bit of a hack to deal with a catch-22. Below, when we use systemLayoutSizeFitting,
                // if we use a high horizontal fitting priority we risk blowing away externally-set
                // constraints. If we use a low priority, we risk content that could overflow vertically
                // instead trying to stretch horizontally past this view's bounds. Unclear how to solve
                // this generally, but the thing typically capable of "overflowing" lines within itself,
                // UILabel, has a specific affordance for this we can take advantage of.
                (subview as? UILabel)?.preferredMaxLayoutWidth = bounds.width
                // Check what size the subview prefers to be, up to a full line width.
                let unconstrainedContentSize = subview.sizeThatFits(CGSize(
                    width: bounds.width,
                    height: CGFloat.greatestFiniteMagnitude,
                ))
                // Now apply constraints.
                var constrainedSize = subview.systemLayoutSizeFitting(
                    unconstrainedContentSize,
                    withHorizontalFittingPriority: .fittingSizeLevel,
                    verticalFittingPriority: .required,
                )
                // Do a second round content size calculation, now constrained by width
                // so individual views can overflow height.
                let constrainedContentSize = subview.sizeThatFits(CGSize(
                    width: constrainedSize.width,
                    height: CGFloat.greatestFiniteMagnitude,
                ))
                // And lastly check with constraints at the new height.
                constrainedSize = subview.systemLayoutSizeFitting(
                    constrainedContentSize,
                    withHorizontalFittingPriority: .fittingSizeLevel,
                    verticalFittingPriority: .defaultHigh,
                )

                var subviewWidth = min(bounds.width - x, constrainedSize.width)

                // If we don't fit in the line, wrap to the next line.
                // (Unless we are the first in this line, i.e. x=0)
                if x > 0, constrainedSize.width > (bounds.width - x) {
                    x = 0
                    y += rowHeight + lineSpacing
                    rowHeight = 0
                    subviewWidth = min(constrainedSize.width, bounds.width)
                }

                let frame = CGRect(x: x, y: y, width: subviewWidth, height: ceil(constrainedSize.height))
                x += subviewWidth + spacing
                rowHeight = max(rowHeight, ceil(constrainedSize.height))
                return frame
            }
    }
}
