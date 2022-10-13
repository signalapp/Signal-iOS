//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol ResizingView: UIView {
    var contentOffset: CGPoint { get set }
    var contentSize: CGSize { get }
}

extension UIScrollView: ResizingView {}

public protocol ResizingScrollViewDelegate: AnyObject {
    var resizingViewMinimumHeight: CGFloat { get }
    var resizingViewMaximumHeight: CGFloat { get }
}

public class ResizingScrollView<ResizingViewType: ResizingView>: UIView, UIScrollViewDelegate {
    public weak var resizingView: ResizingViewType? {
        didSet {
            oldValue?.removeGestureRecognizer(gestureScrollView.panGestureRecognizer)
            resizingView?.addGestureRecognizer(gestureScrollView.panGestureRecognizer)
            refreshHeightConstraints()
        }
    }
    public weak var delegate: ResizingScrollViewDelegate? {
        didSet { refreshHeightConstraints() }
    }

    // We utilize this scroll view *only* for it's panGestureRecognizer. No
    // interaction happens with the scrollView directly, instead we translate
    // its movement onto the view that is being resized. Doing this allows us
    // to get all the properties around tracking, bouncing, and decelerating
    // of an actual scrollView in contexts that aren't achievable with a
    // scrollView directly.
    private let gestureScrollView = UIScrollView()
    private lazy var heightConstraint = gestureScrollView.autoSetDimension(.height, toSize: 0, relation: .lessThanOrEqual)

    public init() {
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        gestureScrollView.delegate = self

        addSubview(gestureScrollView)
        gestureScrollView.autoPinEdgesToSuperviewEdges()

        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            gestureScrollView.autoSetDimension(.height, toSize: .greatestFiniteMagnitude)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var current: State = .zero
    private struct State: Equatable {
        let minimumHeight: CGFloat
        let maximumHeight: CGFloat
        let contentSize: CGSize

        static var zero: Self { .init(minimumHeight: 0, maximumHeight: 0, contentSize: .zero) }
    }

    /// Call to notify the resizing scroll view that it's minimum and/or maximum
    /// bound has changed.
    public func refreshHeightConstraints() {
        guard let resizingView = resizingView, let delegate = delegate else { return }

        let new = State(
            minimumHeight: delegate.resizingViewMinimumHeight,
            maximumHeight: delegate.resizingViewMaximumHeight,
            contentSize: resizingView.contentSize
        )

        guard new.maximumHeight >= new.minimumHeight else {
            return owsFailDebug("Unexpectedly had a minimum height that is larger than the maximum height")
        }

        guard new.maximumHeight >= 0, new.minimumHeight >= 0 else {
            return owsFailDebug("Unexpectedly had a negative height value")
        }

        // Our minimum and maximum possible height could be changed at any
        // point by our delegate. When it does change, we need to adjust
        // the properties of the gestureScrollView to reflect that. For
        // example, the min/max bounds may change when a keyboard is
        // presented. It's the delegates responsibility to notify us
        // when this change occurs by calling `refreshHeightConstraints`,
        // but we also do our best to proactively update since doing so
        // should be cheap.
        guard new != current else { return }

        layoutIfNeeded()

        let currentHeight = gestureScrollView.height
        let currentOffset = gestureScrollView.contentOffset.y

        // The inset represents the difference between the min
        // and max sizes. When the scroll view's offset is less
        // than 0 (in the inset range) we're resizing the view.
        // When it's >= 0, we're scrolling the view.
        let newInset = new.maximumHeight - new.minimumHeight

        let newHeight: CGFloat
        if currentHeight >= new.minimumHeight && currentHeight <= new.maximumHeight {
            newHeight = currentHeight
        } else if currentHeight < new.minimumHeight {
            newHeight = new.minimumHeight
        } else if currentHeight > new.maximumHeight {
            newHeight = new.maximumHeight
        } else if new.maximumHeight > current.maximumHeight {
            // If the amount of space we can take up is growing,
            // grow to fill the new space.
            newHeight = min(currentHeight + (new.maximumHeight - current.maximumHeight), new.maximumHeight)
        } else {
            // If the amount of space we can take up is shrinking,
            // shrink to accommodate the new space.
            newHeight = max(currentHeight - (current.maximumHeight - new.maximumHeight), new.minimumHeight)
        }

        let newOffset: CGFloat
        if newHeight < new.maximumHeight {
            // If we're less than the maximum height, our
            // offset is always a representation of the
            // difference between the maximum height and
            // our current height.
            newOffset = newHeight - new.maximumHeight
        } else {
            // If we're above the maximum height, the offset
            // represents the current scroll position.
            newOffset = max(0, currentOffset)
        }

        heightConstraint.constant = newHeight

        gestureScrollView.contentSize = new.contentSize
        gestureScrollView.contentInset.top = newInset
        gestureScrollView.bounds.origin.y = newOffset

        current = new
    }

    public override func layoutSubviews() {
        refreshHeightConstraints()
        super.layoutSubviews()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        owsAssertDebug(gestureScrollView == scrollView)
        guard let resizingView = resizingView, let delegate = delegate else { return }

        // Whenever the gesture scrollView scrolls, we need to update:
        // * our height, which the resizing view will reference
        // * the offset of the resizing view.
        //
        // If our offset is less than 0, we're in the "inset" range.
        // This range represents the difference between the min and
        // max height and is the space in which we should resize rather
        // than scroll.
        //
        // If our offset is >=0, the view should always be the max height
        // and our offset can be directly translated to the resizing view.

        if scrollView.contentOffset.y < 0 {
            let difference = scrollView.contentInset.top + scrollView.contentOffset.y
            if difference < 0 {
                heightConstraint.constant = delegate.resizingViewMinimumHeight
                resizingView.contentOffset.y = difference
            } else {
                heightConstraint.constant = delegate.resizingViewMinimumHeight + difference
                resizingView.contentOffset = .zero
            }
        } else {
            heightConstraint.constant = delegate.resizingViewMaximumHeight
            resizingView.contentOffset = scrollView.contentOffset
        }
    }
}
