//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

/// Input accessory views always render at the full width of the window.
/// This wrapper allows resizing the accessory view to fit within its
/// presenting view.
@objc
class InputAccessoryViewWrapper: UIView {
    @objc
    var containerWidth: CGFloat = 0 {
        didSet {
            guard containerWidth != oldValue else { return }
            widthConstraint?.constant = containerWidth
        }
    }

    @objc
    var pinnedEdge: ALEdge = .trailing {
        didSet {
            assert(pinnedEdge == .leading || pinnedEdge == .trailing)

            guard pinnedEdge != oldValue else { return }

            edgeConstraint?.isActive = false
            edgeConstraint = wrappedView?.autoPinEdge(toSuperviewEdge: pinnedEdge)
        }
    }

    @objc
    weak var wrappedView: UIView? {
        didSet {
            guard oldValue != wrappedView else { return }

            oldValue?.removeFromSuperview()

            guard let wrappedView = wrappedView else { return }
            addSubview(wrappedView)
            wrappedView.autoPinHeightToSuperview()

            edgeConstraint = wrappedView.autoPinEdge(toSuperviewEdge: pinnedEdge)
            widthConstraint = wrappedView.autoSetDimension(.width, toSize: containerWidth)

            autoresizingMask = wrappedView.autoresizingMask

            invalidateIntrinsicContentSize()
        }
    }

    private var widthConstraint: NSLayoutConstraint?
    private var edgeConstraint: NSLayoutConstraint?

    override var intrinsicContentSize: CGSize {
        return wrappedView?.intrinsicContentSize ?? super.intrinsicContentSize
    }
}
