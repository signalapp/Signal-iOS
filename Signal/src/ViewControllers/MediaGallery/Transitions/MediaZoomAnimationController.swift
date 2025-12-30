//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
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
        return MediaPresentationContext.animationDuration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {

        let containerView = transitionContext.containerView

        // Bunch of check to ensure everything is set up for the animated transition.
        // If there's anything wrong the transition would complete without animation.

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

        // All is good, set up the view hieranchy and view animations.

        let backgroundView = UIView(frame: containerView.bounds)
        backgroundView.backgroundColor = fromMediaContext.backgroundColor
        backgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(backgroundView)

        // Sometimes the initial (from) or the final (to) media view is partially obscured
        // (by navigation bar at the top and by the bottom bar at the bottom).
        // To animate from one "viewport" to another we set up a clipping
        // view that will contain the transitional media view.
        let clippingView = UIView(frame: containerView.bounds)
        clippingView.clipsToBounds = true
        if let clippingAreaInsets = fromMediaContext.clippingAreaInsets {
            clippingView.frame = containerView.bounds.inset(by: clippingAreaInsets)
        }
        containerView.addSubview(clippingView)

        let transitionView = MediaTransitionImageView(image: presentationImage)
        transitionView.contentMode = .scaleAspectFill
        transitionView.layer.masksToBounds = true
        transitionView.shape = fromMediaContext.mediaViewShape
        transitionView.frame = clippingView.convert(fromMediaContext.presentationFrame, from: containerView)
        clippingView.addSubview(transitionView)

        // `toView` goes above the media view so that any toolbars the view might have show
        // over the media view.
        containerView.addSubview(toView)
        toView.alpha = 0
        toView.frame = containerView.bounds
        toView.autoPinEdgesToSuperviewEdges()
        toView.layoutIfNeeded()

        // Because toggling `isHidden` causes UIStack view layouts to change, we instead toggle `alpha`
        fromMediaContext.mediaView.alpha = 0.0
        toMediaContext.mediaView.alpha = 0.0

        fromContextProvider.mediaWillPresent(fromContext: fromMediaContext)
        toContextProvider.mediaWillPresent(toContext: toMediaContext)

        let duration = transitionDuration(using: transitionContext)
        let animator = UIViewPropertyAnimator(duration: duration, springDamping: 1, springResponse: 0.25)
        animator.addAnimations {
            if let clippingAreaInsets = toMediaContext.clippingAreaInsets {
                clippingView.frame = containerView.bounds.inset(by: clippingAreaInsets)
            } else {
                clippingView.frame = containerView.bounds
            }

            toView.alpha = 1.0
            transitionView.shape = toMediaContext.mediaViewShape
            transitionView.frame = clippingView.convert(toMediaContext.presentationFrame, from: containerView)
            backgroundView.backgroundColor = toMediaContext.backgroundColor
        }
        animator.addCompletion { _ in
            fromContextProvider.mediaDidPresent(fromContext: fromMediaContext)
            toContextProvider.mediaDidPresent(toContext: toMediaContext)

            // Show the actual media views first to prevent flash during transition cleanup
            toMediaContext.mediaView.alpha = 1.0
            fromMediaContext.mediaView.alpha = 1.0

            // Then remove transition views after media is visible
            clippingView.removeFromSuperview()
            backgroundView.removeFromSuperview()

            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
        animator.startAnimation()
    }
}
