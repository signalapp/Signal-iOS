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
    private var interactiveDismissCoordinator: StoryInteractiveTransitionCoordinator?

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

        interactiveDismissCoordinator = StoryInteractiveTransitionCoordinator(pageViewController: self)
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

    func storyContextViewControllerDidPause(_ storyContextViewController: StoryContextViewController) {
        displayLink?.isPaused = true
    }

    func storyContextViewControllerDidResume(_ storyContextViewController: StoryContextViewController) {
        displayLink?.isPaused = false
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
        return StoryZoomAnimator(storyTransitionContext: storyTransitionContext)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let presentingViewController = presentingViewController else { return nil }
        guard let storyTransitionContext = try? storyTransitionContext(
            presentingViewController: presentingViewController,
            isPresenting: false
        ) else {
            return StorySlideAnimator(interactiveEdge: interactiveDismissCoordinator?.interactiveEdge ?? .none)
        }
        return StoryZoomAnimator(storyTransitionContext: storyTransitionContext)
    }

    public func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        guard let interactiveDismissCoordinator = interactiveDismissCoordinator, interactiveDismissCoordinator.interactionInProgress else { return nil }
        interactiveDismissCoordinator.mode = animator is StoryZoomAnimator ? .zoom : .slide
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
            pageViewController: self,
            interactiveGesture: interactiveDismissCoordinator?.interactionInProgress == true
                ? interactiveDismissCoordinator?.panGestureRecognizer : nil
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
