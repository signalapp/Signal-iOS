//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class MediaZoomAnimationController: NSObject {
    private let galleryItem: MediaGalleryItem

    init(galleryItem: MediaGalleryItem) {
        self.galleryItem = galleryItem
    }
}

extension MediaZoomAnimationController: UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return kIsDebuggingMediaPresentationAnimations ? 1.5 : 0.15
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
        default:
            owsFailDebug("unexpected fromVC: \(fromVC)")
            transitionContext.completeTransition(false)
            return
        }

        guard let fromMediaContext = fromContextProvider.mediaPresentationContext(galleryItem: galleryItem, in: containerView) else {
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

        guard let toMediaContext = toContextProvider.mediaPresentationContext(galleryItem: galleryItem, in: containerView) else {
            owsFailDebug("toPresentationContext was unexpectedly nil")
            transitionContext.completeTransition(false)
            return
        }

        guard let presentationImage = galleryItem.attachmentStream.originalImage else {
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

        let transitionView = UIImageView(image: presentationImage)
        transitionView.contentMode = .scaleAspectFill
        transitionView.layer.masksToBounds = true
        transitionView.layer.cornerRadius = fromMediaContext.cornerRadius

        containerView.addSubview(transitionView)
        transitionView.frame = fromMediaContext.presentationFrame

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
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut],
            animations: {
                fromTransitionalOverlayView?.alpha = 0.0
                toView.alpha = 1.0
                toTransitionalOverlayView?.alpha = 1.0
                transitionView.frame = toMediaContext.presentationFrame
                transitionView.layer.cornerRadius = toMediaContext.cornerRadius
        },
            completion: { _ in
                fromContextProvider.mediaDidPresent(fromContext: fromMediaContext)
                toContextProvider.mediaDidPresent(toContext: toMediaContext)
                transitionView.removeFromSuperview()
                fromTransitionalOverlayView?.removeFromSuperview()
                toTransitionalOverlayView?.removeFromSuperview()

                toMediaContext.mediaView.alpha = 1.0
                fromMediaContext.mediaView.alpha = 1.0

                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        })
    }
}
