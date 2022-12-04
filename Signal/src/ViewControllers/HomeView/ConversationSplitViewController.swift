//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity
import SignalMessaging
import SignalUI

@objc
class ConversationSplitViewController: UISplitViewController, ConversationSplit {

    fileprivate var deviceTransferNavController: DeviceTransferNavigationController?

    let homeVC = HomeTabBarController()
    private let detailPlaceholderVC = NoSelectedConversationViewController()

    private var chatListNavController: OWSNavigationController { homeVC.chatListNavController }
    private lazy var detailNavController = OWSNavigationController()
    private lazy var lastActiveInterfaceOrientation = CurrentAppContext().interfaceOrientation

    @objc
    private(set) weak var selectedConversationViewController: ConversationViewController?

    weak var navigationTransitionDelegate: UINavigationControllerDelegate?

    /// The thread, if any, that is currently presented in the view hieararchy. It may be currently
    /// covered by a modal presentation or a pushed view controller.
    @objc
    var selectedThread: TSThread? {
        // If the placeholder view is in the view hierarchy, there is no selected thread.
        guard detailPlaceholderVC.view.superview == nil else { return nil }
        guard let selectedConversationViewController = selectedConversationViewController else { return nil }

        // In order to not show selected when collapsed during an interactive dismissal,
        // we verify the conversation is still in the nav stack when collapsed. There is
        // no interactive dismissal when expanded, so we don't have to do any special check.
        guard !isCollapsed || chatListNavController.viewControllers.contains(selectedConversationViewController) else { return nil }

        return selectedConversationViewController.thread
    }

    /// Returns the currently selected thread if it is visible on screen, otherwise
    /// returns nil.
    @objc
    var visibleThread: TSThread? {
        guard view.window?.isKeyWindow == true else { return nil }
        guard selectedConversationViewController?.isViewVisible == true else { return nil }
        return selectedThread
    }

    @objc
    var topViewController: UIViewController? {
        guard !isCollapsed else {
            return chatListNavController.topViewController
        }

        return detailNavController.topViewController ?? chatListNavController.topViewController
    }

    @objc
    init() {
        super.init(nibName: nil, bundle: nil)

        viewControllers = [homeVC, detailPlaceholderVC]

        chatListNavController.delegate = self
        detailNavController.delegate = self
        delegate = self
        preferredDisplayMode = .allVisible

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .ThemeDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: UIDevice.current
        )
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: .OWSApplicationDidBecomeActive, object: nil)

        applyTheme()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
    }

    @objc
    func applyTheme() {
        view.backgroundColor = Theme.isDarkThemeEnabled ? UIColor(rgbHex: 0x292929) : UIColor(rgbHex: 0xd6d6d6)
    }

    @objc
    func orientationDidChange() {
        AssertIsOnMainThread()
        guard UIApplication.shared.applicationState == .active else { return }
        lastActiveInterfaceOrientation = CurrentAppContext().interfaceOrientation
    }

    @objc
    func didBecomeActive() {
        AssertIsOnMainThread()
        lastActiveInterfaceOrientation = CurrentAppContext().interfaceOrientation
    }

    private var hasHiddenExtraSubivew = false
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        // We don't want to hide anything on iOS 13, as the extra subview no longer exists
        if #available(iOS 13, *) { hasHiddenExtraSubivew = true }

        // HACK: UISplitViewController adds an extra subview behind the navigation
        // bar area that extends across both views. As far as I can tell, it's not
        // possible to adjust the color of this view. It gets reset constantly.
        // Without this fix, the space between the primary and detail view has a
        // hairline of the wrong color, most apparent in dark mode.
        guard !hasHiddenExtraSubivew, let firstSubview = view.subviews.first,
              !viewControllers.map({ $0.view }).contains(firstSubview) else { return }
        hasHiddenExtraSubivew = true
        firstSubview.isHidden = true
    }

    @objc(closeSelectedConversationAnimated:)
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

    @objc
    func presentThread(_ thread: TSThread, action: ConversationViewAction, focusMessageId: String?, animated: Bool) {
        AssertIsOnMainThread()

        // On iOS 13, there is a bug with UISplitViewController that causes the `isCollapsed` state to
        // get out of sync while the app isn't active and the orientation has changed while backgrounded.
        // This results in conversations opening up in the wrong pane when you were in portrait and then
        // try and open the app in landscape. We work around this by dispatching to the next runloop
        // at which point things have stabilized.
        if #available(iOS 13, *), UIApplication.shared.applicationState != .active, lastActiveInterfaceOrientation != CurrentAppContext().interfaceOrientation {
            if #available(iOS 14, *) { owsFailDebug("check if this still happens") }
            // Reset this to avoid getting stuck in a loop. We're becoming active.
            lastActiveInterfaceOrientation = CurrentAppContext().interfaceOrientation
            DispatchQueue.main.async { self.presentThread(thread, action: action, focusMessageId: focusMessageId, animated: animated) }
            return
        }

        if homeVC.selectedTab != .chatList {
            guard homeVC.presentedViewController == nil else {
                homeVC.dismiss(animated: true) {
                    self.presentThread(thread, action: action, focusMessageId: focusMessageId, animated: animated)
                }
                return
            }

            // Ensure the tab bar is on the chat list.
            homeVC.selectedTab = .chatList
        }

        guard selectedThread?.uniqueId != thread.uniqueId else {
            // If this thread is already selected, pop to the thread if
            // anything else has been presented above the view.
            guard let selectedConversationVC = selectedConversationViewController else { return }
            if isCollapsed {
                chatListNavController.popToViewController(selectedConversationVC, animated: animated)
            } else {
                detailNavController.popToViewController(selectedConversationVC, animated: animated)
            }
            return
        }

        // Update the last viewed thread on the conversation list so it
        // can maintain its scroll position when navigating back.
        homeVC.chatListViewController.updateLastViewedThread(thread, animated: animated)

        let threadViewModel = databaseStorage.read {
            return ThreadViewModel(thread: thread,
                                   forChatList: false,
                                   transaction: $0)
        }
        let vc = ConversationViewController(threadViewModel: threadViewModel, action: action, focusMessageId: focusMessageId)

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
    private weak var currentDetailViewController: UIViewController?
    override func showDetailViewController(_ vc: UIViewController, sender: Any?) {
        if isCollapsed {
            var viewControllersToDisplay = chatListNavController.viewControllers
            // If we already have a detail VC displayed, we want to replace it.
            // The normal behavior of `showDetailViewController` pushes on
            // top of it in collapsed mode.
            if let currentDetailVC = currentDetailViewController,
               let detailVCIndex = viewControllersToDisplay.firstIndex(of: currentDetailVC) {
                viewControllersToDisplay = Array(viewControllersToDisplay[0..<detailVCIndex])
            }
            viewControllersToDisplay.append(vc)
            chatListNavController.setViewControllers(viewControllersToDisplay, animated: true)
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
            viewControllers = [homeVC, vc]
        }

        // If the detail VC is a nav controller, we want to keep track of
        // the root view controller. We use this to determine the start
        // point of the current detail view when replacing it while
        // collapsed. At that point, this nav controller's view controllers
        // will have been merged into the primary nav controller.
        if let vc = vc as? UINavigationController {
            currentDetailViewController = vc.viewControllers.first
        } else {
            currentDetailViewController = vc
        }
    }

    // MARK: - Keyboard Shortcuts

    override var canBecomeFirstResponder: Bool {
        return true
    }

    let chatListKeyCommands = [
        UIKeyCommand(
            input: "n",
            modifierFlags: .command,
            action: #selector(showNewConversationView),
            discoverabilityTitle: NSLocalizedString(
                "KEY_COMMAND_NEW_MESSAGE",
                comment: "A keyboard command to present the new message dialog."
            )
        ),
        UIKeyCommand(
            input: "g",
            modifierFlags: .command,
            action: #selector(showNewGroupView),
            discoverabilityTitle: NSLocalizedString(
                "KEY_COMMAND_NEW_GROUP",
                comment: "A keyboard command to present the new group dialog."
            )
        ),
        UIKeyCommand(
            input: ",",
            modifierFlags: .command,
            action: #selector(showAppSettings),
            discoverabilityTitle: NSLocalizedString(
                "KEY_COMMAND_SETTINGS",
                comment: "A keyboard command to present the application settings dialog."
            )
        ),
        UIKeyCommand(
            input: "f",
            modifierFlags: .command,
            action: #selector(focusSearch),
            discoverabilityTitle: NSLocalizedString(
                "KEY_COMMAND_SEARCH",
                comment: "A keyboard command to begin a search on the conversation list."
            )
        ),
        UIKeyCommand(
            input: UIKeyCommand.inputUpArrow,
            modifierFlags: .alternate,
            action: #selector(selectPreviousConversation),
            discoverabilityTitle: NSLocalizedString(
                "KEY_COMMAND_PREVIOUS_CONVERSATION",
                comment: "A keyboard command to jump to the previous conversation in the list."
            )
        ),
        UIKeyCommand(
            input: UIKeyCommand.inputDownArrow,
            modifierFlags: .alternate,
            action: #selector(selectNextConversation),
            discoverabilityTitle: NSLocalizedString(
                "KEY_COMMAND_NEXT_CONVERSATION",
                comment: "A keyboard command to jump to the next conversation in the list."
            )
        )
    ]

    var selectedConversationKeyCommands: [UIKeyCommand] {
        return [
            UIKeyCommand(
                input: "i",
                modifierFlags: [.command, .shift],
                action: #selector(openConversationSettings),
                discoverabilityTitle: NSLocalizedString(
                    "KEY_COMMAND_CONVERSATION_INFO",
                    comment: "A keyboard command to open the current conversation's settings."
                )
            ),
            UIKeyCommand(
                input: "m",
                modifierFlags: [.command, .shift],
                action: #selector(openAllMedia),
                discoverabilityTitle: NSLocalizedString(
                    "KEY_COMMAND_ALL_MEDIA",
                    comment: "A keyboard command to open the current conversation's all media view."
                )
            ),
            UIKeyCommand(
                input: "g",
                modifierFlags: [.command, .shift],
                action: #selector(openGifSearch),
                discoverabilityTitle: NSLocalizedString(
                    "KEY_COMMAND_GIF_SEARCH",
                    comment: "A keyboard command to open the current conversations GIF picker."
                )
            ),
            UIKeyCommand(
                input: "u",
                modifierFlags: .command,
                action: #selector(openAttachmentKeyboard),
                discoverabilityTitle: NSLocalizedString(
                    "KEY_COMMAND_ATTACHMENTS",
                    comment: "A keyboard command to open the current conversation's attachment picker."
                )
            ),
            UIKeyCommand(
                input: "s",
                modifierFlags: [.command, .shift],
                action: #selector(openStickerKeyboard),
                discoverabilityTitle: NSLocalizedString(
                    "KEY_COMMAND_STICKERS",
                    comment: "A keyboard command to open the current conversation's sticker picker."
                )
            ),
            UIKeyCommand(
                input: "a",
                modifierFlags: [.command, .shift],
                action: #selector(archiveSelectedConversation),
                discoverabilityTitle: NSLocalizedString(
                    "KEY_COMMAND_ARCHIVE",
                    comment: "A keyboard command to archive the current conversation."
                )
            ),
            UIKeyCommand(
                input: "u",
                modifierFlags: [.command, .shift],
                action: #selector(unarchiveSelectedConversation),
                discoverabilityTitle: NSLocalizedString(
                    "KEY_COMMAND_UNARCHIVE",
                    comment: "A keyboard command to unarchive the current conversation."
                )
            ),
            UIKeyCommand(
                input: "t",
                modifierFlags: [.command, .shift],
                action: #selector(focusInputToolbar),
                discoverabilityTitle: NSLocalizedString(
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
        if homeVC.selectedTab == .chatList {
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

    func showAppSettingsWithMode(_ mode: ShowAppSettingsMode) {
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
        chatListNavController.viewControllers += detailNavController.viewControllers

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
            owsFailDebug("Unexpected conversation in view hierarchy: \(vc.thread.uniqueId)")
            return false
        }

        // Create a new detail nav because reusing the existing one causes
        // some strange behavior around the title view + input accessory view.
        // TODO iPad: Maybe investigate this further.
        detailNavController = OWSNavigationController()
        detailNavController.delegate = self
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

@objc
extension ChatListViewController {
    var conversationSplitViewController: ConversationSplitViewController? {
        return splitViewController as? ConversationSplitViewController
    }
}

extension StoriesViewController {
    var conversationSplitViewController: ConversationSplitViewController? {
        return splitViewController as? ConversationSplitViewController
    }
}

@objc
extension ConversationViewController {
    var conversationSplitViewController: ConversationSplitViewController? {
        return splitViewController as? ConversationSplitViewController
    }
}

private class NoSelectedConversationViewController: OWSViewController {
    let logoImageView = UIImageView()

    override func loadView() {
        view = UIView()

        logoImageView.image = #imageLiteral(resourceName: "signal-logo-128").withRenderingMode(.alwaysTemplate)
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.autoSetDimension(.height, toSize: 112)
        view.addSubview(logoImageView)

        logoImageView.autoCenterInSuperview()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        applyTheme()
    }

    @objc
    override func themeDidChange() {
        super.themeDidChange()
        applyTheme()
    }

    private func applyTheme() {
        view.backgroundColor = Theme.backgroundColor
        logoImageView.tintColor = Theme.isDarkThemeEnabled ? UIColor.white.withAlphaComponent(0.12) : UIColor.black.withAlphaComponent(0.12)
    }
}

extension ConversationSplitViewController: DeviceTransferServiceObserver {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        deviceTransferService.addObserver(self)
        deviceTransferService.startListeningForNewDevices()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        deviceTransferService.removeObserver(self)
        deviceTransferService.stopListeningForNewDevices()
    }

    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?) {
        guard deviceTransferNavController?.presentingViewController == nil else { return }
        let navController = DeviceTransferNavigationController()
        deviceTransferNavController = navController
        navController.present(fromViewController: self)
    }

    func deviceTransferServiceDidStartTransfer(progress: Progress) {}

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {}
}
