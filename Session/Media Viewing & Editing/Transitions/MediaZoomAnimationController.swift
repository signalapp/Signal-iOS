// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

class MediaZoomAnimationController: NSObject {
    private let mediaItem: Media
    private let shouldBounce: Bool

    init(galleryItem: MediaGalleryViewModel.Item, shouldBounce: Bool = true) {
        self.mediaItem = .gallery(galleryItem)
        self.shouldBounce = shouldBounce
    }
}

extension MediaZoomAnimationController: UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.4
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView
        let fromContextProvider: MediaPresentationContextProvider
        let toContextProvider: MediaPresentationContextProvider

        guard let fromVC: UIViewController = transitionContext.viewController(forKey: .from) else {
            transitionContext.completeTransition(false)
            return
        }
        guard let toVC: UIViewController = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }

        switch fromVC {
            case let contextProvider as MediaPresentationContextProvider:
                fromContextProvider = contextProvider

            case let navController as UINavigationController:
                guard let contextProvider = navController.topViewController as? MediaPresentationContextProvider else {
                    transitionContext.completeTransition(false)
                    return
                }

                fromContextProvider = contextProvider

            default:
                transitionContext.completeTransition(false)
                return
        }

        switch toVC {
            case let contextProvider as MediaPresentationContextProvider:
                toContextProvider = contextProvider

            case let navController as UINavigationController:
                guard let contextProvider = navController.topViewController as? MediaPresentationContextProvider else {
                    transitionContext.completeTransition(false)
                    return
                }

                toContextProvider = contextProvider

            default:
                transitionContext.completeTransition(false)
                return
        }

        // 'view(forKey: .to)' will be nil when using this transition for a modal dismiss, in which
        // case we want to use the 'toVC.view' but need to ensure we add it back to it's original
        // parent afterwards so we don't break the view hierarchy
        //
        // Note: We *MUST* call 'layoutIfNeeded' prior to 'toContextProvider.mediaPresentationContext'
        // as the 'toContextProvider.mediaPresentationContext' is dependant on it having the correct
        // positioning (and the navBar sizing isn't correct until after layout)
        let toView: UIView = (transitionContext.view(forKey: .to) ?? toVC.view)
        let duration: CGFloat = transitionDuration(using: transitionContext)
        let oldToViewSuperview: UIView? = toView.superview
        toView.layoutIfNeeded()
        
        // If we can't retrieve the contextual info we need to perform the proper zoom animation then
        // just fade the destination in (otherwise the user would get stuck on a blank screen)
        guard
            let fromMediaContext: MediaPresentationContext = fromContextProvider.mediaPresentationContext(mediaItem: mediaItem, in: containerView),
            let toMediaContext: MediaPresentationContext = toContextProvider.mediaPresentationContext(mediaItem: mediaItem, in: containerView),
            let presentationImage: UIImage = mediaItem.image
        else {
            
            toView.frame = containerView.bounds
            toView.alpha = 0
            containerView.addSubview(toView)
            
            UIView.animate(
                withDuration: (duration / 2),
                delay: 0,
                options: .curveEaseInOut,
                animations: {
                    toView.alpha = 1
                },
                completion: { _ in
                    // Need to ensure we add the 'toView' back to it's old superview if it had one
                    oldToViewSuperview?.addSubview(toView)

                    transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
                }
            )
            return
        }

        fromMediaContext.mediaView.alpha = 0
        toMediaContext.mediaView.alpha = 0

        toView.frame = containerView.bounds
        toView.alpha = 0
        containerView.addSubview(toView)
        
        let transitionView: UIImageView = UIImageView(image: presentationImage)
        transitionView.frame = fromMediaContext.presentationFrame
        transitionView.contentMode = MediaView.contentMode
        transitionView.layer.masksToBounds = true
        transitionView.layer.cornerRadius = fromMediaContext.cornerRadius
        transitionView.layer.maskedCorners = fromMediaContext.cornerMask
        containerView.addSubview(transitionView)
        
        // Note: We need to do this after adding the 'transitionView' and insert it at the back
        // otherwise the screen can flicker since we have 'afterScreenUpdates: true' (if we use
        // 'afterScreenUpdates: false' then the 'fromMediaContext.mediaView' won't be hidden
        // during the transition)
        let fromSnapshotView: UIView = (fromVC.view.snapshotView(afterScreenUpdates: true) ?? UIView())
        containerView.insertSubview(fromSnapshotView, at: 0)

        let overshootPercentage: CGFloat = 0.15
        let overshootFrame: CGRect = (self.shouldBounce ?
            CGRect(
                x: (toMediaContext.presentationFrame.minX + ((toMediaContext.presentationFrame.minX - fromMediaContext.presentationFrame.minX) * overshootPercentage)),
                y: (toMediaContext.presentationFrame.minY + ((toMediaContext.presentationFrame.minY - fromMediaContext.presentationFrame.minY) * overshootPercentage)),
                width: (toMediaContext.presentationFrame.width + ((toMediaContext.presentationFrame.width - fromMediaContext.presentationFrame.width) * overshootPercentage)),
                height: (toMediaContext.presentationFrame.height + ((toMediaContext.presentationFrame.height - fromMediaContext.presentationFrame.height) * overshootPercentage))
            ) :
            toMediaContext.presentationFrame
        )

        // Add any UI elements which should appear above the media view
        let fromTransitionalOverlayView: UIView? = {
            guard let (overlayView, overlayViewFrame) = fromContextProvider.snapshotOverlayView(in: containerView) else {
                return nil
            }

            overlayView.frame = overlayViewFrame
            containerView.addSubview(overlayView)

            return overlayView
        }()
        let toTransitionalOverlayView: UIView? = {
            guard let (overlayView, overlayViewFrame) = toContextProvider.snapshotOverlayView(in: containerView) else {
                return nil
            }

            overlayView.alpha = 0
            overlayView.frame = overlayViewFrame
            containerView.addSubview(overlayView)

            return overlayView
        }()

        UIView.animate(
            withDuration: (duration / 2),
            delay: 0,
            options: .curveEaseOut,
            animations: {
                // Only fade out the 'fromTransitionalOverlayView' if it's bigger than the destination
                // one (makes it look cleaner as you don't get the crossfade effect)
                if (fromTransitionalOverlayView?.frame.size.height ?? 0) > (toTransitionalOverlayView?.frame.size.height ?? 0) {
                    fromTransitionalOverlayView?.alpha = 0
                }

                toView.alpha = 1
                toTransitionalOverlayView?.alpha = 1
                transitionView.frame = overshootFrame
                transitionView.layer.cornerRadius = toMediaContext.cornerRadius
            },
            completion: { _ in
                UIView.animate(
                    withDuration: (duration / 2),
                    delay: 0,
                    options: .curveEaseInOut,
                    animations: {
                        transitionView.frame = toMediaContext.presentationFrame
                    },
                    completion: { _ in
                        transitionView.removeFromSuperview()
                        fromSnapshotView.removeFromSuperview()
                        fromTransitionalOverlayView?.removeFromSuperview()
                        toTransitionalOverlayView?.removeFromSuperview()

                        toMediaContext.mediaView.alpha = 1
                        fromMediaContext.mediaView.alpha = 1

                        // Need to ensure we add the 'toView' back to it's old superview if it had one
                        oldToViewSuperview?.addSubview(toView)

                        transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
                    }
                )
            }
        )
    }
}
