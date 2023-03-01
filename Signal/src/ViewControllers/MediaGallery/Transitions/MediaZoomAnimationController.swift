//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import UIKit

class MediaZoomAnimationController: NSObject {
    private let item: Media

    init(image: UIImage) {
        item = .image(image)
    }

    init(galleryItem: MediaGalleryItem) {
        item = .gallery(galleryItem)
    }
}

extension MediaZoomAnimationController: UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return kIsDebuggingMediaPresentationAnimations ? 2.5 : 0.25
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView

        guard let fromVC = transitionContext.viewController(forKey: .from) else {
            owsFailDebug("fromVC was unexpectedly nil")
            transitionContext.completeTransition(false)
            return
        }

        let fromContextProvider: MediaPresentationContextProvider
        switch fromVC {
        case let contextProvider as MediaPresentationContextProvider:
            fromContextProvider = contextProvider
        case let navController as UINavigationController:
            guard let contextProvider = navController.topViewController as? MediaPresentationContextProvider else {
                owsFailDebug("unexpected contextProvider: \(String(describing: navController.topViewController))")
                transitionContext.completeTransition(false)
                return
            }
            fromContextProvider = contextProvider
        case let splitViewController as ConversationSplitViewController:
            guard let contextProvider = splitViewController.topViewController as? MediaPresentationContextProvider else {
                owsFailDebug("unexpected contextProvider: \(String(describing: splitViewController.topViewController))")
                transitionContext.completeTransition(false)
                return
            }
            fromContextProvider = contextProvider
        case let memberActionSheet as MemberActionSheet:
            fromContextProvider = memberActionSheet
        default:
            owsFailDebug("unexpected fromVC: \(fromVC)")
            transitionContext.completeTransition(false)
            return
        }

        guard let fromMediaContext = fromContextProvider.mediaPresentationContext(item: item, in: containerView) else {
            owsFailDebug("fromPresentationContext was unexpectedly nil")
            transitionContext.completeTransition(false)
            return
        }

        guard let toVC = transitionContext.viewController(forKey: .to) else {
            owsFailDebug("toVC was unexpectedly nil")
            transitionContext.completeTransition(false)
            return
        }

        guard let toContextProvider = toVC as? MediaPresentationContextProvider else {
            owsFailDebug("toContext was unexpectedly nil")
            transitionContext.completeTransition(false)
            return
        }

        guard let toView = transitionContext.view(forKey: .to) else {
            owsFailDebug("toView was unexpectedly nil")
            transitionContext.completeTransition(false)
            return
        }
        containerView.addSubview(toView)
        toView.autoPinEdgesToSuperviewEdges()
        toView.layoutIfNeeded()

        guard let toMediaContext = toContextProvider.mediaPresentationContext(item: item, in: containerView) else {
            owsFailDebug("toPresentationContext was unexpectedly nil")
            transitionContext.completeTransition(false)
            return
        }

        guard let presentationImage = item.image else {
            owsFailDebug("presentationImage was unexpectedly nil")
            // Complete transition immediately.
            fromContextProvider.mediaWillPresent(fromContext: fromMediaContext)
            toContextProvider.mediaWillPresent(toContext: toMediaContext)
            DispatchQueue.main.async {
                fromContextProvider.mediaDidPresent(fromContext: fromMediaContext)
                toContextProvider.mediaDidPresent(toContext: toMediaContext)
                transitionContext.completeTransition(true)
            }
            return
        }

        let transitionView = MediaTransitionImageView(image: presentationImage)
        transitionView.contentMode = .scaleAspectFill
        transitionView.layer.masksToBounds = true
        transitionView.roundedCorners = fromMediaContext.roundedCorners
        transitionView.frame = fromMediaContext.presentationFrame
        containerView.addSubview(transitionView)

        let fromTransitionalOverlayView: UIView?
        if let (overlayView, overlayViewFrame) = fromContextProvider.snapshotOverlayView(in: containerView) {
            fromTransitionalOverlayView = overlayView
            containerView.addSubview(overlayView)
            overlayView.frame = overlayViewFrame
        } else {
            fromTransitionalOverlayView = nil
        }

        let toTransitionalOverlayView: UIView?
        if let (overlayView, overlayViewFrame) = toContextProvider.snapshotOverlayView(in: containerView) {
            toTransitionalOverlayView = overlayView
            containerView.addSubview(overlayView)
            overlayView.frame = overlayViewFrame
        } else {
            toTransitionalOverlayView = nil
        }

        // Because toggling `isHidden` causes UIStack view layouts to change, we instead toggle `alpha`
        fromTransitionalOverlayView?.alpha = 1.0
        fromMediaContext.mediaView.alpha = 0.0
        toView.alpha = 0.0
        toTransitionalOverlayView?.alpha = 0.0
        toMediaContext.mediaView.alpha = 0.0

        let duration = transitionDuration(using: transitionContext)

        fromContextProvider.mediaWillPresent(fromContext: fromMediaContext)
        toContextProvider.mediaWillPresent(toContext: toMediaContext)

        let animator = UIViewPropertyAnimator(duration: duration, springDamping: 0.77, springResponse: 0.3)
        animator.addAnimations {
            fromTransitionalOverlayView?.alpha = 0.0
            toView.alpha = 1.0
            toTransitionalOverlayView?.alpha = 1.0
            transitionView.roundedCorners = toMediaContext.roundedCorners
            transitionView.frame = toMediaContext.presentationFrame
        }
        animator.addCompletion { _ in
            fromContextProvider.mediaDidPresent(fromContext: fromMediaContext)
            toContextProvider.mediaDidPresent(toContext: toMediaContext)
            transitionView.removeFromSuperview()
            fromTransitionalOverlayView?.removeFromSuperview()
            toTransitionalOverlayView?.removeFromSuperview()

            toMediaContext.mediaView.alpha = 1.0
            fromMediaContext.mediaView.alpha = 1.0

            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
        animator.startAnimation()
    }
}
