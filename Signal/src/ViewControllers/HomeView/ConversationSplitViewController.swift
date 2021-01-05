//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import MultipeerConnectivity

@objc
class ConversationSplitViewController: UISplitViewController, ConversationSplit {

    fileprivate var deviceTransferNavController: DeviceTransferNavigationController?

    private let conversationListVC = ConversationListViewController()
    private let detailPlaceholderVC = NoSelectedConversationViewController()

    private lazy var primaryNavController = OWSNavigationController(rootViewController: conversationListVC)
    private lazy var detailNavController = OWSNavigationController()
    private lazy var lastActiveInterfaceOrientation = CurrentAppContext().interfaceOrientation

    @objc private(set) weak var selectedConversationViewController: ConversationViewController?

    /// The thread, if any, that is currently presented in the view hieararchy. It may be currently
    /// covered by a modal presentation or a pushed view controller.
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

    /// Returns the currently selected thread if it is visible on screen, otherwise
    /// returns nil.
    @objc var visibleThread: TSThread? {
        guard view.window?.isKeyWindow == true else { return nil }
        guard selectedConversationViewController?.isViewVisible == true else { return nil }
        return selectedThread
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

    @objc func applyTheme() {
        view.backgroundColor = Theme.secondaryBackgroundColor
        applyNavBarStyle(collapsed: isCollapsed)
    }

    @objc func orientationDidChange() {
        AssertIsOnMainThread()
        guard UIApplication.shared.applicationState == .active else { return }
        lastActiveInterfaceOrientation = CurrentAppContext().interfaceOrientation
    }

    @objc func didBecomeActive() {
        AssertIsOnMainThread()
        lastActiveInterfaceOrientation = CurrentAppContext().interfaceOrientation
    }

    func applyNavBarStyle(collapsed: Bool) {
        guard let owsNavBar = primaryNavController.navigationBar as? OWSNavigationBar else {
            return owsFailDebug("unexpected nav bar")
        }
        owsNavBar.switchToStyle(collapsed ? .default : .secondaryBar)
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
            if let selectedConversationIndex = primaryNavController.viewControllers.firstIndex(of: selectedConversationViewController) {
                let targetViewController = primaryNavController.viewControllers[max(0, selectedConversationIndex-1)]
                primaryNavController.popToViewController(targetViewController, animated: animated)
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

        let threadViewModel = databaseStorage.uiRead {
            return ThreadViewModel(thread: thread, transaction: $0)
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
            var viewControllersToDisplay = primaryNavController.viewControllers
            // If we already have a detail VC displayed, we want to replace it.
            // The normal behavior of `showDetailViewController` pushes on
            // top of it in collapsed mode.
            if let currentDetailVC = currentDetailViewController,
                let detailVCIndex = viewControllersToDisplay.firstIndex(of: currentDetailVC) {
                viewControllersToDisplay = Array(viewControllersToDisplay[0..<detailVCIndex])
            }
            viewControllersToDisplay.append(vc)
            primaryNavController.setViewControllers(viewControllersToDisplay, animated: true)
        } else {
            viewControllers[1] = vc
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

    let globalKeyCommands = [
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
                    comment: "A keyboard command to archive the current coversation."
                )
            ),
            UIKeyCommand(
                input: "u",
                modifierFlags: [.command, .shift],
                action: #selector(unarchiveSelectedConversation),
                discoverabilityTitle: NSLocalizedString(
                    "KEY_COMMAND_UNARCHIVE",
                    comment: "A keyboard command to unarchive the current coversation."
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

        // Don't allow keyboard commands while presenting message actions.
        guard selectedConversationViewController?.isPresentingMessageActions != true else { return nil }

        if selectedThread != nil {
            return selectedConversationKeyCommands + globalKeyCommands
        } else {
            return globalKeyCommands
        }
    }

    @objc func showNewConversationView() {
        conversationListVC.showNewConversationView()
    }

    @objc func showNewGroupView() {
        conversationListVC.showNewGroupView()
    }

    @objc func showAppSettings() {
        conversationListVC.showAppSettings()
    }

    @objc func focusSearch() {
        conversationListVC.focusSearch()
    }

    @objc func selectPreviousConversation() {
        conversationListVC.selectPreviousConversation()
    }

    @objc func selectNextConversation(_ sender: UIKeyCommand) {
        conversationListVC.selectNextConversation()
    }

    @objc func archiveSelectedConversation() {
        conversationListVC.archiveSelectedConversation()
    }

    @objc func unarchiveSelectedConversation() {
        conversationListVC.unarchiveSelectedConversation()
    }

    @objc func openConversationSettings() {
        guard let selectedConversationViewController = selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }

        selectedConversationViewController.showConversationSettings()
    }

    @objc func focusInputToolbar() {
        guard let selectedConversationViewController = selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }

        selectedConversationViewController.focusInputToolbar()
    }

    @objc func openAllMedia() {
        guard let selectedConversationViewController = selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }

        selectedConversationViewController.openAllMedia()
    }

    @objc func openStickerKeyboard() {
        guard let selectedConversationViewController = selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }

        selectedConversationViewController.openStickerKeyboard()
    }

    @objc func openAttachmentKeyboard() {
        guard let selectedConversationViewController = selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }

        selectedConversationViewController.openAttachmentKeyboard()
    }

    @objc func openGifSearch() {
        guard let selectedConversationViewController = selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }

        selectedConversationViewController.openGifSearch()
    }
}

extension ConversationSplitViewController: UISplitViewControllerDelegate {
    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
        applyNavBarStyle(collapsed: true)

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

        applyNavBarStyle(collapsed: false)

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

        primaryNavController.viewControllers = Array(allViewControllers[0..<conversationVCIndex]).filter { vc in
            // Don't ever allow a conversation view controller to be transfered on the master
            // stack when expanding from collapsed mode. This should never happen.
            guard let vc = vc as? ConversationViewController else { return true }
            owsFailDebug("Unexpected conversation in view hierarchy: \(vc.thread.uniqueId)")
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
    let titleLabel = UILabel()
    let bodyLabel = UILabel()
    let logoImageView = UIImageView()

    override func loadView() {
        view = UIView()

        let logoContainer = UIView.container()
        logoImageView.image = #imageLiteral(resourceName: "signal-logo-128").withRenderingMode(.alwaysTemplate)
        logoImageView.contentMode = .scaleAspectFit
        logoContainer.addSubview(logoImageView)
        logoImageView.autoPinTopToSuperviewMargin()
        logoImageView.autoPinBottomToSuperviewMargin(withInset: 8)
        logoImageView.autoHCenterInSuperview()
        logoImageView.autoSetDimension(.height, toSize: 72)

        titleLabel.font = UIFont.ows_dynamicTypeBody.ows_semibold
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.text = NSLocalizedString("NO_SELECTED_CONVERSATION_TITLE", comment: "Title welcoming to the app")

        bodyLabel.font = .ows_dynamicTypeBody
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.text = NSLocalizedString("NO_SELECTED_CONVERSATION_DESCRIPTION", comment: "Explanation of how to see a conversation.")

        let centerStackView = UIStackView(arrangedSubviews: [logoContainer, titleLabel, bodyLabel])
        centerStackView.axis = .vertical
        centerStackView.spacing = 4
        view.addSubview(centerStackView)
        // Slightly offset from center to better optically center
        centerStackView.autoAlignAxis(.horizontal, toSameAxisOf: view, withMultiplier: 0.88)
        centerStackView.autoPinWidthToSuperview()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self, selector: #selector(self.applyTheme), name: .ThemeDidChange, object: nil)

        applyTheme()
    }

    @objc func applyTheme() {
        view.backgroundColor = Theme.backgroundColor
        titleLabel.textColor = Theme.primaryTextColor
        bodyLabel.textColor = Theme.secondaryTextAndIconColor
        logoImageView.tintColor = Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_gray65
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
