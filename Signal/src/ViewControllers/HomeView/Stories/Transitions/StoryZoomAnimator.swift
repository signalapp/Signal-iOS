//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

struct StoryTransitionContext {
    let isPresenting: Bool
    let thumbnailView: UIView
    let storyView: UIView
    let thumbnailRepresentsStoryView: Bool
    weak var pageViewController: StoryPageViewController!
    weak var interactiveGesture: UIPanGestureRecognizer?
}

class StoryZoomAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let context: StoryTransitionContext
    private let backgroundView = UIView()
    private var interactiveCompletion: (() -> Void)?

    init(storyTransitionContext: StoryTransitionContext) {
        self.context = storyTransitionContext
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { totalDuration }
    var totalDuration: TimeInterval { presentationDelay + presentationDuration + crossFadeDuration }
    var crossFadeDuration: TimeInterval { 0.1 }
    var presentationDelay: TimeInterval {
        if context.isPresenting {
            return context.thumbnailRepresentsStoryView ? 0 : crossFadeDuration
        } else {
            return crossFadeDuration
        }
    }
    var presentationDuration: TimeInterval { 0.2 }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView

        guard let toVC = transitionContext.viewController(forKey: .to) else {
            owsFailDebug("Missing toVC")
            transitionContext.completeTransition(false)
            return
        }

        let dismissedFrame = containerView.convert(
            context.thumbnailView.frame,
            from: context.thumbnailView.superview
        )
        let presentedFrame = mediaFrame(in: transitionContext.finalFrame(for: toVC), containerView: containerView)

        backgroundView.backgroundColor = .ows_black
        backgroundView.frame = transitionContext.finalFrame(for: toVC)

        toVC.view.frame = transitionContext.finalFrame(for: toVC)

        if context.isPresenting {
            containerView.addSubview(backgroundView)
            containerView.addSubview(context.storyView)
            containerView.addSubview(toVC.view)

            context.storyView.frame = dismissedFrame
            context.storyView.layoutIfNeeded()

            backgroundView.alpha = 0
            toVC.view.alpha = 0

            context.storyView.layer.cornerRadius = 12
            context.storyView.alpha = 0

            UIView.animateKeyframes(withDuration: totalDuration, delay: 0) {
                self.animateThumbnailFade()
                self.animatePresentation(delay: self.presentationDelay, endFrame: presentedFrame)
                self.animateChromeFade(delay: self.presentationDelay + self.presentationDuration)
            } completion: { _ in
                self.context.storyView.removeFromSuperview()
                self.context.thumbnailView.alpha = 1
                self.backgroundView.removeFromSuperview()
                transitionContext.completeTransition(true)
            }
        } else {
            containerView.addSubview(toVC.view)
            containerView.addSubview(context.storyView)
            containerView.addSubview(context.pageViewController.view)

            context.storyView.layer.cornerRadius = UIDevice.current.hasIPhoneXNotch || UIDevice.current.isIPad ? 18 : 0
            context.storyView.frame = presentedFrame
            if let storyView = context.storyView as? TextAttachmentThumbnailView {
                storyView.renderSize = presentedFrame.size
            }
            context.storyView.layoutIfNeeded()

            context.thumbnailView.alpha = 0

            if let interactiveGesture = context.interactiveGesture {
                interactiveGesture.addTarget(self, action: #selector(handlePan(_:)))

                UIView.animate(withDuration: totalDuration) {
                    self.context.pageViewController.view.backgroundColor = .clear
                }

                interactiveCompletion = {
                    if transitionContext.transitionWasCancelled {
                        self.animateCancelledInteractiveDismissal(
                            interactiveGesture: interactiveGesture
                        ) {
                            toVC.view.removeFromSuperview()
                            self.context.pageViewController.view.alpha = 1
                            self.context.thumbnailView.alpha = 1

                            transitionContext.completeTransition(false)
                        }
                    } else {
                        self.animateCompletedInteractiveDismissal(
                            endFrame: dismissedFrame,
                            interactiveGesture: interactiveGesture
                        ) {
                            self.context.storyView.removeFromSuperview()
                            self.backgroundView.removeFromSuperview()
                            self.context.pageViewController.view.removeFromSuperview()

                            transitionContext.completeTransition(true)
                        }
                    }
                }
            } else {
                containerView.insertSubview(backgroundView, aboveSubview: toVC.view)

                UIView.animateKeyframes(withDuration: totalDuration, delay: 0) {
                    self.animateChromeFade()
                    self.animatePresentation(delay: self.presentationDelay, endFrame: dismissedFrame)
                    self.animateThumbnailFade(delay: self.presentationDuration + self.crossFadeDuration)
                } completion: { _ in
                    self.context.storyView.removeFromSuperview()
                    self.backgroundView.removeFromSuperview()

                    if transitionContext.transitionWasCancelled {
                        toVC.view.removeFromSuperview()
                        self.context.pageViewController.view.alpha = 1
                        self.context.thumbnailView.alpha = 1
                    } else {
                        self.context.pageViewController.view.removeFromSuperview()
                    }

                    transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
                }
            }
        }
    }

    private func mediaFrame(in containerFrame: CGRect, containerView: UIView) -> CGRect {
        var mediaFrame = containerFrame

        let heightScalar = UIDevice.current.isIPad
            ? UIDevice.current.orientation.isLandscape ? 0.75 : 0.65
            : 1

        let maxHeight = mediaFrame.height * heightScalar
        mediaFrame.size.height = min(maxHeight, mediaFrame.width * (16 / 9))
        mediaFrame.size.width = mediaFrame.height * (9 / 16)

        if UIDevice.current.isIPad {
            // Center in view
            mediaFrame.origin = CGPoint(
                x: mediaFrame.origin.x + containerView.safeAreaLayoutGuide.layoutFrame.midX - (mediaFrame.width / 2),
                y: mediaFrame.origin.y + containerView.safeAreaLayoutGuide.layoutFrame.midY - (mediaFrame.height / 2)
            )
        } else {
            // Pin to top of view
            mediaFrame.origin.y += containerView.safeAreaInsets.top
        }

        return mediaFrame
    }

    @objc
    func handlePan(_ interactiveGesture: UIPanGestureRecognizer) {
        switch interactiveGesture.state {
        case .changed:
            let translation = interactiveGesture.translation(in: context.pageViewController.view)
            let translatedFrame = context.pageViewController.view.frame.offsetBy(dx: translation.x, dy: translation.y)
            context.pageViewController.currentContextViewController.view.center = translatedFrame.center
            context.storyView.frame = mediaFrame(in: translatedFrame, containerView: context.pageViewController.view)
        case .ended, .cancelled:
            interactiveCompletion?()
            interactiveCompletion = nil
            interactiveGesture.removeTarget(self, action: #selector(handlePan(_:)))
        default:
            break
        }
    }

    /// When finishing the interactive dismissal, we spring from the translated position to the final position
    private func animateCompletedInteractiveDismissal(
        endFrame: CGRect,
        interactiveGesture: UIPanGestureRecognizer,
        completion: @escaping () -> Void
    ) {
        context.pageViewController.view.alpha = 0

        let velocity = interactiveGesture.velocity(in: context.pageViewController.view)
        let averageVelocity = abs(velocity.x) + abs(velocity.y) / 2
        let translation = interactiveGesture.translation(in: context.pageViewController.view)
        let averageTranslation = abs(translation.x) + abs(translation.y) / 2
        let springVelocity = averageVelocity / averageTranslation

        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            usingSpringWithDamping: 0.98,
            initialSpringVelocity: springVelocity,
            options: .curveLinear
        ) {
            if let storyView = self.context.storyView as? TextAttachmentThumbnailView {
                storyView.renderSize = TextAttachmentThumbnailView.defaultRenderSize
            }
            self.context.storyView.layer.cornerRadius = 12
            self.context.storyView.frame = endFrame
            self.context.storyView.layoutIfNeeded()
        } completion: { _ in
            let duration = self.context.thumbnailRepresentsStoryView ? 0 : self.crossFadeDuration
            UIView.animate(withDuration: duration) {
                self.context.storyView.alpha = self.context.isPresenting ? 1 : 0
                self.context.thumbnailView.alpha = self.context.isPresenting ? 0 : 1
            } completion: { _ in
                completion()
            }
        }
    }

    /// When cancelling the interactive dismissal, we spring from the translated position to the original position
    private func animateCancelledInteractiveDismissal(
        interactiveGesture: UIPanGestureRecognizer,
        completion: @escaping () -> Void
    ) {
        context.storyView.removeFromSuperview()

        let velocity = interactiveGesture.velocity(in: context.pageViewController.view)
        let averageVelocity = abs(velocity.x) + abs(velocity.y) / 2
        let translation = interactiveGesture.translation(in: context.pageViewController.view)
        let averageTranslation = abs(translation.x) + abs(translation.y) / 2
        let springVelocity = averageVelocity / averageTranslation

        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            usingSpringWithDamping: 0.98,
            initialSpringVelocity: springVelocity,
            options: .curveLinear
        ) {
            self.context.pageViewController.currentContextViewController.view.frame = self.context.pageViewController.view.bounds
            self.context.pageViewController.view.backgroundColor = .black
        } completion: { _ in
            completion()
        }
    }

    /// Cross-fade the thumbnail on the stories list if it doesn't match the presented story
    private func animateThumbnailFade(delay: TimeInterval = 0) {
        let duration = context.thumbnailRepresentsStoryView ? 0 : crossFadeDuration
        UIView.addKeyframe(withRelativeStartTime: delay / totalDuration, relativeDuration: duration / totalDuration) {
            self.context.storyView.alpha = self.context.isPresenting ? 1 : 0
            self.context.thumbnailView.alpha = self.context.isPresenting ? 0 : 1
        }
    }

    /// Move the story to its final location
    private func animatePresentation(delay: TimeInterval = 0, endFrame: CGRect) {
        UIView.addKeyframe(withRelativeStartTime: delay / totalDuration, relativeDuration: presentationDuration / totalDuration) {
            if let storyView = self.context.storyView as? TextAttachmentThumbnailView {
                storyView.renderSize = self.context.isPresenting
                    ? endFrame.size : TextAttachmentThumbnailView.defaultRenderSize
            }
            self.context.storyView.layer.cornerRadius = self.context.isPresenting
                ? UIDevice.current.hasIPhoneXNotch || UIDevice.current.isIPad ? 18 : 0
                : 12
            self.context.storyView.frame = endFrame
            self.context.storyView.layoutIfNeeded()
            self.backgroundView.alpha = self.context.isPresenting ? 1 : 0
        }
    }

    /// Fade the UI chrome
    private func animateChromeFade(delay: TimeInterval = 0) {
        UIView.addKeyframe(withRelativeStartTime: delay / totalDuration, relativeDuration: crossFadeDuration / totalDuration) {
            self.context.pageViewController.view.alpha = self.context.isPresenting ? 1 : 0
        }
    }
}
