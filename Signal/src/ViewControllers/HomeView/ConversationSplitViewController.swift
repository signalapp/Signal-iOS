//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MultipeerConnectivity
import SignalServiceKit
import SignalUI

class ConversationSplitViewController: UISplitViewController, ConversationSplit {

    fileprivate var deviceTransferNavController: OutgoingDeviceTransferNavigationController?

    let homeVC: HomeTabBarController
    private let detailPlaceholderVC = NoSelectedConversationViewController()

    private var chatListNavController: OWSNavigationController { homeVC.chatListNavController }
    private var callListNavController: OWSNavigationController { homeVC.callsListNavController }
    private lazy var detailNavController = OWSNavigationController()
    private var lastActiveInterfaceOrientation = UIInterfaceOrientation.unknown

    private(set) weak var selectedConversationViewController: ConversationViewController?

    weak var navigationTransitionDelegate: UINavigationControllerDelegate?

    /// The thread, if any, that is currently presented in the view hieararchy. It may be currently
    /// covered by a modal presentation or a pushed view controller.
    var selectedThread: TSThread? {
        // If the placeholder view is in the view hierarchy, there is no selected thread.
        guard detailPlaceholderVC.view.superview == nil else { return nil }
        guard let selectedConversationViewController else { return nil }

        // In order to not show selected when collapsed during an interactive dismissal,
        // we verify the conversation is still in the nav stack when collapsed. There is
        // no interactive dismissal when expanded, so we don't have to do any special check.
        guard !isCollapsed || chatListNavController.viewControllers.contains(selectedConversationViewController) else { return nil }

        return selectedConversationViewController.thread
    }

    /// Returns the currently selected thread if it is visible on screen, otherwise
    /// returns nil.
    var visibleThread: TSThread? {
        guard view.window?.isKeyWindow == true else { return nil }
        guard selectedConversationViewController?.isViewVisible == true else { return nil }
        return selectedThread
    }

    var topViewController: UIViewController? {
        guard !isCollapsed else {
            return homeVC.selectedHomeTab == .calls ? callListNavController.topViewController : chatListNavController.topViewController
        }

        return detailNavController.topViewController ?? chatListNavController.topViewController
    }

    private let appReadiness: AppReadinessSetter

    init(appReadiness: AppReadinessSetter) {
        self.appReadiness = appReadiness
        self.homeVC = HomeTabBarController(appReadiness: appReadiness)
        super.init(nibName: nil, bundle: nil)

        viewControllers = [homeVC, detailPlaceholderVC]

        chatListNavController.delegate = self
        delegate = self
        preferredDisplayMode = .oneBesideSecondary

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: UIDevice.current
        )
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: .OWSApplicationDidBecomeActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didStartTransfer), name: .outgoingDeviceTransferDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEndTransfer), name: .outgoingDeviceTransferDidEnd, object: nil)

        applyTheme()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
    }

    @objc
    private func applyTheme() {
        view.backgroundColor = Theme.isDarkThemeEnabled ? UIColor(rgbHex: 0x292929) : UIColor(rgbHex: 0xd6d6d6)
    }

    @objc
    private func orientationDidChange() {
        AssertIsOnMainThread()

        if let windowScene = view.window?.windowScene, windowScene.activationState == .foregroundActive {
            lastActiveInterfaceOrientation = windowScene.interfaceOrientation
        }
    }

    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()

        if let windowScene = view.window?.windowScene {
            lastActiveInterfaceOrientation = windowScene.interfaceOrientation
        }
    }

    @objc
    private func didStartTransfer() {
        // Disable the device transfer listener while the new device restore flow is active
        AppEnvironment.shared.deviceTransferServiceRef.removeObserver(self)
        AppEnvironment.shared.deviceTransferServiceRef.stopListeningForNewDevices()
    }

    @objc
    private func didEndTransfer() {
        AppEnvironment.shared.deviceTransferServiceRef.addObserver(self)
        AppEnvironment.shared.deviceTransferServiceRef.startListeningForNewDevices()
    }

    func closeSelectedConversation(animated: Bool) {
        guard let selectedConversationViewController = selectedConversationViewController else { return }

        if isCollapsed {
            // If we're currently displaying the conversation in the primary nav controller, remove it
            // and everything it pushed to the navigation stack from the nav controller. We don't want
            // to just pop to root as we might have opened this conversation from the archive.
            if let selectedConversationIndex = chatListNavController.viewControllers.firstIndex(of: selectedConversationViewController) {
                let targetViewController = chatListNavController.viewControllers[max(0, selectedConversationIndex-1)]
                chatListNavController.popToViewController(targetViewController, animated: animated)
            }
        } else {
            viewControllers[1] = detailPlaceholderVC
        }
    }

    func presentThread(
        threadUniqueId: String,
        action: ConversationViewAction,
        focusMessageId: String?,
        animated: Bool
    ) {
        AssertIsOnMainThread()

        // On iOS 13, and possibly later versions, there is/was a bug in
        // `UISplitViewController` that caused the `isCollapsed` state to fall
        // out of sync while the app isn't active and the orientation has
        // changed while backgrounded. That results in conversations opening in
        // the wrong pane when the app was in portrait but is re-opened in
        // landscape. We work around this by dispatching to the next runloop, at
        // which point things have stabilized.
        if
            let windowScene = view.window?.windowScene,
            windowScene.activationState != .foregroundActive,
            lastActiveInterfaceOrientation != windowScene.interfaceOrientation
        {
            lastActiveInterfaceOrientation = windowScene.interfaceOrientation
            DispatchQueue.main.async {
                self.presentThread(
                    threadUniqueId: threadUniqueId,
                    action: action,
                    focusMessageId: focusMessageId,
                    animated: animated
                )
            }
            return
        }

        if homeVC.selectedHomeTab != .chatList {
            guard homeVC.presentedViewController == nil else {
                homeVC.dismiss(animated: true) {
                    self.presentThread(
                        threadUniqueId: threadUniqueId,
                        action: action,
                        focusMessageId: focusMessageId,
                        animated: animated
                    )
                }
                return
            }

            // Ensure the tab bar is on the chat list.
            homeVC.selectedHomeTab = .chatList
        }

        if
            let selectedThreadUniqueId = selectedThread?.uniqueId,
            selectedThreadUniqueId == threadUniqueId
        {
            guard let selectedConversationVC = selectedConversationViewController else { return }

            // This thread is already selected, so pop to it.
            if isCollapsed {
                chatListNavController.popToViewController(selectedConversationVC, animated: animated)
            } else {
                detailNavController.popToViewController(selectedConversationVC, animated: animated)
            }

            if let focusMessageId {
                selectedConversationVC.ensureInteractionLoadedThenScrollToInteraction(
                    focusMessageId,
                    alignment: .centerIfNotEntirelyOnScreen,
                    isAnimated: animated
                )
            }

            return
        }

        // Update the last viewed thread on the conversation list so it
        // can maintain its scroll position when navigating back.
        homeVC.chatListViewController.updateLastViewedThreadUniqueId(
            threadUniqueId,
            animated: animated
        )

        let conversationViewController = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return ConversationViewController.load(
                appReadiness: appReadiness,
                threadViewModel: ThreadViewModel(
                    threadUniqueId: threadUniqueId,
                    forChatList: false,
                    transaction: tx
                ),
                action: action,
                focusMessageId: focusMessageId,
                tx: tx
            )
        }

        selectedConversationViewController = conversationViewController

        let detailVC: UIViewController = {
            guard !isCollapsed else { return conversationViewController }

            detailNavController.viewControllers = [conversationViewController]
            return detailNavController
        }()

        showDetailViewController(viewController: detailVC, animated: animated)
    }

    func showMyStoriesController(animated: Bool) {
        AssertIsOnMainThread()

        // On iOS 13, there is a bug with UISplitViewController that causes the `isCollapsed` state to
        // get out of sync while the app isn't active and the orientation has changed while backgrounded.
        // This results in conversations opening up in the wrong pane when you were in portrait and then
        // try and open the app in landscape. We work around this by dispatching to the next runloop
        // at which point things have stabilized.
        if let windowScene = view.window?.windowScene, windowScene.activationState != .foregroundActive, lastActiveInterfaceOrientation != windowScene.interfaceOrientation {
            owsFailDebug("check if this still happens")
            // Reset this to avoid getting stuck in a loop. We're becoming active.
            lastActiveInterfaceOrientation = windowScene.interfaceOrientation
            DispatchQueue.main.async { self.showMyStoriesController(animated: animated) }
            return
        }

        if homeVC.selectedHomeTab != .stories {
            guard homeVC.presentedViewController == nil else {
                homeVC.dismiss(animated: true) {
                    self.showMyStoriesController(animated: animated)
                }
                return
            }

            // Ensure the tab bar is on the stories tab.
            homeVC.selectedHomeTab = .stories
        }

        homeVC.storiesViewController.showMyStories(animated: animated)
    }

    override var shouldAutorotate: Bool {
        if let presentedViewController = presentedViewController {
            return presentedViewController.shouldAutorotate
        } else if let selectedConversationViewController = selectedConversationViewController {
            return selectedConversationViewController.shouldAutorotate
        } else {
            return super.shouldAutorotate
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if let presentedViewController = presentedViewController {
            return presentedViewController.supportedInterfaceOrientations
        } else {
            return super.supportedInterfaceOrientations
        }
    }

    // The stock implementation of `showDetailViewController` will in some cases,
    // particularly when launching a conversation from another window, fail to
    // recognize the right context to present the view controller. When this happens,
    // it presents the view modally instead of within the split view controller.
    // We never want this to happen, so we implement a version that knows the
    // correct context is always the split view controller.
    override func showDetailViewController(_ vc: UIViewController, sender _: Any?) {
        showDetailViewController(viewController: vc, animated: true)
    }

    /// Present the given controller as our detail view controller as
    /// appropriate for our current context.
    private weak var currentDetailViewController: UIViewController?
    func showDetailViewController(viewController: UIViewController, animated: Bool) {
        if isCollapsed {
            var viewControllersToDisplay = chatListNavController.viewControllers
            // If we already have a detail VC displayed, we want to replace it.
            // The normal behavior of `showDetailViewController` pushes on
            // top of it in collapsed mode.
            if let currentDetailVC = currentDetailViewController,
               let detailVCIndex = viewControllersToDisplay.firstIndex(of: currentDetailVC) {
                viewControllersToDisplay = Array(viewControllersToDisplay[0..<detailVCIndex])
            }
            viewControllersToDisplay.append(viewController)
            chatListNavController.setViewControllers(viewControllersToDisplay, animated: animated)
        } else {
            // There is a race condition at app launch where `isCollapsed` cannot be
            // relied upon. This leads to a crash where viewControllers is empty, so
            // setting index 1 is not possible. We know what the primary view controller
            // should always be, so we attempt to fill it in when that happens. The only
            // ways this could really be happening is if, somehow, before `viewControllers`
            // is set in init this method is getting called OR this `viewControllers` is
            // returning stale information. The latter seems most plausible, but is near
            // impossible to reproduce.
            owsAssertDebug(viewControllers.first == homeVC)
            viewControllers = [homeVC, viewController]
        }

        // If the detail VC is a nav controller, we want to keep track of
        // the root view controller. We use this to determine the start
        // point of the current detail view when replacing it while
        // collapsed. At that point, this nav controller's view controllers
        // will have been merged into the primary nav controller.
        if let navController = viewController as? UINavigationController {
            currentDetailViewController = navController.viewControllers.first
        } else {
            currentDetailViewController = viewController
        }
    }

    // MARK: - Keyboard Shortcuts

    override var canBecomeFirstResponder: Bool {
        return true
    }

    let chatListKeyCommands = [
        UIKeyCommand(
            action: #selector(showNewConversationView),
            input: "n",
            modifierFlags: .command,
            discoverabilityTitle: OWSLocalizedString(
                "KEY_COMMAND_NEW_MESSAGE",
                comment: "A keyboard command to present the new message dialog."
            )
        ),
        UIKeyCommand(
            action: #selector(showNewGroupView),
            input: "g",
            modifierFlags: .command,
            discoverabilityTitle: OWSLocalizedString(
                "KEY_COMMAND_NEW_GROUP",
                comment: "A keyboard command to present the new group dialog."
            )
        ),
        UIKeyCommand(
            action: #selector(showAppSettings),
            input: ",",
            modifierFlags: .command,
            discoverabilityTitle: CommonStrings.openAppSettingsButton
        ),
        UIKeyCommand(
            action: #selector(focusSearch),
            input: "f",
            modifierFlags: .command,
            discoverabilityTitle: OWSLocalizedString(
                "KEY_COMMAND_SEARCH",
                comment: "A keyboard command to begin a search on the conversation list."
            )
        ),
        UIKeyCommand(
            action: #selector(selectPreviousConversation),
            input: UIKeyCommand.inputUpArrow,
            modifierFlags: .alternate,
            discoverabilityTitle: OWSLocalizedString(
                "KEY_COMMAND_PREVIOUS_CONVERSATION",
                comment: "A keyboard command to jump to the previous conversation in the list."
            )
        ),
        UIKeyCommand(
            action: #selector(selectNextConversation),
            input: UIKeyCommand.inputDownArrow,
            modifierFlags: .alternate,
            discoverabilityTitle: OWSLocalizedString(
                "KEY_COMMAND_NEXT_CONVERSATION",
                comment: "A keyboard command to jump to the next conversation in the list."
            )
        )
    ]

    var selectedConversationKeyCommands: [UIKeyCommand] {
        return [
            UIKeyCommand(
                action: #selector(openConversationSettings),
                input: "i",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_CONVERSATION_INFO",
                    comment: "A keyboard command to open the current conversation's settings."
                )
            ),
            UIKeyCommand(
                action: #selector(openAllMedia),
                input: "m",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_ALL_MEDIA",
                    comment: "A keyboard command to open the current conversation's all media view."
                )
            ),
            UIKeyCommand(
                action: #selector(openGifSearch),
                input: "g",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_GIF_SEARCH",
                    comment: "A keyboard command to open the current conversations GIF picker."
                )
            ),
            UIKeyCommand(
                action: #selector(openAttachmentKeyboard),
                input: "u",
                modifierFlags: .command,
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_ATTACHMENTS",
                    comment: "A keyboard command to open the current conversation's attachment picker."
                )
            ),
            UIKeyCommand(
                action: #selector(openStickerKeyboard),
                input: "s",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_STICKERS",
                    comment: "A keyboard command to open the current conversation's sticker picker."
                )
            ),
            UIKeyCommand(
                action: #selector(archiveSelectedConversation),
                input: "a",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_ARCHIVE",
                    comment: "A keyboard command to archive the current conversation."
                )
            ),
            UIKeyCommand(
                action: #selector(unarchiveSelectedConversation),
                input: "u",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_UNARCHIVE",
                    comment: "A keyboard command to unarchive the current conversation."
                )
            ),
            UIKeyCommand(
                action: #selector(focusInputToolbar),
                input: "t",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_FOCUS_COMPOSER",
                    comment: "A keyboard command to focus the current conversation's input field."
                )
            )
        ]
    }

    override var keyCommands: [UIKeyCommand]? {
        // If there is a modal presented over us, or another window above us, don't respond to keyboard commands.
        guard presentedViewController == nil || view.window?.isKeyWindow != true else { return nil }

        // Don't allow keyboard commands while presenting context menu.
        guard selectedConversationViewController?.isPresentingContextMenu != true else { return nil }

        var keyCommands = [UIKeyCommand]()
        if selectedThread != nil {
            keyCommands += selectedConversationKeyCommands
        }
        if homeVC.selectedHomeTab == .chatList {
            keyCommands += chatListKeyCommands
        }
        return keyCommands
    }

    @objc
    func showNewConversationView() {
        homeVC.chatListViewController.showNewConversationView()
    }

    @objc
    func showNewGroupView() {
        homeVC.chatListViewController.showNewGroupView()
    }

    @objc
    func showAppSettings() {
        homeVC.chatListViewController.showAppSettings()
    }

    func showAppSettingsWithMode(_ mode: ChatListViewController.ShowAppSettingsMode) {
        homeVC.chatListViewController.showAppSettings(mode: mode)
    }

    @objc
    func focusSearch() {
        homeVC.chatListViewController.focusSearch()
    }

    @objc
    func selectPreviousConversation() {
        homeVC.chatListViewController.selectPreviousConversation()
    }

    @objc
    func selectNextConversation(_ sender: UIKeyCommand) {
        homeVC.chatListViewController.selectNextConversation()
    }

    @objc
    func archiveSelectedConversation() {
        homeVC.chatListViewController.archiveSelectedConversation()
    }

    @objc
    func unarchiveSelectedConversation() {
        homeVC.chatListViewController.unarchiveSelectedConversation()
    }

    @objc
    func openConversationSettings() {
        guard let selectedConversationViewController = selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }

        selectedConversationViewController.showConversationSettings()
    }

    @objc
    func focusInputToolbar() {
        guard let selectedConversationViewController = selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }

        selectedConversationViewController.focusInputToolbar()
    }

    @objc
    func openAllMedia() {
        guard let selectedConversationViewController = selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }

        selectedConversationViewController.openAllMedia()
    }

    @objc
    func openStickerKeyboard() {
        guard let selectedConversationViewController = selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }

        selectedConversationViewController.openStickerKeyboard()
    }

    @objc
    func openAttachmentKeyboard() {
        guard let selectedConversationViewController = selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }

        selectedConversationViewController.openAttachmentKeyboard()
    }

    @objc
    func openGifSearch() {
        guard let selectedConversationViewController = selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }

        selectedConversationViewController.openGifSearch()
    }
}

extension ConversationSplitViewController: UISplitViewControllerDelegate {
    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {

        // If we're currently showing the placeholder view, we want to do nothing with in
        // when collapsing into a single nav controller without a side panel.
        guard secondaryViewController != detailPlaceholderVC else { return true }

        assert(secondaryViewController == detailNavController)

        // Move all the views from the detail nav controller onto the primary nav controller.
        let detailViewControllers = detailNavController.viewControllers
        // Clear the detailNavController's view controllers first to avoid a UIKit
        // crash that happens if you don't.
        detailNavController.viewControllers = []
        chatListNavController.viewControllers += detailViewControllers

        return true
    }

    func splitViewController(_ splitViewController: UISplitViewController, separateSecondaryFrom primaryViewController: UIViewController) -> UIViewController? {
        assert(primaryViewController == homeVC)

        // See if the current conversation is currently in the view hierarchy. If not,
        // show the placeholder view as no conversation is selected. The conversation
        // was likely popped from the stack while the split view was collapsed.
        guard let currentConversationVC = selectedConversationViewController,
              let conversationVCIndex = chatListNavController.viewControllers.firstIndex(of: currentConversationVC) else {
            self.selectedConversationViewController = nil
            return detailPlaceholderVC
        }

        // Move everything on the nav stack from the conversation view on back onto
        // the detail nav controller.

        let allViewControllers = chatListNavController.viewControllers

        chatListNavController.viewControllers = Array(allViewControllers[0..<conversationVCIndex]).filter { vc in
            // Don't ever allow a conversation view controller to be transferred on the master
            // stack when expanding from collapsed mode. This should never happen.
            guard let vc = vc as? ConversationViewController else { return true }
            owsFailDebug("Unexpected conversation in view hierarchy: \(vc.thread.logString)")
            return false
        }

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
        guard isCollapsed, viewController is ChatListViewController else { return }
        selectedConversationViewController = nil
    }

    func navigationController(_ navigationController: UINavigationController, interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return navigationTransitionDelegate?.navigationController?(
            navigationController,
            interactionControllerFor: animationController
        )
    }

    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return navigationTransitionDelegate?.navigationController?(
            navigationController,
            animationControllerFor: operation,
            from: fromVC,
            to: toVC
        )
    }
}

extension ConversationViewController {
    var conversationSplitViewController: ConversationSplitViewController? {
        return splitViewController as? ConversationSplitViewController
    }
}

private class NoSelectedConversationViewController: OWSViewController {
    let logoImageView = UIImageView()

    override func loadView() {
        view = UIView()
        view.backgroundColor = UIColor.Signal.background

        logoImageView.image = #imageLiteral(resourceName: "signal-logo-128").withRenderingMode(.alwaysTemplate)
        logoImageView.tintColor = UIColor.Signal.quaternaryLabel
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.autoSetDimension(.height, toSize: 112)
        view.addSubview(logoImageView)

        logoImageView.autoCenterInSuperview()
    }
}

extension ConversationSplitViewController: DeviceTransferServiceObserver {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        AppEnvironment.shared.deviceTransferServiceRef.addObserver(self)
        AppEnvironment.shared.deviceTransferServiceRef.startListeningForNewDevices()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let windowScene = view.window?.windowScene, windowScene.activationState == .foregroundActive {
            lastActiveInterfaceOrientation = windowScene.interfaceOrientation
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        AppEnvironment.shared.deviceTransferServiceRef.removeObserver(self)
        AppEnvironment.shared.deviceTransferServiceRef.stopListeningForNewDevices()
    }

    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?) {
        guard deviceTransferNavController?.presentingViewController == nil else { return }
        let navController = OutgoingDeviceTransferNavigationController()
        deviceTransferNavController = navController
        navController.present(fromViewController: self)
    }

    func deviceTransferServiceDidStartTransfer(progress: Progress) {}

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {}

    func deviceTransferServiceDidRequestAppRelaunch() {}
}
