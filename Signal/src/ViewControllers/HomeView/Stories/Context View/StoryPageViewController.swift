//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalUI

protocol StoryPageViewControllerDataSource: AnyObject {
    func storyPageViewControllerAvailableContexts(_ storyPageViewController: StoryPageViewController) -> [StoryContext]
}

class StoryPageViewController: UIPageViewController {
    var currentContext: StoryContext {
        set {
            setViewControllers([StoryContextViewController(context: newValue, delegate: self)], direction: .forward, animated: false)
        }
        get { currentContextViewController.context }
    }
    var currentContextViewController: StoryContextViewController {
        viewControllers!.first as! StoryContextViewController
    }
    weak var contextDataSource: StoryPageViewControllerDataSource? {
        didSet { initiallyAvailableContexts = contextDataSource?.storyPageViewControllerAvailableContexts(self) ?? [currentContext] }
    }
    lazy var initiallyAvailableContexts: [StoryContext] = [currentContext]
    private var interactiveDismissCoordinator: InteractiveDismissCoordinator?

    required init(context: StoryContext) {
        super.init(transitionStyle: .scroll, navigationOrientation: .vertical, options: nil)
        self.currentContext = context
        modalPresentationStyle = .fullScreen
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { !UIDevice.current.hasIPhoneXNotch && !UIDevice.current.isIPad }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.isIPad ? .all : .portrait
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        delegate = self
        view.backgroundColor = .black

        interactiveDismissCoordinator = InteractiveDismissCoordinator(pageViewController: self)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // For now, the design only allows for portrait layout on non-iPads
        if !UIDevice.current.isIPad && CurrentAppContext().interfaceOrientation != .portrait {
            UIDevice.current.ows_setOrientation(.portrait)
        }
    }

    private var displayLink: CADisplayLink?
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let displayLink = displayLink {
            displayLink.isPaused = false
        } else {
            let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkStep))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        displayLink?.isPaused = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if isBeingDismissed {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    @objc
    func displayLinkStep(_ displayLink: CADisplayLink) {
        currentContextViewController.displayLinkStep(displayLink)
    }
}

extension StoryPageViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        pendingViewControllers
            .lazy
            .map { $0 as! StoryContextViewController }
            .forEach { $0.resetForPresentation() }
    }
}

extension StoryPageViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let contextBefore = previousStoryContext else { return nil }
        return StoryContextViewController(context: contextBefore, delegate: self)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let contextAfter = nextStoryContext else { return nil }
        return StoryContextViewController(context: contextAfter, delegate: self)
    }
}

extension StoryPageViewController: StoryContextViewControllerDelegate {
    var availableContexts: [StoryContext] {
        guard let contextDataSource = contextDataSource else { return initiallyAvailableContexts }
        let availableContexts = contextDataSource.storyPageViewControllerAvailableContexts(self)
        return initiallyAvailableContexts.filter { availableContexts.contains($0) }
    }

    var previousStoryContext: StoryContext? {
        guard let contextIndex = availableContexts.firstIndex(of: currentContext),
              let contextBefore = availableContexts[safe: contextIndex.advanced(by: -1)] else {
            return nil
        }
        return contextBefore
    }

    var nextStoryContext: StoryContext? {
        guard let contextIndex = availableContexts.firstIndex(of: currentContext),
              let contextAfter = availableContexts[safe: contextIndex.advanced(by: 1)] else {
            return nil
        }
        return contextAfter
    }

    func storyContextViewControllerWantsTransitionToNextContext(
        _ storyContextViewController: StoryContextViewController,
        loadPositionIfRead: StoryContextViewController.LoadPosition
    ) {
        guard let nextContext = nextStoryContext else {
            dismiss(animated: true)
            return
        }
        setViewControllers(
            [StoryContextViewController(context: nextContext, loadPositionIfRead: loadPositionIfRead, delegate: self)],
            direction: .forward,
            animated: true
        )
    }

    func storyContextViewControllerWantsTransitionToPreviousContext(
        _ storyContextViewController: StoryContextViewController,
        loadPositionIfRead: StoryContextViewController.LoadPosition
    ) {
        guard let previousContext = previousStoryContext else {
            storyContextViewController.resetForPresentation()
            return
        }
        setViewControllers(
            [StoryContextViewController(context: previousContext, loadPositionIfRead: loadPositionIfRead, delegate: self)],
            direction: .reverse,
            animated: true
        )
    }

    func pause() { displayLink?.isPaused = true }
    func resume() { displayLink?.isPaused = false }

    func storyContextViewControllerDidPause(_ storyContextViewController: StoryContextViewController) {
        pause()
    }

    func storyContextViewControllerDidResume(_ storyContextViewController: StoryContextViewController) {
        resume()
    }
}

extension StoryPageViewController: UIViewControllerTransitioningDelegate {
    public func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        guard let storyTransitionContext = try? storyTransitionContext(
            presentingViewController: presenting,
            isPresenting: true
        ) else {
            return nil
        }
        return ZoomAnimator(storyTransitionContext: storyTransitionContext)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let presentingViewController = presentingViewController else { return nil }
        guard let storyTransitionContext = try? storyTransitionContext(
            presentingViewController: presentingViewController,
            isPresenting: false
        ) else {
            return SlideAnimator(interactiveEdge: interactiveDismissCoordinator?.interactiveEdge ?? .none)
        }
        return ZoomAnimator(storyTransitionContext: storyTransitionContext)
    }

    public func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        guard let interactiveDismissCoordinator = interactiveDismissCoordinator, interactiveDismissCoordinator.interactionInProgress else { return nil }
        interactiveDismissCoordinator.mode = animator is ZoomAnimator ? .zoom : .slide
        return interactiveDismissCoordinator
    }

    private func storyTransitionContext(presentingViewController: UIViewController, isPresenting: Bool) throws -> StoryTransitionContext? {
        // If we're not presenting from the stories tab, use a default animation
        guard let splitViewController = presentingViewController as? ConversationSplitViewController else { return nil }
        guard splitViewController.homeVC.selectedTab == .stories else { return nil }

        let storiesVC = splitViewController.homeVC.storiesViewController

        // If the story cell isn't visible, use a default animation
        guard let storyCell = storiesVC.cell(for: currentContext) else { return nil }

        guard let storyModel = storiesVC.model(for: currentContext), !storyModel.messages.isEmpty else {
            throw OWSAssertionError("Unexpectedly missing story model for presentation")
        }

        let storyMessage: StoryMessage
        if let currentMessage = currentContextViewController.currentItem?.message {
            storyMessage = currentMessage
        } else {
            storyMessage = storyModel.messages.first(where: { $0.localUserViewedTimestamp == nil }) ?? storyModel.messages.first!
        }

        return .init(
            isPresenting: isPresenting,
            thumbnailView: storyCell.attachmentThumbnail,
            storyView: try storyView(for: storyMessage),
            thumbnailRepresentsStoryView: storyMessage.uniqueId == storyModel.messages.last?.uniqueId,
            pageViewController: self
        )
    }

    private func storyView(for presentingMessage: StoryMessage) throws -> UIView {
        let storyView: UIView
        switch presentingMessage.attachment {
        case .file(let attachmentId):
            guard let attachment = databaseStorage.read(block: { TSAttachment.anyFetch(uniqueId: attachmentId, transaction: $0) }) else {
                throw OWSAssertionError("Unexpectedly missing attachment for story message")
            }

            let view = UIView()
            storyView = view

            if let stream = attachment as? TSAttachmentStream, let thumbnailImage = stream.thumbnailImageSmallSync() {
                let blurredImageView = UIImageView()
                blurredImageView.contentMode = .scaleAspectFill
                blurredImageView.image = thumbnailImage

                let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
                blurredImageView.addSubview(blurView)
                blurView.autoPinEdgesToSuperviewEdges()

                view.addSubview(blurredImageView)
                blurredImageView.autoPinEdgesToSuperviewEdges()

                let imageView = UIImageView()
                imageView.contentMode = .scaleAspectFit
                imageView.image = thumbnailImage
                view.addSubview(imageView)
                imageView.autoPinEdgesToSuperviewEdges()
            } else if let blurHash = attachment.blurHash, let blurHashImage = BlurHash.image(for: blurHash) {
                let blurHashImageView = UIImageView()
                blurHashImageView.contentMode = .scaleAspectFill
                blurHashImageView.image = blurHashImage
                view.addSubview(blurHashImageView)
                blurHashImageView.autoPinEdgesToSuperviewEdges()
            }
        case .text(let attachment):
            storyView = TextAttachmentView(attachment: attachment).asThumbnailView()
        }

        storyView.clipsToBounds = true

        return storyView
    }
}

private class InteractiveDismissCoordinator: UIPercentDrivenInteractiveTransition, UIGestureRecognizerDelegate {
    weak var pageViewController: StoryPageViewController!
    lazy var panGestureRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handlePan(_:))
    )
    init(pageViewController: StoryPageViewController) {
        self.pageViewController = pageViewController
        super.init()
        pageViewController.view.addGestureRecognizer(panGestureRecognizer)
        panGestureRecognizer.delegate = self

        for subview in pageViewController.view.subviews {
            guard let scrollView = subview as? UIScrollView else { continue }
            scrollView.panGestureRecognizer.require(toFail: panGestureRecognizer)
            break
        }
    }

    var interactionInProgress: Bool { interactiveEdge != .none }

    enum Edge {
        case leading
        case top
        case bottom
        case none
    }
    var interactiveEdge: Edge = .none

    enum Mode {
        case zoom
        case slide
    }
    var mode: Mode = .zoom

    @objc
    func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began:
            gestureRecognizer.setTranslation(.zero, in: pageViewController.view)
            pageViewController.pause()
            pageViewController.dismiss(animated: true)
        case .changed:
            update(calculateProgress(gestureRecognizer))
        case .cancelled:
            pageViewController.resume()
            cancel()
            interactiveEdge = .none
        case .ended:
            let progress = calculateProgress(gestureRecognizer)

            if progress >= 0.5 || hasExceededVelocityThreshold(gestureRecognizer) {
                finish()
            } else {
                pageViewController.resume()
                cancel()
            }

            interactiveEdge = .none
        default:
            cancel()
            interactiveEdge = .none
        }
    }

    func calculateProgress(_ gestureRecognizer: UIPanGestureRecognizer) -> CGFloat {
        let offset = gestureRecognizer.translation(in: pageViewController.view)
        let totalDistance: CGFloat

        switch mode {
        case .zoom: totalDistance = 150
        case .slide:
            switch interactiveEdge {
            case .top, .bottom: totalDistance = pageViewController.view.height
            case .leading, .none: totalDistance = pageViewController.view.width
            }
        }

        switch interactiveEdge {
        case .top:
            return offset.y / totalDistance
        case .leading:
            return ((CurrentAppContext().isRTL ? -1 : 1) * offset.x) / totalDistance
        case .bottom:
            return -offset.y / totalDistance
        case .none:
            return 0
        }
    }

    func hasExceededVelocityThreshold(_ gestureRecognizer: UIPanGestureRecognizer) -> Bool {
        let velocity = gestureRecognizer.velocity(in: pageViewController.view)
        let velocityThreshold: CGFloat = 500

        switch interactiveEdge {
        case .top:
            return velocity.y > velocityThreshold
        case .leading:
            return ((CurrentAppContext().isRTL ? -1 : 1) * velocity.x) > velocityThreshold
        case .bottom:
            return -velocity.y > velocityThreshold
        case .none:
            return false
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == panGestureRecognizer else { return false }
        let translation = panGestureRecognizer.translation(in: pageViewController.view)

        if !CurrentAppContext().isRTL, translation.x > 0 {
            interactiveEdge = .leading
            return true
        } else if CurrentAppContext().isRTL, translation.x < 0 {
            interactiveEdge = .leading
            return true
        } else if pageViewController.previousStoryContext == nil, translation.y > 0 {
            interactiveEdge = .top
            return true
        } else if pageViewController.nextStoryContext == nil, translation.y < 0 {
            interactiveEdge = .bottom
            return true
        } else {
            interactiveEdge = .none
            return false
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer == panGestureRecognizer
    }
}

private struct StoryTransitionContext {
    let isPresenting: Bool
    let thumbnailView: UIView
    let storyView: UIView
    let thumbnailRepresentsStoryView: Bool
    weak var pageViewController: StoryPageViewController!
}

private class ZoomAnimator: NSObject, UIViewControllerAnimatedTransitioning {
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

private class SlideAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let interactiveEdge: InteractiveDismissCoordinator.Edge
    init(interactiveEdge: InteractiveDismissCoordinator.Edge) {
        self.interactiveEdge = interactiveEdge
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.2
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView

        guard let fromVC = transitionContext.viewController(forKey: .from),
              let toVC = transitionContext.viewController(forKey: .to) else {
            owsFailDebug("Missing vcs")
            transitionContext.completeTransition(false)
            return
        }

        containerView.addSubview(toVC.view)

        containerView.addSubview(fromVC.view)
        fromVC.view.frame = transitionContext.initialFrame(for: fromVC)

        let endFrame: CGRect
        switch interactiveEdge {
        case .leading:
            endFrame = fromVC.view.frame.offsetBy(dx: (CurrentAppContext().isRTL ? -1 : 1) * fromVC.view.width, dy: 0)
        case .top, .none:
            endFrame = fromVC.view.frame.offsetBy(dx: 0, dy: fromVC.view.height)
        case .bottom:
            endFrame = fromVC.view.frame.offsetBy(dx: 0, dy: -fromVC.view.height)
        }

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: interactiveEdge != .none ? .curveLinear : .curveEaseInOut
        ) {
            fromVC.view.frame = endFrame
        } completion: { _ in
            if transitionContext.transitionWasCancelled {
                toVC.view.removeFromSuperview()
            } else {
                fromVC.view.removeFromSuperview()
            }

            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
}
