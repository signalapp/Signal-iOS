//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol ConversationCollectionViewDelegate: AnyObject {

    func collectionViewWillChangeSize(from oldSize: CGSize, to size: CGSize)
    func collectionViewDidChangeSize(from oldSize: CGSize, to size: CGSize)
    func collectionViewWillAnimate()
    func collectionViewShouldRecognizeSimultaneously(with otherGestureRecognizer: UIGestureRecognizer) -> Bool
}

class ConversationCollectionView: UICollectionView {

    weak var layoutDelegate: ConversationCollectionViewDelegate?

    override var frame: CGRect {
        get { super.frame }
        set {
            AssertIsOnMainThread()
            guard newValue.width > 0, newValue.height > 0 else {
                // Ignore iOS Auto Layout's tendency to temporarily zero out the
                // frame of this view during the layout process.
                //
                // The conversation view has an invariant that the collection view
                // should always have a "reasonable" (correct width, non-zero height)
                // size.  This lets us manipulate scroll state at all times, especially
                // before the view has been presented for the first time.  This
                // invariant also saves us from needing all sorts of ugly and incomplete
                // hacks in the conversation view's code.
                return
            }
            let oldValue = frame
            let isChanging = oldValue.size != newValue.size
            if isChanging {
                layoutDelegate?.collectionViewWillChangeSize(from: oldValue.size, to: newValue.size)
            }
            super.frame = newValue
            if isChanging {
                layoutDelegate?.collectionViewDidChangeSize(from: oldValue.size, to: newValue.size)
            }
        }
    }

    override var bounds: CGRect {
        get { super.bounds }
        set {
            AssertIsOnMainThread()
            guard newValue.width > 0, newValue.height > 0 else {
                // Ignore iOS Auto Layout's tendency to temporarily zero out the
                // frame of this view during the layout process.
                //
                // The conversation view has an invariant that the collection view
                // should always have a "reasonable" (correct width, non-zero height)
                // size.  This lets us manipulate scroll state at all times, especially
                // before the view has been presented for the first time.  This
                // invariant also saves us from needing all sorts of ugly and incomplete
                // hacks in the conversation view's code.
                return
            }
            let oldValue = bounds
            let isChanging = oldValue.size != newValue.size
            if isChanging {
                layoutDelegate?.collectionViewWillChangeSize(from: oldValue.size, to: newValue.size)
            }
            super.bounds = newValue
            if isChanging {
                layoutDelegate?.collectionViewDidChangeSize(from: oldValue.size, to: newValue.size)
            }
        }
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        AssertIsOnMainThread()
        if animated {
            layoutDelegate?.collectionViewWillAnimate()
        }
        super.setContentOffset(contentOffset, animated: animated)
    }

    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set {
            AssertIsOnMainThread()
            if contentSize.height < 1, newValue.y <= 0 {
                // [UIScrollView _adjustContentOffsetIfNecessary] resets the content
                // offset to zero under a number of undocumented conditions.  We don't
                // want this behavior; we want fine-grained control over the default
                // scroll state of the message view.
                //
                // [UIScrollView _adjustContentOffsetIfNecessary] is called in
                // response to many different events; trying to prevent them all is
                // whack-a-mole.
                //
                // It's not safe to override [UIScrollView _adjustContentOffsetIfNecessary],
                // since its a private API.
                //
                // We can avoid the issue by simply ignoring attempt to reset the content
                // offset to zero before the collection view has determined its content size.
                return
            }
            super.contentOffset = newValue
        }
    }

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        if animated {
            layoutDelegate?.collectionViewWillAnimate()
        }
        super.scrollRectToVisible(rect, animated: animated)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        guard let layoutDelegate else { return false }
        return layoutDelegate.collectionViewShouldRecognizeSimultaneously(with: otherGestureRecognizer)
    }

    // MARK: CVC

    typealias CVCPerformBatchUpdatesBlock = () -> Void
    typealias CVCPerformBatchUpdatesCompletion = (Bool) -> Void

    func cvc_reloadData(animated: Bool, cvc: ConversationViewController) {
        AssertIsOnMainThread()

        cvc.layout.willReloadData()
        if animated {
            super.reloadData()
        } else {
            UIView.performWithoutAnimation {
                super.reloadData()
            }
        }
        cvc.layout.invalidateLayout()
        cvc.layout.didReloadData()
    }

    func cvc_performBatchUpdates(
        _ batchUpdates: @escaping CVCPerformBatchUpdatesBlock,
        completion: @escaping CVCPerformBatchUpdatesCompletion,
        animated: Bool,
        scrollContinuity: ScrollContinuity,
        lastKnownDistanceFromBottom: CGFloat?,
        cvc: ConversationViewController,
    ) {
        AssertIsOnMainThread()

        let updateBlock = {
            let layout = cvc.layout
            layout.willPerformBatchUpdates(
                scrollContinuity: scrollContinuity,
                lastKnownDistanceFromBottom: lastKnownDistanceFromBottom,
            )
            super.performBatchUpdates(batchUpdates) { (finished: Bool) in
                AssertIsOnMainThread()
                completion(finished)
            }
            layout.didPerformBatchUpdates()
        }

        if animated {
            updateBlock()
        } else {
            // Don't wrap in a zero-duration animation: that makes UIKit
            // recreate visible cells rather than reuse them.
            UIView.performWithoutAnimation(updateBlock)
        }
    }
}
