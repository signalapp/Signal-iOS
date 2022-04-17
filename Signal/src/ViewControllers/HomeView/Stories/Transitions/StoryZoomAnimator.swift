//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

struct StoryTransitionContext {
    let isPresenting: Bool
    let thumbnailView: UIView
    let storyView: UIView
    let thumbnailRepresentsStoryView: Bool
    weak var pageViewController: StoryPageViewController!
}

class StoryZoomAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let context: StoryTransitionContext
    private let backgroundView = UIView()

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
        var presentedFrame = transitionContext.finalFrame(for: toVC)

        let heightScalar = UIDevice.current.isIPad
            ? UIDevice.current.orientation.isLandscape ? 0.75 : 0.65
            : 1

        let maxHeight = presentedFrame.height * heightScalar
        presentedFrame.size.height = min(maxHeight, presentedFrame.width * (16 / 9))
        presentedFrame.size.width = presentedFrame.height * (9 / 16)

        if UIDevice.current.isIPad {
            // Center in view
            presentedFrame.origin = CGPoint(
                x: containerView.safeAreaLayoutGuide.layoutFrame.midX - (presentedFrame.width / 2),
                y: containerView.safeAreaLayoutGuide.layoutFrame.midY - (presentedFrame.height / 2)
            )
        } else {
            // Pin to top of view
            presentedFrame.origin.y = containerView.safeAreaInsets.top
        }

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
            containerView.addSubview(backgroundView)
            containerView.addSubview(context.storyView)
            containerView.addSubview(context.pageViewController.view)

            context.storyView.layer.cornerRadius = UIDevice.current.hasIPhoneXNotch || UIDevice.current.isIPad ? 18 : 0
            context.storyView.frame = presentedFrame
            if let storyView = context.storyView as? TextAttachmentThumbnailView {
                storyView.renderSize = presentedFrame.size
            }
            context.storyView.layoutIfNeeded()

            context.thumbnailView.alpha = 0

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
