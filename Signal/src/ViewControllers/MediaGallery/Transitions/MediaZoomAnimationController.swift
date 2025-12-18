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
        backgroundView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        containerView.addSubview(backgroundView)

        // Sometimes the media being opened isn't fully visible because of the scroll position
        // of the container the media is in (chat view, all media view). To preserve obscured area
        // a clipping view needs to be set up.
        let clippingView = UIView(frame: containerView.bounds)
        clippingView.clipsToBounds = true
        clippingView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        if let clippingAreaInsets = fromMediaContext.clippingAreaInsets, clippingAreaInsets.isNonEmpty {
            let maskLayer = CALayer()
            maskLayer.frame = clippingView.layer.bounds.inset(by: clippingAreaInsets)
            maskLayer.backgroundColor = UIColor.black.cgColor
            clippingView.layer.mask = maskLayer
        }
        containerView.addSubview(clippingView)

        let transitionView = MediaTransitionImageView(image: presentationImage)
        transitionView.contentMode = .scaleAspectFill
        transitionView.layer.masksToBounds = true
        transitionView.shape = fromMediaContext.mediaViewShape
        transitionView.frame = fromMediaContext.presentationFrame
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
        let animator = UIViewPropertyAnimator(duration: duration, springDamping: 1, springResponse: 0.3)
        animator.addAnimations {
            toView.alpha = 1.0
            transitionView.shape = toMediaContext.mediaViewShape
            transitionView.frame = toMediaContext.presentationFrame
            backgroundView.backgroundColor = toMediaContext.backgroundColor

            // TODO: this doesn't animate. fix it.
            if let clippingAreaInsets = toMediaContext.clippingAreaInsets, clippingAreaInsets.isNonEmpty {
                let maskLayer = CALayer()
                maskLayer.frame = clippingView.layer.bounds.inset(by: clippingAreaInsets)
                maskLayer.backgroundColor = UIColor.black.cgColor
                clippingView.layer.mask = maskLayer
            } else {
                clippingView.layer.mask = nil
            }
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
