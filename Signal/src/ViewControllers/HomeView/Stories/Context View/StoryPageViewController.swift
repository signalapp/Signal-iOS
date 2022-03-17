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
            setViewControllers([StoryHorizontalPageViewController(context: newValue, delegate: self)], direction: .forward, animated: false)
        }
        get {
            (viewControllers!.first as! StoryHorizontalPageViewController).context
        }
    }
    weak var contextDataSource: StoryPageViewControllerDataSource?

    required init(context: StoryContext) {
        super.init(transitionStyle: .scroll, navigationOrientation: .vertical, options: nil)
        self.currentContext = context
    }

    public func present(from fromViewController: UIViewController, animated: Bool) {
        AssertIsOnMainThread()

        modalPresentationStyle = .custom
        modalPresentationCapturesStatusBarAppearance = true
        transitioningDelegate = self
        fromViewController.present(self, animated: animated)
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
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // For now, the design only allows for portrait layout on non-iPads
        if !UIDevice.current.isIPad && CurrentAppContext().interfaceOrientation != .portrait {
            UIDevice.current.ows_setOrientation(.portrait)
        }
    }
}

extension StoryPageViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        pendingViewControllers
            .lazy
            .map { $0 as! StoryHorizontalPageViewController }
            .forEach { $0.resetForPresentation() }
    }
}

extension StoryPageViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let contextBefore = contextDataSource?.storyPageViewController(self, storyContextBefore: currentContext) else {
            return nil
        }

        return StoryHorizontalPageViewController(context: contextBefore, delegate: self)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let contextAfter = contextDataSource?.storyPageViewController(self, storyContextAfter: currentContext) else {
            return nil
        }

        return StoryHorizontalPageViewController(context: contextAfter, delegate: self)
    }
}

extension StoryPageViewController: StoryHorizontalPageViewControllerDelegate {
    func storyHorizontalPageViewControllerWantsTransitionToNextContext(_ storyHorizontalPageViewController: StoryHorizontalPageViewController) {
        guard let nextContext = contextDataSource?.storyPageViewController(self, storyContextAfter: currentContext) else {
                  dismiss(animated: true)
                  return
              }
        setViewControllers(
            [StoryHorizontalPageViewController(context: nextContext, delegate: self)],
            direction: .forward,
            animated: true
        )
    }

    func storyHorizontalPageViewControllerWantsTransitionToPreviousContext(_ storyHorizontalPageViewController: StoryHorizontalPageViewController) {
        guard let previousContext = contextDataSource?.storyPageViewController(self, storyContextBefore: currentContext) else {
            storyHorizontalPageViewController.resetForPresentation()
                  return
              }
        setViewControllers(
            [StoryHorizontalPageViewController(context: previousContext, delegate: self)],
            direction: .reverse,
            animated: true
        )
    }
}

private class AnimationController: UIPresentationController {

    let backdropView: UIView = UIView()

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)

        if UIAccessibility.isReduceTransparencyEnabled {
            backdropView.backgroundColor = Theme.backdropColor
        } else {
            let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            backdropView.addSubview(blurEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
            backdropView.backgroundColor = .ows_blackAlpha60
        }
    }

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView else { return }
        backdropView.alpha = 0
        containerView.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView.alpha = 1
        }, completion: nil)
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView.alpha = 0
        }, completion: { _ in
            self.backdropView.removeFromSuperview()
        })
    }
}

extension StoryPageViewController: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return AnimationController(presentedViewController: presented, presenting: presenting)
    }
}
