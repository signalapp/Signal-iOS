//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import UIKit

class MediaDismissAnimationController: NSObject {
    private let item: Media
    public let interactionController: MediaInteractiveDismiss?

    var transitionView: UIView?
    var fromMediaFrame: CGRect?
    var pendingCompletion: (() -> Void)?

    init(galleryItem: MediaGalleryItem, interactionController: MediaInteractiveDismiss? = nil) {
        self.item = .gallery(galleryItem)
        self.interactionController = interactionController
    }

    init(image: UIImage, interactionController: MediaInteractiveDismiss? = nil) {
        self.item = .image(image)
        self.interactionController = interactionController
    }
}

extension MediaDismissAnimationController: UIViewControllerAnimatedTransitioning {
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

        let transitionView = UIImageView(image: presentationImage)
        transitionView.contentMode = .scaleAspectFill
        transitionView.layer.masksToBounds = true
        transitionView.layer.cornerRadius = fromMediaContext.cornerRadius
        self.transitionView = transitionView

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

        assert(toContextProvider.snapshotOverlayView(in: containerView) == nil)

        // Because toggling `isHidden` causes UIStack view layouts to change, we instead toggle `alpha`
        fromTransitionalOverlayView?.alpha = 1.0
        fromMediaContext.mediaView.alpha = 0.0
        toMediaContext?.mediaView.alpha = 0.0

        let duration = transitionDuration(using: transitionContext)

        let completion = {
            let destinationFrame: CGRect
            let destinationCornerRadius: CGFloat
            if transitionContext.transitionWasCancelled {
                destinationFrame = fromMediaContext.presentationFrame
                destinationCornerRadius = fromMediaContext.cornerRadius
            } else if let toMediaContext = toMediaContext {
                destinationFrame = toMediaContext.presentationFrame
                destinationCornerRadius = toMediaContext.cornerRadius
            } else {
                // `toMediaContext` can be nil if the target item is scrolled off of the
                // contextProvider's screen, so we synthesize a context to dismiss the item
                // off screen
                let offscreenFrame = fromMediaContext.presentationFrame.offsetBy(dx: 0, dy: fromMediaContext.presentationFrame.height)
                destinationFrame = offscreenFrame
                destinationCornerRadius = fromMediaContext.cornerRadius
            }

            UIView.animate(.promise,
                                  duration: duration,
                                  delay: 0.0,
                                  options: [.beginFromCurrentState, .curveEaseInOut]) {
                transitionView.frame = destinationFrame
                transitionView.layer.cornerRadius = destinationCornerRadius
            }.done { _ in
                fromTransitionalOverlayView?.removeFromSuperview()

                transitionView.removeFromSuperview()
                fromMediaContext.mediaView.alpha = 1.0
                toMediaContext?.mediaView.alpha = 1.0
                if transitionContext.transitionWasCancelled {
                    // the "to" view will be nil if we're doing a modal dismiss, in which case
                    // we wouldn't want to remove the toView.
                    transitionContext.view(forKey: .to)?.removeFromSuperview()
                } else {
                    assert(transitionContext.view(forKey: .from) != nil)
                    transitionContext.view(forKey: .from)?.removeFromSuperview()
                }

                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            }.done {
                fromContextProvider.mediaDidDismiss(fromContext: fromMediaContext)
                if let toMediaContext = toMediaContext {
                    toContextProvider.mediaDidDismiss(toContext: toMediaContext)
                }
            }
        }

        if transitionContext.isInteractive {
            self.pendingCompletion = completion
        } else {
            Logger.verbose("ran completion simultaneously for non-interactive transition")
            completion()
        }

        fromContextProvider.mediaWillDismiss(fromContext: fromMediaContext)
        if let toMediaContext = toMediaContext {
            toContextProvider.mediaWillDismiss(toContext: toMediaContext)
        }
        UIView.animate(.promise,
                       duration: duration,
                       delay: 0.0,
                       options: [.beginFromCurrentState, .curveEaseInOut]) {
                fromTransitionalOverlayView?.alpha = 0.0
                fromView.alpha = 0.0
        }.done { _ in
            guard let pendingCompletion = self.pendingCompletion else {
                Logger.verbose("pendingCompletion already ran by the time fadeout completed.")
                return
            }

            Logger.verbose("ran pendingCompletion after fadeout")
            self.pendingCompletion = nil
            pendingCompletion()
        }
    }
}

extension MediaDismissAnimationController: InteractiveDismissDelegate {
    func interactiveDismissDidBegin(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
    }

    func interactiveDismissUpdate(_ interactiveDismiss: UIPercentDrivenInteractiveTransition, didChangeTouchOffset offset: CGPoint) {
        guard let transitionView = transitionView else {
            // transition hasn't started yet.
            return
        }

        guard let fromMediaFrame = fromMediaFrame else {
            owsFailDebug("fromMediaFrame was unexpectedly nil")
            return
        }

        transitionView.center = fromMediaFrame.offsetBy(dx: offset.x, dy: offset.y).center
    }

    func interactiveDismissDidFinish(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
        if let pendingCompletion = pendingCompletion {
            Logger.verbose("interactive gesture started pendingCompletion during fadeout")
            self.pendingCompletion = nil
            pendingCompletion()
        }
    }

    func interactiveDismissDidCancel(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
    }
}
