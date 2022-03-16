//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import UIKit
import SignalUI

protocol StoryHorizontalPageViewControllerDelegate: AnyObject {
    func storyHorizontalPageViewControllerWantsTransitionToNextContext(_ storyHorizontalPageViewController: StoryHorizontalPageViewController)
    func storyHorizontalPageViewControllerWantsTransitionToPreviousContext(_ storyHorizontalPageViewController: StoryHorizontalPageViewController)
}

class StoryHorizontalPageViewController: OWSViewController {
    let context: StoryContext

    weak var delegate: StoryHorizontalPageViewControllerDelegate?

    private lazy var pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
        options: nil
    )
    private lazy var playbackProgressView = StoryPlaybackProgressView()

    private var items = [StoryItem]()
    var currentItem: StoryItem? {
        set {
            let viewControllers: [StoryItemViewController]
            if let newValue = newValue {
                viewControllers = [StoryItemViewController(item: newValue)]
            } else {
                viewControllers = []
            }
            pageViewController.setViewControllers(viewControllers, direction: .forward, animated: false)
            updateProgressState()
        }
        get { currentItemViewController?.item }
    }
    var currentItemViewController: StoryItemViewController? {
        pageViewController.viewControllers?.first as? StoryItemViewController
    }

    required init(context: StoryContext, delegate: StoryHorizontalPageViewControllerDelegate) {
        self.context = context
        super.init()
        self.delegate = delegate
        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func resetForPresentation() {
        // If we've loaded already, reset to the first item
        if let firstItem = items.first {
            currentItem = firstItem
        }
    }

    @objc
    func transitionToNextItem() {
        guard let currentVC = currentItemViewController,
              let nextVC = pageViewController(pageViewController, viewControllerAfter: currentVC) else {
                  delegate?.storyHorizontalPageViewControllerWantsTransitionToNextContext(self)
                  return
              }
        pageViewController.setViewControllers([nextVC], direction: .forward, animated: true)
        updateProgressState()
    }

    @objc
    func transitionToPreviousItem() {
        guard let currentVC = currentItemViewController,
              let previousVC = pageViewController(pageViewController, viewControllerBefore: currentVC) else {
                  delegate?.storyHorizontalPageViewControllerWantsTransitionToPreviousContext(self)
                  return
              }
        pageViewController.setViewControllers([previousVC], direction: .reverse, animated: true)
        updateProgressState()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        displayLink?.invalidate()
        displayLink = nil
    }

    private lazy var leftTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapLeft))
    private lazy var rightTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapRight))
    private lazy var pauseGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addGestureRecognizer(leftTapGestureRecognizer)
        view.addGestureRecognizer(rightTapGestureRecognizer)
        view.addGestureRecognizer(pauseGestureRecognizer)

        leftTapGestureRecognizer.delegate = self
        rightTapGestureRecognizer.delegate = self
        pauseGestureRecognizer.delegate = self
        pauseGestureRecognizer.minimumPressDuration = 0.2

        leftTapGestureRecognizer.require(toFail: pauseGestureRecognizer)
        rightTapGestureRecognizer.require(toFail: pauseGestureRecognizer)

        pageViewController.view.alpha = 0
        pageViewController.dataSource = self
        pageViewController.delegate = self
        pageViewController.view.isUserInteractionEnabled = false
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.autoPinEdgesToSuperviewSafeArea()

        view.addLayoutGuide(mediaLayoutGuide)
        mediaLayoutGuide.widthAnchor.constraint(equalTo: mediaLayoutGuide.heightAnchor, multiplier: 9/16).isActive = true

        if !UIDevice.current.hasIPhoneXNotch && !UIDevice.current.isIPad {
            mediaLayoutGuide.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        }

        applyConstraints()

        let spinner = UIActivityIndicatorView(style: .white)
        view.addSubview(spinner)
        spinner.autoCenterInSuperview()
        spinner.startAnimating()

        let closeButton = OWSButton(imageName: "x-24", tintColor: .ows_white) { [weak self] in
            self?.dismiss(animated: true)
        }
        closeButton.setShadow()
        closeButton.imageEdgeInsets = UIEdgeInsets(hMargin: 16, vMargin: 16)
        view.addSubview(closeButton)
        closeButton.autoSetDimensions(to: CGSize(square: 56))
        closeButton.autoPinEdge(.top, to: .top, of: pageViewController.view)
        closeButton.autoPinEdge(.leading, to: .leading, of: pageViewController.view)

        view.addSubview(playbackProgressView)
        playbackProgressView.leadingAnchor.constraint(equalTo: mediaLayoutGuide.leadingAnchor, constant: OWSTableViewController2.defaultHOuterMargin).isActive = true
        playbackProgressView.trailingAnchor.constraint(equalTo: mediaLayoutGuide.trailingAnchor, constant: -OWSTableViewController2.defaultHOuterMargin).isActive = true
        playbackProgressView.bottomAnchor.constraint(equalTo: mediaLayoutGuide.bottomAnchor, constant: -OWSTableViewController2.defaultHOuterMargin).isActive = true
        playbackProgressView.autoSetDimension(.height, toSize: 2)
        playbackProgressView.isUserInteractionEnabled = false

        loadStoryItems { [weak self] storyItems in
            // If there are no stories for this context, dismiss.
            guard let firstStoryItem = storyItems.first else {
                self?.dismiss(animated: true)
                return
            }

            UIView.animate(withDuration: 0.2) { [weak self] in
                spinner.alpha = 0
                self?.pageViewController.view.alpha = 1
            } completion: { _ in
                spinner.stopAnimating()
                spinner.removeFromSuperview()
            }

            self?.items = storyItems
            self?.currentItem = firstStoryItem
        }
    }

    private static let maxItemsToRender = 100
    private func loadStoryItems(completion: @escaping ([StoryItem]) -> Void) {
        var storyItems = [StoryItem]()
        databaseStorage.asyncRead { [weak self] transaction in
            guard let self = self else { return }
            StoryFinder.enumerateStoriesForContext(self.context, transaction: transaction) { message, stop in
                guard let storyItem = self.buildStoryItem(for: message, transaction: transaction) else { return }
                storyItems.append(storyItem)
                if storyItems.count >= Self.maxItemsToRender { stop.pointee = true }
            }

            DispatchQueue.main.async {
                completion(storyItems)
            }
        }
    }

    private func buildStoryItem(for message: StoryMessage, transaction: SDSAnyReadTransaction) -> StoryItem? {
        switch message.attachment {
        case .file(let attachmentId):
            guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) else {
                owsFailDebug("Missing attachment for StoryMessage with timestamp \(message.timestamp)")
                return nil
            }
            if let attachment = attachment as? TSAttachmentPointer {
                return .init(message: message, attachment: .pointer(attachment))
            } else if let attachment = attachment as? TSAttachmentStream {
                return .init(message: message, attachment: .stream(attachment))
            } else {
                owsFailDebug("Unexpected attachment type \(type(of: attachment))")
                return nil
            }
        case .text(let attachment):
            return .init(message: message, attachment: .text(attachment))
        }
    }

    private var pauseTime: CFTimeInterval?
    private var displayLink: CADisplayLink?
    private var lastTransitionTime: CFTimeInterval?
    private static let transitionDuration: CFTimeInterval = 5
    private func updateProgressState() {
        AssertIsOnMainThread()
        lastTransitionTime = CACurrentMediaTime()
        if let displayLink = displayLink {
            displayLink.isPaused = false
        } else {
            let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkStep))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
    }

    @objc
    func displayLinkStep(_ displayLink: CADisplayLink) {
        AssertIsOnMainThread()
        playbackProgressView.numberOfItems = items.count
        if let currentItemVC = currentItemViewController, let idx = items.firstIndex(of: currentItemVC.item) {
            // When we present a story, mark it as viewed if it's not already.
            if !currentItemVC.isDownloading, case .incoming(_, let viewedTimestamp) = currentItemVC.item.message.manifest, viewedTimestamp == nil {
                databaseStorage.write { transaction in
                    currentItemVC.item.message.markAsViewed(at: Date.ows_millisecondTimestamp(), circumstance: .onThisDevice, transaction: transaction)
                }
            }

            currentItemVC.updateTimestampText()
            if currentItemVC.isDownloading {
                lastTransitionTime = CACurrentMediaTime()
                playbackProgressView.itemState = .init(index: idx, value: 0)
            } else if let lastTransitionTime = lastTransitionTime {
                let currentTime: CFTimeInterval
                if let elapsedTime = currentItemVC.elapsedTime {
                    currentTime = lastTransitionTime + elapsedTime
                } else {
                    currentTime = displayLink.targetTimestamp
                }

                let value = currentTime.inverseLerp(
                    lastTransitionTime,
                    (lastTransitionTime + currentItemVC.duration),
                    shouldClamp: true
                )
                playbackProgressView.itemState = .init(index: idx, value: value)

                if value >= 1 {
                    displayLink.isPaused = true
                    transitionToNextItem()
                }
            } else {
                displayLink.isPaused = true
                playbackProgressView.itemState = .init(index: idx, value: 0)
            }
        } else {
            displayLink.isPaused = true
            playbackProgressView.itemState = .init(index: 0, value: 0)
        }
    }

    private lazy var iPadLandscapeConstraints = [
        mediaLayoutGuide.heightAnchor.constraint(lessThanOrEqualTo: pageViewController.view.heightAnchor, multiplier: 0.75)
    ]
    private lazy var iPadPortraitConstraints = [
        mediaLayoutGuide.heightAnchor.constraint(lessThanOrEqualTo: pageViewController.view.heightAnchor, multiplier: 0.65)
    ]

    private let mediaLayoutGuide = UILayoutGuide()

    private lazy var iPhoneConstraints = [
        mediaLayoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        mediaLayoutGuide.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
        mediaLayoutGuide.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
    ]

    private lazy var iPadConstraints: [NSLayoutConstraint] = {
        var constraints = [
            mediaLayoutGuide.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mediaLayoutGuide.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ]

        // Prefer to be as big as possible.
        let heightConstraint = mediaLayoutGuide.heightAnchor.constraint(equalTo: pageViewController.view.heightAnchor)
        heightConstraint.priority = .defaultHigh
        constraints.append(heightConstraint)

        let widthConstraint = mediaLayoutGuide.widthAnchor.constraint(equalTo: pageViewController.view.widthAnchor)
        widthConstraint.priority = .defaultHigh
        constraints.append(widthConstraint)

        return constraints
    }()

    private func applyConstraints(newSize: CGSize = CurrentAppContext().frame.size) {
        NSLayoutConstraint.deactivate(iPhoneConstraints)
        NSLayoutConstraint.deactivate(iPadConstraints)
        NSLayoutConstraint.deactivate(iPadPortraitConstraints)
        NSLayoutConstraint.deactivate(iPadLandscapeConstraints)

        if UIDevice.current.isIPad {
            NSLayoutConstraint.activate(iPadConstraints)
            if newSize.width > newSize.height {
                NSLayoutConstraint.activate(iPadLandscapeConstraints)
            } else {
                NSLayoutConstraint.activate(iPadPortraitConstraints)
            }
        } else {
            NSLayoutConstraint.activate(iPhoneConstraints)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            self.applyConstraints(newSize: size)
        } completion: { _ in
            self.applyConstraints()
        }
    }
}

extension StoryHorizontalPageViewController: UIGestureRecognizerDelegate {
    @objc
    func didTapLeft() {
        guard currentItemViewController?.willHandleTapGesture(leftTapGestureRecognizer) != true else { return }
        CurrentAppContext().isRTL ? transitionToPreviousItem() : transitionToNextItem()
    }

    @objc
    func didTapRight() {
        guard currentItemViewController?.willHandleTapGesture(rightTapGestureRecognizer) != true else { return }
        CurrentAppContext().isRTL ? transitionToNextItem() : transitionToPreviousItem()
    }

    @objc
    func handleLongPress() {
        switch pauseGestureRecognizer.state {
        case .began:
            pauseTime = CACurrentMediaTime()
            displayLink?.isPaused = true
            currentItemViewController?.pause()
        case .ended:
            if let lastTransitionTime = lastTransitionTime, let pauseTime = pauseTime {
                let pauseDuration = CACurrentMediaTime() - pauseTime
                self.lastTransitionTime = lastTransitionTime + pauseDuration
                self.pauseTime = nil
            }
            currentItemViewController?.play()
            displayLink?.isPaused = false
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let touchLocation = gestureRecognizer.location(in: view)
        if gestureRecognizer == leftTapGestureRecognizer {
            var nextFrame = mediaLayoutGuide.layoutFrame
            nextFrame.width = nextFrame.width / 2
            nextFrame.x += nextFrame.width
            return nextFrame.contains(touchLocation)
        } else if gestureRecognizer == rightTapGestureRecognizer {
            var previousFrame = mediaLayoutGuide.layoutFrame
            previousFrame.width = previousFrame.width / 2
            return previousFrame.contains(touchLocation)
        } else {
            return true
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

extension StoryHorizontalPageViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        updateProgressState()
    }

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        pendingViewControllers
            .lazy
            .map { $0 as! StoryItemViewController }
            .forEach { $0.reset() }
    }
}

extension StoryHorizontalPageViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let currentItem = currentItem,
              let currentItemIndex = items.firstIndex(of: currentItem),
              let itemBefore = items[safe: currentItemIndex.advanced(by: -1)] else {
                  return nil
              }

        return StoryItemViewController(item: itemBefore)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let currentItem = currentItem,
              let currentItemIndex = items.firstIndex(of: currentItem),
              let itemAfter = items[safe: currentItemIndex.advanced(by: 1)] else {
                  return nil
              }

        return StoryItemViewController(item: itemAfter)
    }
}

extension StoryHorizontalPageViewController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard var currentItem = currentItem else { return }
        guard !databaseChanges.storyMessageRowIds.isEmpty else { return }

        databaseStorage.asyncRead { transaction in
            var newItems = self.items
            var shouldDismiss = false
            for (idx, item) in self.items.enumerated().reversed() {
                guard let id = item.message.id, databaseChanges.storyMessageRowIds.contains(id) else { continue }
                if let message = StoryMessage.anyFetch(uniqueId: item.message.uniqueId, transaction: transaction) {
                    if let newItem = self.buildStoryItem(for: message, transaction: transaction) {
                        newItems[idx] = newItem

                        if item.message.uniqueId == currentItem.message.uniqueId {
                            currentItem = newItem
                        }

                        continue
                    }
                }

                newItems.remove(at: idx)
                if item.message.uniqueId == currentItem.message.uniqueId {
                    shouldDismiss = true
                    break
                }
            }
            DispatchQueue.main.async {
                if shouldDismiss {
                    self.dismiss(animated: true)
                } else {
                    self.items = newItems
                    self.currentItem = currentItem
                }
            }
        }
    }

    func databaseChangesDidUpdateExternally() {}

    func databaseChangesDidReset() {}
}
