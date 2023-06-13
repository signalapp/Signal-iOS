//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

class MediaDismissAnimationController: NSObject {
    private let item: Media
    let interactionController: MediaInteractiveDismiss

    var transitionView: UIView?
    var fromMediaFrame: CGRect?
    var pendingCompletion: ((CGVector?) -> Void)?

    init(galleryItem: MediaGalleryItem, interactionController: MediaInteractiveDismiss) {
        self.item = .gallery(galleryItem)
        self.interactionController = interactionController
    }

    init(image: UIImage, interactionController: MediaInteractiveDismiss) {
        self.item = .image(image)
        self.interactionController = interactionController
    }
}

extension MediaDismissAnimationController: UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return kIsDebuggingMediaPresentationAnimations ? 2.5 : 0.25
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView
        let isTransitionInteractive = transitionContext.isInteractive

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
                owsFailDebug("unexpected context: \(String(describing: navController.topViewController))")
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
        self.fromMediaFrame = fromMediaContext.presentationFrame

        guard let toVC = transitionContext.viewController(forKey: .to) else {
            owsFailDebug("toVC was unexpectedly nil")
            transitionContext.completeTransition(false)
            return
        }

        // toView will be nil if doing a modal dismiss, in which case we don't want to add the view -
        // it's already in the view hierarchy, behind the VC we're dismissing.
        if let toView = transitionContext.view(forKey: .to) {
            containerView.insertSubview(toView, at: 0)
        }

        guard let fromView = transitionContext.view(forKey: .from) else {
            owsFailDebug("fromView was unexpectedly nil")
            transitionContext.completeTransition(false)
            return
        }

        let toContextProvider: MediaPresentationContextProvider
        switch toVC {
        case let contextProvider as MediaPresentationContextProvider:
            toContextProvider = contextProvider
        case let navController as UINavigationController:
            guard let contextProvider = navController.topViewController as? MediaPresentationContextProvider else {
                owsFailDebug("unexpected context: \(String(describing: navController.topViewController))")
                transitionContext.completeTransition(false)
                return
            }
            toContextProvider = contextProvider
        case let splitViewController as ConversationSplitViewController:
            guard let contextProvider = splitViewController.topViewController as? MediaPresentationContextProvider else {
                owsFailDebug("unexpected context: \(String(describing: splitViewController.topViewController))")
                transitionContext.completeTransition(false)
                return
            }
            toContextProvider = contextProvider
        default:
            owsFailDebug("unexpected toVC: \(toVC)")
            transitionContext.completeTransition(false)
            return
        }

        let toMediaContext = toContextProvider.mediaPresentationContext(item: item, in: containerView)

        guard let presentationImage = item.image else {
            owsFailDebug("presentationImage was unexpectedly nil")
            // Complete transition immediately.
            fromContextProvider.mediaWillPresent(fromContext: fromMediaContext)
            if let toMediaContext = toMediaContext {
                toContextProvider.mediaWillPresent(toContext: toMediaContext)
            }
            DispatchQueue.main.async {
                fromContextProvider.mediaDidPresent(fromContext: fromMediaContext)
                if let toMediaContext = toMediaContext {
                    toContextProvider.mediaDidPresent(toContext: toMediaContext)
                }
                transitionContext.completeTransition(true)
            }
            return
        }

        // Dims content underneath the media view while user is gragging the media around.
        let dimmerView: UIView?
        if isTransitionInteractive {
            let view = UIView(frame: containerView.bounds)
            view.alpha = 0
            view.backgroundColor = .ows_blackAlpha40
            containerView.addSubview(view)
            dimmerView = view
        } else {
            dimmerView = nil
        }

        let clippingView = UIView(frame: containerView.bounds)
        clippingView.clipsToBounds = true
        if let clippingAreaInsets = fromMediaContext.clippingAreaInsets, clippingAreaInsets.isNonEmpty {
            let maskLayer = CALayer()
            maskLayer.frame = clippingView.layer.bounds.inset(by: clippingAreaInsets)
            maskLayer.backgroundColor = UIColor.black.cgColor
            clippingView.layer.mask = maskLayer
        }
        containerView.addSubview(clippingView)

        // Can't do rounded corners and drop shadow at the same time,
        // so put image into a container view.
        let transitionView = UIView(frame: fromMediaContext.presentationFrame)
        transitionView.layer.shadowColor = UIColor.ows_blackAlpha20.cgColor
        transitionView.layer.shadowOffset = CGSize(width: 0, height: 32)
        transitionView.layer.shadowRadius = 48
        transitionView.layer.shadowOpacity = 0
        self.transitionView = transitionView
        clippingView.addSubview(transitionView)

        let imageView = MediaTransitionImageView(image: presentationImage)
        imageView.contentMode = .scaleAspectFill
        imageView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        imageView.layer.masksToBounds = true
        imageView.shape = fromMediaContext.mediaViewShape
        imageView.frame = transitionView.bounds
        transitionView.addSubview(imageView)

        let fromTransitionalOverlayView: UIView?
        if let (overlayView, overlayViewFrame) = fromContextProvider.snapshotOverlayView(in: containerView) {
            fromTransitionalOverlayView = overlayView
            containerView.addSubview(overlayView)
            overlayView.frame = overlayViewFrame
        } else {
            fromTransitionalOverlayView = nil
        }

        assert(toContextProvider.snapshotOverlayView(in: containerView) == nil)

        // Because toggling `isHidden` causes UIStack view layouts to change, we instead toggle `alpha`
        fromTransitionalOverlayView?.alpha = 1
        fromMediaContext.mediaView.alpha = 0
        toMediaContext?.mediaView.alpha = 0

        let duration = transitionDuration(using: transitionContext)

        let completion: (CGVector?) -> Void = { velocity in
            let destinationFrame: CGRect
            let destinationMediaViewShape: MediaViewShape
            if transitionContext.transitionWasCancelled {
                destinationFrame = fromMediaContext.presentationFrame
                destinationMediaViewShape = fromMediaContext.mediaViewShape
            } else if let toMediaContext {
                destinationFrame = toMediaContext.presentationFrame
                destinationMediaViewShape = toMediaContext.mediaViewShape
            } else {
                // `toMediaContext` can be nil if the target item is scrolled off of the
                // contextProvider's screen, so we synthesize a context to dismiss the item
                // off screen
                let offscreenFrame = fromMediaContext.presentationFrame.offsetBy(dx: 0, dy: fromMediaContext.presentationFrame.height)
                destinationFrame = offscreenFrame
                destinationMediaViewShape = fromMediaContext.mediaViewShape
            }

            if let clippingAreaInsets = toMediaContext?.clippingAreaInsets, clippingAreaInsets.isNonEmpty {
                let maskLayer = CALayer()
                maskLayer.frame = clippingView.layer.bounds.inset(by: clippingAreaInsets)
                maskLayer.backgroundColor = UIColor.black.cgColor
                clippingView.layer.mask = maskLayer
            }

            let animator = UIViewPropertyAnimator(
                duration: duration,
                springDamping: 1,
                springResponse: 0.3,
                initialVelocity: velocity ?? .zero
            )
            animator.addAnimations {
                if !transitionContext.transitionWasCancelled {
                    fromTransitionalOverlayView?.alpha = 0
                    fromView.alpha = 0
                    dimmerView?.alpha = 0
                }

                imageView.shape = destinationMediaViewShape
                transitionView.transform = .identity
                transitionView.bounds.size = destinationFrame.size
                transitionView.center = destinationFrame.center
                transitionView.layer.shadowOpacity = 0
            }
            animator.addCompletion { _ in
                fromTransitionalOverlayView?.removeFromSuperview()
                clippingView.removeFromSuperview()
                dimmerView?.removeFromSuperview()

                fromMediaContext.mediaView.alpha = 1
                toMediaContext?.mediaView.alpha = 1
                if transitionContext.transitionWasCancelled {
                    // the "to" view will be nil if we're doing a modal dismiss, in which case
                    // we wouldn't want to remove the toView.
                    transitionContext.view(forKey: .to)?.removeFromSuperview()
                } else {
                    assert(transitionContext.view(forKey: .from) != nil)
                    transitionContext.view(forKey: .from)?.removeFromSuperview()
                }

                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)

                DispatchQueue.main.async {
                    fromContextProvider.mediaDidDismiss(fromContext: fromMediaContext)
                    if let toMediaContext {
                        toContextProvider.mediaDidDismiss(toContext: toMediaContext)
                    }
                }
            }
            animator.startAnimation()
        }

        fromContextProvider.mediaWillDismiss(fromContext: fromMediaContext)
        if let toMediaContext = toMediaContext {
            toContextProvider.mediaWillDismiss(toContext: toMediaContext)
        }

        if isTransitionInteractive {
            self.pendingCompletion = completion

            // "animation end" state is the UI state when user drags the image around
            // and has exceeded distance threshold specified in MediaInteractiveDismiss.
            // UIKit will reverse the animation if user drags the image back to the starting point.
            UIView.animate(
                withDuration: duration,
                delay: 0,
                animations: {
                    fromTransitionalOverlayView?.alpha = 0
                    fromView.alpha = 0
                    dimmerView?.alpha = 1

                    transitionView.transform = .scale(0.8)
                    transitionView.layer.shadowOpacity = 1
                },
                completion: { _ in
                    guard let pendingCompletion = self.pendingCompletion else {
                        Logger.verbose("pendingCompletion already ran by the time fadeout completed.")
                        return
                    }

                    Logger.verbose("ran pendingCompletion after fadeout")
                    self.pendingCompletion = nil
                    pendingCompletion(nil)
                }
            )
        } else {
            Logger.verbose("ran completion simultaneously for non-interactive transition")
            completion(nil)
        }
    }
}

extension MediaDismissAnimationController: InteractiveDismissDelegate {
    func interactiveDismissDidBegin(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) { }

    func interactiveDismiss(
        _ interactiveDismiss: UIPercentDrivenInteractiveTransition,
        didChangeProgress progress: CGFloat,
        touchOffset offset: CGPoint
    ) {
        guard let transitionView else {
            // transition hasn't started yet.
            return
        }

        guard let fromMediaFrame else {
            owsFailDebug("fromMediaFrame was unexpectedly nil")
            return
        }

        transitionView.center = fromMediaFrame.offsetBy(dx: offset.x, dy: offset.y).center
    }

    func interactiveDismiss(
        _ interactiveDismiss: UIPercentDrivenInteractiveTransition,
        didFinishWithVelocity velocity: CGVector?
    ) {
        if let pendingCompletion {
            Logger.verbose("interactive gesture started pendingCompletion during fadeout")
            self.pendingCompletion = nil
            pendingCompletion(velocity)
        }
    }

    func interactiveDismissDidCancel(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) { }
}
