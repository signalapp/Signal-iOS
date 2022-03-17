//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

protocol StoryPageViewControllerDataSource: AnyObject {
    func storyPageViewController(_ storyPageViewController: StoryPageViewController, storyContextBefore storyContext: StoryContext) -> StoryContext?
    func storyPageViewController(_ storyPageViewController: StoryPageViewController, storyContextAfter storyContext: StoryContext) -> StoryContext?
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
    weak var contextDataSource: StoryPageViewControllerDataSource?

    required init(context: StoryContext) {
        super.init(transitionStyle: .scroll, navigationOrientation: .vertical, options: nil)
        self.currentContext = context
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
        guard let contextBefore = contextDataSource?.storyPageViewController(self, storyContextBefore: currentContext) else {
            return nil
        }

        return StoryContextViewController(context: contextBefore, delegate: self)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let contextAfter = contextDataSource?.storyPageViewController(self, storyContextAfter: currentContext) else {
            return nil
        }

        return StoryContextViewController(context: contextAfter, delegate: self)
    }
}

extension StoryPageViewController: StoryContextViewControllerDelegate {
    func storyContextViewControllerWantsTransitionToNextContext(
        _ storyContextViewController: StoryContextViewController,
        loadPosition: StoryContextViewController.LoadPosition
    ) {
        guard let nextContext = contextDataSource?.storyPageViewController(self, storyContextAfter: currentContext) else {
            dismiss(animated: true)
            return
        }
        setViewControllers(
            [StoryContextViewController(context: nextContext, loadPosition: loadPosition, delegate: self)],
            direction: .forward,
            animated: true
        )
    }

    func storyContextViewControllerWantsTransitionToPreviousContext(
        _ storyContextViewController: StoryContextViewController,
        loadPosition: StoryContextViewController.LoadPosition
    ) {
        guard let previousContext = contextDataSource?.storyPageViewController(self, storyContextBefore: currentContext) else {
            storyContextViewController.resetForPresentation()
            return
        }
        setViewControllers(
            [StoryContextViewController(context: previousContext, loadPosition: loadPosition, delegate: self)],
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
