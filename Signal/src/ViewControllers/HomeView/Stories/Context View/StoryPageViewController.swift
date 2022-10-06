//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalUI

protocol StoryPageViewControllerDataSource: AnyObject {
    func storyPageViewControllerAvailableContexts(
        _ storyPageViewController: StoryPageViewController,
        hiddenStoryFilter: Bool?
    ) -> [StoryContext]
}

class StoryPageViewController: UIPageViewController {

    // MARK: - State

    var currentContext: StoryContext {
        get { currentContextViewController.context }
        set {
            setViewControllers([StoryContextViewController(context: newValue, delegate: self)], direction: .forward, animated: false)
        }
    }
    let onlyRenderMyStories: Bool

    var currentMessage: StoryMessage? {
        currentContextViewController.currentItem?.message
    }

    weak var contextDataSource: StoryPageViewControllerDataSource?
    let viewableContexts: [StoryContext]
    private let hiddenStoryFilter: Bool?
    private var interactiveDismissCoordinator: StoryInteractiveTransitionCoordinator?

    private let audioActivity = AudioActivity(audioDescription: "StoriesViewer", behavior: .playbackMixWithOthers)

    // MARK: View Controllers

    var pendingTransitionViewControllers = [StoryContextViewController]()

    var currentContextViewController: StoryContextViewController {
        viewControllers!.first as! StoryContextViewController
    }

    // MARK: - Init

    required init(
        context: StoryContext,
        viewableContexts: [StoryContext]? = nil,
        hiddenStoryFilter: Bool? = nil, /* If true only hidden stories, if false only unhidden. */
        loadMessage: StoryMessage? = nil,
        action: StoryContextViewController.Action = .none,
        onlyRenderMyStories: Bool = false
    ) {
        self.onlyRenderMyStories = onlyRenderMyStories
        self.viewableContexts = viewableContexts ?? [context]
        self.hiddenStoryFilter = hiddenStoryFilter
        super.init(transitionStyle: .scroll, navigationOrientation: .vertical, options: nil)
        self.currentContext = context
        currentContextViewController.loadMessage = loadMessage
        currentContextViewController.action = action
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

    private var isDisplayLinkPaused = false {
        didSet {
            displayLink?.isPaused = isDisplayLinkPaused
        }
    }

    private var displayLink: CADisplayLink?

    private var viewIsAppeared = false {
        didSet {
            updateVolumeObserversIfNeeded()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let displayLink = displayLink {
            displayLink.isPaused = false
        } else {
            let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkStep))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
            displayLink.isPaused = isDisplayLinkPaused
        }
        viewIsAppeared = true
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // For now, the design only allows for portrait layout on non-iPads
        if !UIDevice.current.isIPad && CurrentAppContext().interfaceOrientation != .portrait {
            UIDevice.current.ows_setOrientation(.portrait)
        }

        currentContextViewController.pageControllerDidAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        currentContextViewController.pause()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if isBeingDismissed {
            displayLink?.invalidate()
            displayLink = nil
        }
        viewIsAppeared = false
    }

    @objc func owsApplicationWillEnterForeground() {
        // reset mute state if foregrounded while this is on screen.
        self.isMuted = true
    }

    @objc
    func displayLinkStep(_ displayLink: CADisplayLink) {
        currentContextViewController.displayLinkStep(displayLink)
    }

    // MARK: - Muting

    private struct MuteStatus {
        let isMuted: Bool
        let appForegroundTime: Date
    }

    // Once unmuted, stays that way until the app is backgrounded.
    private static var muteStatus: MuteStatus?

    private var isMuted: Bool {
        get {
            let appForegroundTime = CurrentAppContext().appForegroundTime
            if
                let muteStatus = Self.muteStatus,
                // Mute status is only valid for one foregroundind session,
                // dedupe by timestamp.
                muteStatus.appForegroundTime == appForegroundTime
            {
                return muteStatus.isMuted
            }
            let muteStatus = MuteStatus(
                // Audio starts muted until the user unmutes.
                isMuted: true,
                appForegroundTime: CurrentAppContext().appForegroundTime
            )
            Self.muteStatus = muteStatus
            return muteStatus.isMuted
        }
        set {
            Self.muteStatus = MuteStatus(
                isMuted: newValue,
                appForegroundTime: CurrentAppContext().appForegroundTime
            )
            viewControllers?.forEach {
                ($0 as? StoryContextViewController)?.updateMuteState()
            }
            updateVolumeObserversIfNeeded()
        }
    }

    private var isAudioSessionActive = false
    private var isObservingVolumeButtons = false

    private func updateVolumeObserversIfNeeded() {
        // Set audio session only if on screen.
        if viewIsAppeared {
            if isAudioSessionActive {
                // Nothing to do, we are already listening
            } else {
                startAudioSession()
            }
        } else {
            if isAudioSessionActive {
                stopAudioSession()
            } else {
                // We were already not listening, nothing to do.
            }
        }

        // Observe volume buttons only if on screen and muted.
        if viewIsAppeared && isMuted {
            if isObservingVolumeButtons {
                // Nothing to do, we are already listening.
            } else {
                observeVolumeButtons()
            }
        } else {
            if isObservingVolumeButtons {
                stopObservingVolumeButtons()
            } else {
                // We were already not listening, nothing to do.
            }
        }
    }

    private func startAudioSession() {
        // AudioSession's activities act like a stack; by adding a story-wide activity here we
        // ensure the session configuration doesn't get needlessly changed every time a player
        // for an individual story starts and stops. The config stays the same as long
        // as the story viewer is up.
        let startAudioActivitySuccess = audioSession.startAudioActivity(audioActivity)
        owsAssertDebug(startAudioActivitySuccess, "Starting stories audio activity failed")

        RingerSwitch.shared.addObserver(observer: self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(owsApplicationWillEnterForeground),
            name: .OWSApplicationWillEnterForeground,
            object: nil
        )
        isAudioSessionActive = true
    }

    private func stopAudioSession() {
        // If the view disappeared and we were listening, stop.
        audioSession.endAudioActivity(audioActivity)
        RingerSwitch.shared.removeObserver(self)
        NotificationCenter.default.removeObserver(self, name: .OWSApplicationWillEnterForeground, object: nil)
        isAudioSessionActive = false
    }

    private func observeVolumeButtons() {
        VolumeButtons.shared?.addObserver(observer: self)
        isObservingVolumeButtons = true
    }

    private func stopObservingVolumeButtons() {
        VolumeButtons.shared?.removeObserver(self)
        isObservingVolumeButtons = false
    }
}

extension StoryPageViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        willTransition(to: pendingViewControllers)
    }

    private func willTransition(to pendingViewControllers: [UIViewController]) {
        self.pendingTransitionViewControllers = pendingViewControllers
            .map { $0 as! StoryContextViewController }
        // Note: this also starts playing the next one transitioning in
        pendingTransitionViewControllers.forEach { $0.resetForPresentation() }

        currentContextViewController.pause()
        isDisplayLinkPaused = true
        self.view.isUserInteractionEnabled = false
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard finished else {
            return
        }
        didFinishTransitioning(completed: completed)
    }

    func didFinishTransitioning(completed: Bool) {
        if !completed {
            // The transition was stopped, reverting to the previous controller.
            // Stop the pending ones that are now cancelled.
            pendingTransitionViewControllers.forEach { $0.pause() }
            // Play the current one (which is the one we started out with and paused
            // when the transition began)
            currentContextViewController.play()
        }
        pendingTransitionViewControllers = []
        isDisplayLinkPaused = false
        self.view.isUserInteractionEnabled = true
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
        guard let contextDataSource = contextDataSource else { return viewableContexts }
        let availableContexts = contextDataSource.storyPageViewControllerAvailableContexts(self, hiddenStoryFilter: hiddenStoryFilter)
        return viewableContexts.filter { availableContexts.contains($0) }
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
        guard
            pendingTransitionViewControllers.isEmpty,
            storyContextViewController == currentContextViewController
        else {
            return
        }

        guard let nextContext = nextStoryContext else {
            dismiss(animated: true)
            return
        }
        let newControllers = [StoryContextViewController(context: nextContext, loadPositionIfRead: loadPositionIfRead, delegate: self)]
        self.willTransition(to: newControllers)
        setViewControllers(
            newControllers,
            direction: .forward,
            animated: true
        ) { completed in
            self.didFinishTransitioning(completed: completed)
        }
    }

    func storyContextViewControllerWantsTransitionToPreviousContext(
        _ storyContextViewController: StoryContextViewController,
        loadPositionIfRead: StoryContextViewController.LoadPosition
    ) {
        guard let previousContext = previousStoryContext else {
            storyContextViewController.resetForPresentation()
            return
        }
        let newControllers = [StoryContextViewController(context: previousContext, loadPositionIfRead: loadPositionIfRead, delegate: self)]
        self.willTransition(to: newControllers)
        setViewControllers(
            newControllers,
            direction: .reverse,
            animated: true
        ) { completed in
            self.didFinishTransitioning(completed: completed)
        }
    }

    func storyContextViewController(_ storyContextViewController: StoryContextViewController, contextAfter context: StoryContext) -> StoryContext? {
        guard let contextIndex = availableContexts.firstIndex(of: context),
              let contextAfter = availableContexts[safe: contextIndex.advanced(by: 1)] else {
            return nil
        }
        return contextAfter
    }

    func storyContextViewControllerDidPause(_ storyContextViewController: StoryContextViewController) {
        guard
            storyContextViewController === currentContextViewController,
            // Don't stop the displaylink during a transition, one of the two controllers is playing.
            pendingTransitionViewControllers.isEmpty
        else {
            return
        }
        isDisplayLinkPaused = true
    }

    func storyContextViewControllerDidResume(_ storyContextViewController: StoryContextViewController) {
        isDisplayLinkPaused = false
    }

    func storyContextViewControllerShouldOnlyRenderMyStories(_ storyContextViewController: StoryContextViewController) -> Bool {
        onlyRenderMyStories
    }

    func storyContextViewControllerShouldBeMuted(_ storyContextViewController: StoryContextViewController) -> Bool {
        return isMuted
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

        let thumbnailView: UIView
        let storyMessage: StoryMessage
        let thumbnailRepresentsStoryView: Bool

        switch splitViewController.homeVC.storiesNavController.topViewController {
        case let storiesVC as StoriesViewController:
            // If the story cell isn't visible, use a default animation
            guard let storyCell = storiesVC.cell(for: currentContext) else { return nil }

            guard let storyModel = storiesVC.model(for: currentContext), !storyModel.messages.isEmpty else {
                throw OWSAssertionError("Unexpectedly missing story model for presentation")
            }

            if let currentMessage = currentMessage {
                storyMessage = currentMessage
            } else {
                storyMessage = storyModel.messages.first(where: { $0.localUserViewedTimestamp == nil }) ?? storyModel.messages.first!
            }

            thumbnailView = storyCell.attachmentThumbnail
            thumbnailRepresentsStoryView = storyMessage.uniqueId == storyModel.messages.last?.uniqueId
        case let myStoriesVC as MyStoriesViewController:
            guard let message = currentMessage ?? currentContextViewController.loadMessage else {
                owsFailDebug("Unexpectedly missing current message when presenting story from MyStoriesViewController")
                return nil
            }

            // If the story cell isn't visible, use a default animation
            guard let sentStoryCell = myStoriesVC.cell(for: message, and: currentContext) else { return nil }

            storyMessage = message
            thumbnailView = sentStoryCell.attachmentThumbnail
            thumbnailRepresentsStoryView = true
        default:
            return nil
        }

        guard let storyView = storyView(for: storyMessage) else {
            return nil
        }

        return .init(
            isPresenting: isPresenting,
            thumbnailView: thumbnailView,
            storyView: storyView,
            storyThumbnailSize: try storyThumbnailSize(for: storyMessage),
            thumbnailRepresentsStoryView: thumbnailRepresentsStoryView,
            pageViewController: self,
            interactiveGesture: interactiveDismissCoordinator?.interactionInProgress == true
                ? interactiveDismissCoordinator?.panGestureRecognizer : nil
        )
    }

    private func storyThumbnailSize(for presentingMessage: StoryMessage) throws -> CGSize? {
        switch presentingMessage.attachment {
        case .file(let attachmentId):
            guard let attachment = databaseStorage.read(block: { TSAttachment.anyFetch(uniqueId: attachmentId, transaction: $0) }) else {
                throw OWSAssertionError("Unexpectedly missing attachment for story message")
            }

            if let stream = attachment as? TSAttachmentStream, let thumbnailImage = stream.thumbnailImageSmallSync() {
                return thumbnailImage.size
            } else {
                return nil
            }
        case .text:
            return nil
        }
    }

    private func storyView(for presentingMessage: StoryMessage) -> UIView? {
        let storyView: UIView
        switch presentingMessage.attachment {
        case .file(let attachmentId):
            guard let attachment = databaseStorage.read(block: { TSAttachment.anyFetch(uniqueId: attachmentId, transaction: $0) }) else {
                // Can happen if the story was deleted by the sender while in the viewer.
                return nil
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

extension StoryPageViewController: VolumeButtonObserver {

    func didPressVolumeButton(with identifier: VolumeButtons.Identifier) {
        VolumeButtons.shared?.incrementSystemVolume(for: identifier)

        guard isMuted else {
            // Already unmuted, no need to do anything.
            return
        }
        // Unmute when the user presses the volume buttons.
        isMuted = false
    }
}

extension StoryPageViewController: RingerSwitchObserver {

    func didToggleRingerSwitch(_ isSilenced: Bool) {
        guard !isMuted && isSilenced else {
            // Not muting
            return
        }
        // Mute if unmuted and toggling off.
        isMuted = true
    }
}
