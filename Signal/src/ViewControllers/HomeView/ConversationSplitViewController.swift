//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ConversationSplitViewController: UISplitViewController {
    private let conversationListVC = ConversationListViewController()
    private let detailPlaceholderVC = NoSelectedConversationViewController()

    private lazy var primaryNavController = SignalsNavigationController(rootViewController: conversationListVC)
    private lazy var detailNavController = OWSNavigationController()

    @objc private(set) weak var selectedConversationViewController: ConversationViewController?
    @objc var selectedThread: TSThread? {
        // If the placeholder view is in the view hierarchy, there is no selected thread.
        guard detailPlaceholderVC.view.superview == nil else { return nil }
        guard let selectedConversationViewController = selectedConversationViewController else { return nil }

        // In order to not show selected when collapsed during an interactive dismissal,
        // we verify the conversation is still in the nav stack when collapsed. There is
        // no interactive dismissal when expanded, so we don't have to do any special check.
        guard !isCollapsed || primaryNavController.viewControllers.contains(selectedConversationViewController) else { return nil }

        return selectedConversationViewController.thread
    }

    @objc var topViewController: UIViewController? {
        guard !isCollapsed else {
            return primaryNavController.topViewController
        }

        return detailNavController.topViewController ?? primaryNavController.topViewController
    }

    @objc
    init() {
        super.init(nibName: nil, bundle: nil)

        viewControllers = [primaryNavController, detailPlaceholderVC]

        primaryNavController.delegate = self
        delegate = self

        // If this is not an iPad we want to always show the collapsed mode, even
        // if the size class is regular (portrait mode on large phones). On iPad,
        // if there is space we want to always show the conversation list.
        preferredDisplayMode = UIDevice.current.isIPad ? .allVisible : .primaryHidden
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
    }

    override var canBecomeFirstResponder: Bool {
        return false
    }

    @objc
    func showNewConversationView() {
        conversationListVC.showNewConversationView()
    }

    @objc(closeSelectedConversationAnimated:)
    func closeSelectedConversation(animated: Bool) {
        guard let selectedConversationViewController = selectedConversationViewController else { return }

        if isCollapsed {
            // If we're currently displaying the conversation in the primary nav controller, remove it
            // and everything it pushed to the navigation stack from the nav controller. We don't want
            // to just pop to root as we might have opened this conversation from the archive.
            if let selectedConversationIndex = primaryNavController.viewControllers.firstIndex(of: selectedConversationViewController) {
                let trimmedViewControllers = Array(primaryNavController.viewControllers[0..<selectedConversationIndex])
                primaryNavController.setViewControllers(trimmedViewControllers, animated: animated)
            }
        } else {
            viewControllers[1] = detailPlaceholderVC
        }
    }

    @objc
    func presentThread(_ thread: TSThread, action: ConversationViewAction, focusMessageId: String?, animated: Bool) {
        AssertIsOnMainThread()

        guard selectedThread?.uniqueId != thread.uniqueId else {
            // If this thread is already selected, pop to the thread if
            // anything else has been presented above the view.
            guard let selectedConversationVC = selectedConversationViewController else { return }
            if isCollapsed {
                primaryNavController.popToViewController(selectedConversationVC, animated: animated)
            } else {
                detailNavController.popToViewController(selectedConversationVC, animated: animated)
            }
            return
        }

        // Update the last viewed thread on the conversation list so it
        // can maintain its scroll position when navigating back.
        conversationListVC.lastViewedThread = thread

        // Close any currently open conversation so we don't end up
        // with multiple conversations in the nav stack.
        closeSelectedConversation(animated: animated)

        let vc = ConversationViewController()
        vc.configure(for: thread, action: action, focusMessageId: focusMessageId)

        selectedConversationViewController = vc

        let detailVC: UIViewController = {
            guard !isCollapsed else { return vc }

            detailNavController.viewControllers = [vc]
            return detailNavController
        }()

        if animated {
            showDetailViewController(detailVC, sender: self)
        } else {
            UIView.performWithoutAnimation { showDetailViewController(detailVC, sender: self) }
        }
    }
}

extension ConversationSplitViewController: UISplitViewControllerDelegate {
    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
        // If we're currently showing the placeholder view, we want to do nothing with in
        // when collapsing into a signle nav controller without a side panel.
        guard secondaryViewController != detailPlaceholderVC else { return true }

        assert(secondaryViewController == detailNavController)

        // Move all the views from the detail nav controller onto the primary nav controller.
        primaryNavController.viewControllers += detailNavController.viewControllers

        return true
    }

    func splitViewController(_ splitViewController: UISplitViewController, separateSecondaryFrom primaryViewController: UIViewController) -> UIViewController? {
        assert(primaryViewController == primaryNavController)

        // See if the current conversation is currently in the view hierarchy. If not,
        // show the placeholder view as no conversation is selected. The conversation
        // was likely popped from the stack while the split view was collapsed.
        guard let currentConversationVC = selectedConversationViewController,
            let conversationVCIndex = primaryNavController.viewControllers.firstIndex(of: currentConversationVC) else {
                self.selectedConversationViewController = nil
            return detailPlaceholderVC
        }

        // Move everything on the nav stack from the conversation view on back onto
        // the detail nav controller.

        let allViewControllers = primaryNavController.viewControllers

        primaryNavController.viewControllers = Array(allViewControllers[0..<conversationVCIndex])

        // Create a new detail nav because reusing the existing one causes
        // some strange behavior around the title view + input accessory view.
        // TODO iPad: Maybe investigate this further.
        detailNavController = OWSNavigationController()
        detailNavController.viewControllers = Array(allViewControllers[conversationVCIndex..<allViewControllers.count])

        return detailNavController
    }
}

extension ConversationSplitViewController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        // If we're collapsed and navigating to a list VC (either inbox or archive)
        // the current conversation is no longer selected.
        guard isCollapsed, viewController is ConversationListViewController else { return }
        selectedConversationViewController = nil
    }
}

@objc extension ConversationListViewController {
    var conversationSplitViewController: ConversationSplitViewController? {
        return splitViewController as? ConversationSplitViewController
    }
}

@objc extension ConversationViewController {
    var conversationSplitViewController: ConversationSplitViewController? {
        return splitViewController as? ConversationSplitViewController
    }
}

private class NoSelectedConversationViewController: OWSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self, selector: #selector(self.applyTheme), name: .ThemeDidChange, object: nil)

        applyTheme()
    }

    @objc func applyTheme() {
        view.backgroundColor = Theme.backgroundColor
    }
}
