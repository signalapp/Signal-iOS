// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import DifferenceKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

final class HomeVC: BaseVC, UITableViewDataSource, UITableViewDelegate, NewConversationButtonSetDelegate, SeedReminderViewDelegate {
    typealias Section = HomeViewModel.Section
    typealias Item = HomeViewModel.Item
    
    private let viewModel: HomeViewModel = HomeViewModel()
    private var dataChangeObservable: DatabaseCancellable?
    private var hasLoadedInitialData: Bool = false
    
    // MARK: - UI
    
    private var tableViewTopConstraint: NSLayoutConstraint!
    
    private lazy var seedReminderView: SeedReminderView = {
        let result = SeedReminderView(hasContinueButton: true)
        let title = "You're almost finished! 80%"
        let attributedTitle = NSMutableAttributedString(string: title)
        attributedTitle.addAttribute(.foregroundColor, value: Colors.accent, range: (title as NSString).range(of: "80%"))
        result.title = attributedTitle
        result.subtitle = NSLocalizedString("view_seed_reminder_subtitle_1", comment: "")
        result.setProgress(0.8, animated: false)
        result.delegate = self
        
        return result
    }()
        
    private lazy var tableView: UITableView = {
        let result = UITableView()
        result.backgroundColor = .clear
        result.separatorStyle = .none
        result.contentInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: (
                Values.newConversationButtonBottomOffset +
                NewConversationButtonSet.expandedButtonSize +
                Values.largeSpacing +
                NewConversationButtonSet.collapsedButtonSize
            ),
            right: 0
        )
        result.showsVerticalScrollIndicator = false
        result.register(view: MessageRequestsCell.self)
        result.register(view: ConversationCell.self)
        result.dataSource = self
        result.delegate = self
        
        return result
    }()

    private lazy var newConversationButtonSet: NewConversationButtonSet = {
        let result = NewConversationButtonSet()
        result.delegate = self
        return result
    }()
    
    private lazy var fadeView: UIView = {
        let result = UIView()
        let gradient = Gradients.homeVCFade
        result.setGradient(gradient)
        result.isUserInteractionEnabled = false
        
        return result
    }()

    private lazy var emptyStateView: UIView = {
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.textAlignment = .center
        explanationLabel.text = NSLocalizedString("vc_home_empty_state_message", comment: "")
        let createNewPrivateChatButton = Button(style: .prominentOutline, size: .large)
        createNewPrivateChatButton.setTitle(NSLocalizedString("vc_home_empty_state_button_title", comment: ""), for: UIControl.State.normal)
        createNewPrivateChatButton.addTarget(self, action: #selector(createNewDM), for: UIControl.Event.touchUpInside)
        createNewPrivateChatButton.set(.width, to: 196)
        let result = UIStackView(arrangedSubviews: [ explanationLabel, createNewPrivateChatButton ])
        result.axis = .vertical
        result.spacing = Values.mediumSpacing
        result.alignment = .center
        result.isHidden = true
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Note: This is a hack to ensure `isRTL` is initially gets run on the main thread so the value
        // is cached (it gets called on background threads and if it hasn't cached the value then it can
        // cause odd performance issues since it accesses UIKit)
        _ = CurrentAppContext().isRTL
        
        // Preparation
        SessionApp.homeViewController.mutate { $0 = self }
        
        // Gradient & nav bar
        setUpGradientBackground()
        if navigationController?.navigationBar != nil {
            setUpNavBarStyle()
        }
        updateNavBarButtons()
        setUpNavBarSessionHeading()
        // Recovery phrase reminder
        let hasViewedSeed = UserDefaults.standard[.hasViewedSeed]
        if !hasViewedSeed {
            view.addSubview(seedReminderView)
            seedReminderView.pin(.leading, to: .leading, of: view)
            seedReminderView.pin(.top, to: .top, of: view)
            seedReminderView.pin(.trailing, to: .trailing, of: view)
        }
        
        // Table view
        view.addSubview(tableView)
        tableView.pin(.leading, to: .leading, of: view)
        if !hasViewedSeed {
            tableViewTopConstraint = tableView.pin(.top, to: .bottom, of: seedReminderView)
        } else {
            tableViewTopConstraint = tableView.pin(.top, to: .top, of: view, withInset: Values.smallSpacing)
        }
        tableView.pin(.trailing, to: .trailing, of: view)
        tableView.pin(.bottom, to: .bottom, of: view)
        view.addSubview(fadeView)
        fadeView.pin(.leading, to: .leading, of: view)
        let topInset = 0.15 * view.height()
        fadeView.pin(.top, to: .top, of: view, withInset: topInset)
        fadeView.pin(.trailing, to: .trailing, of: view)
        fadeView.pin(.bottom, to: .bottom, of: view)
        
        // Empty state view
        view.addSubview(emptyStateView)
        emptyStateView.center(.horizontal, in: view)
        let verticalCenteringConstraint = emptyStateView.center(.vertical, in: view)
        verticalCenteringConstraint.constant = -16 // Makes things appear centered visually
        
        // New conversation button set
        view.addSubview(newConversationButtonSet)
        newConversationButtonSet.center(.horizontal, in: view)
        newConversationButtonSet.pin(.bottom, to: .bottom, of: view, withInset: -Values.newConversationButtonBottomOffset) // Negative due to how the constraint is set up
        
        // Notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        
        notificationCenter.addObserver(self, selector: #selector(handleProfileDidChangeNotification(_:)), name: .otherUsersProfileDidChange, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleLocalProfileDidChangeNotification(_:)), name: .localProfileDidChange, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleSeedViewedNotification(_:)), name: .seedViewed, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleBlockedContactsUpdatedNotification(_:)), name: .blockedContactsUpdated, object: nil)
        
        // Start polling if needed (i.e. if the user just created or restored their Session ID)
        if Identity.userExists(), let appDelegate: AppDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.startPollersIfNeeded()
            
            // Do this only if we created a new Session ID, or if we already received the initial configuration message
            if UserDefaults.standard[.hasSyncedInitialConfiguration] {
                appDelegate.syncConfigurationIfNeeded()
            }
        }
        
        // Onion request path countries cache
        DispatchQueue.global(qos: .utility).sync {
            let _ = IP2Country.shared.populateCacheIfNeeded()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        startObservingChanges()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Stop observing database changes
        dataChangeObservable?.cancel()
    }
    
    @objc func applicationDidBecomeActive(_ notification: Notification) {
        startObservingChanges()
    }
    
    @objc func applicationDidResignActive(_ notification: Notification) {
        // Stop observing database changes
        dataChangeObservable?.cancel()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
        
    // MARK: - Updating
    
    private func startObservingChanges() {
        // Start observing for data changes
        dataChangeObservable = GRDBStorage.shared.start(
            viewModel.observableViewData,
            onError:  { error in
                print("Update error!!!!")
            },
            onChange: { [weak self] viewData in
                // The defaul scheduler emits changes on the main thread
                self?.handleUpdates(viewData)
            }
        )
    }
    
    private func handleUpdates(_ updatedViewData: [ArraySection<Section, Item>]) {
        // Ensure the first load runs without animations (if we don't do this the cells will animate
        // in from a frame of CGRect.zero)
        guard hasLoadedInitialData else {
            hasLoadedInitialData = true
            UIView.performWithoutAnimation { handleUpdates(updatedViewData) }
            return
        }
        
        // Show the empty state if there is no data
        emptyStateView.isHidden = (
            !updatedViewData.isEmpty &&
            updatedViewData.contains(where: { !$0.elements.isEmpty })
        )
        
        // Reload the table content (animate changes after the first load)
        tableView.reload(
            using: StagedChangeset(source: viewModel.viewData, target: updatedViewData),
            with: .automatic,
            interrupt: {
                print("Interrupt change check: \($0.changeCount)")
                return $0.changeCount > 100
            }    // Prevent too many changes from causing performance issues
        ) { [weak self] updatedData in
            self?.viewModel.updateData(updatedData)
        }
    }
    
    @objc private func handleProfileDidChangeNotification(_ notification: Notification) {
        DispatchQueue.main.async {
            self.tableView.reloadData() // TODO: Just reload the affected cell
        }
    }
    
    @objc private func handleLocalProfileDidChangeNotification(_ notification: Notification) {
        DispatchQueue.main.async {
            self.updateNavBarButtons()
        }
    }
    
    @objc private func handleSeedViewedNotification(_ notification: Notification) {
        tableViewTopConstraint.isActive = false
        tableViewTopConstraint = tableView.pin(.top, to: .top, of: view, withInset: Values.smallSpacing)
        seedReminderView.removeFromSuperview()
    }

    @objc private func handleBlockedContactsUpdatedNotification(_ notification: Notification) {
        self.tableView.reloadData() // TODO: Just reload the affected cell
    }
    
    private func updateNavBarButtons() {
        // Profile picture view
        let profilePictureSize = Values.verySmallProfilePictureSize
        let profilePictureView = ProfilePictureView()
        profilePictureView.accessibilityLabel = "Settings button"
        profilePictureView.size = profilePictureSize
        profilePictureView.update(
            publicKey: getUserHexEncodedPublicKey(),
            profile: Profile.fetchOrCreateCurrentUser(),
            threadVariant: .contact
        )
        profilePictureView.set(.width, to: profilePictureSize)
        profilePictureView.set(.height, to: profilePictureSize)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(openSettings))
        profilePictureView.addGestureRecognizer(tapGestureRecognizer)
        
        // Path status indicator
        let pathStatusView = PathStatusView()
        pathStatusView.accessibilityLabel = "Current onion routing path indicator"
        pathStatusView.set(.width, to: PathStatusView.size)
        pathStatusView.set(.height, to: PathStatusView.size)
        
        // Container view
        let profilePictureViewContainer = UIView()
        profilePictureViewContainer.accessibilityLabel = "Settings button"
        profilePictureViewContainer.addSubview(profilePictureView)
        profilePictureView.autoPinEdgesToSuperviewEdges()
        profilePictureViewContainer.addSubview(pathStatusView)
        pathStatusView.pin(.trailing, to: .trailing, of: profilePictureViewContainer)
        pathStatusView.pin(.bottom, to: .bottom, of: profilePictureViewContainer)
        
        // Left bar button item
        let leftBarButtonItem = UIBarButtonItem(customView: profilePictureViewContainer)
        leftBarButtonItem.accessibilityLabel = "Settings button"
        leftBarButtonItem.isAccessibilityElement = true
        navigationItem.leftBarButtonItem = leftBarButtonItem
        
        // Right bar button item - search button
        let rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(showSearchUI))
        rightBarButtonItem.accessibilityLabel = "Search button"
        rightBarButtonItem.isAccessibilityElement  = true
        navigationItem.rightBarButtonItem = rightBarButtonItem
    }

    @objc override internal func handleAppModeChangedNotification(_ notification: Notification) {
        super.handleAppModeChangedNotification(notification)
        
        let gradient = Gradients.homeVCFade
        fadeView.setGradient(gradient) // Re-do the gradient
        tableView.reloadData()
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.viewData.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.viewData[section].elements.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section: ArraySection<Section, Item> = viewModel.viewData[indexPath.section]
        
        switch section.model {
            case .messageRequests:
                let cell: MessageRequestsCell = tableView.dequeue(type: MessageRequestsCell.self, for: indexPath)
                cell.update(with: section.elements[indexPath.row].unreadCount)
                return cell
                
            case .threads:
                let cell: ConversationCell = tableView.dequeue(type: ConversationCell.self, for: indexPath)
                cell.update(with: section.elements[indexPath.row].threadInfo)
                return cell
        }
    }
    
    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let section: ArraySection<Section, Item> = viewModel.viewData[indexPath.section]
        
        switch section.model {
            case .messageRequests:
                let viewController: MessageRequestsViewController = MessageRequestsViewController()
                self.navigationController?.pushViewController(viewController, animated: true)
                
            case .threads:
                let threadId: String = section.elements[indexPath.row].threadInfo.id
                show(threadId, with: .none, highlightedInteractionId: nil, animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let section: ArraySection<Section, Item> = viewModel.viewData[indexPath.section]
        
        switch section.model {
            case .messageRequests:
                let hide = UITableViewRowAction(style: .destructive, title: NSLocalizedString("TXT_HIDE_TITLE", comment: "")) { [weak self] _, _ in
                    GRDBStorage.shared.write { db in db[.hasHiddenMessageRequests] = true }

                    // Animate the row removal
                    self?.tableView.beginUpdates()
                    self?.tableView.deleteRows(at: [indexPath], with: .automatic)
                    self?.tableView.endUpdates()
                }
                hide.backgroundColor = Colors.destructive
                
                return [hide]
                
            case .threads:
                let threadInfo: HomeViewModel.ThreadInfo = section.elements[indexPath.row].threadInfo
                let delete: UITableViewRowAction = UITableViewRowAction(
                    style: .destructive,
                    title: "TXT_DELETE_TITLE".localized()
                ) { [weak self] _, _ in
                    let message = (threadInfo.isGroupAdmin ?
                        "admin_group_leave_warning".localized() :
                        "CONVERSATION_DELETE_CONFIRMATION_ALERT_MESSAGE".localized()
                    )
                    
                    let alert = UIAlertController(
                        title: "CONVERSATION_DELETE_CONFIRMATION_ALERT_TITLE".localized(),
                        message: message,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(
                        title: "TXT_DELETE_TITLE".localized(),
                        style: .destructive
                    ) { _ in
                        GRDBStorage.shared.write { db in
                            switch threadInfo.variant {
                                case .closedGroup:
                                    try MessageSender
                                        .leave(db, groupPublicKey: threadInfo.id)
                                        .retainUntilComplete()
                                    
                                case .openGroup:
                                    OpenGroupManagerV2.shared.delete(db, openGroupId: threadInfo.id)
                                    
                                default: break
                            }
                            
                            _ = try SessionThread
                                .filter(id: threadInfo.id)
                                .deleteAll(db)
                        }
                    })
                    alert.addAction(UIAlertAction(
                        title: "TXT_CANCEL_TITLE".localized(),
                        style: .default
                    ))
                    
                    self?.present(alert, animated: true, completion: nil)
                }
                delete.backgroundColor = Colors.destructive

                let pin: UITableViewRowAction = UITableViewRowAction(
                    style: .normal,
                    title: (threadInfo.isPinned ?
                        "PIN_BUTTON_TEXT".localized() :
                        "UNPIN_BUTTON_TEXT".localized()
                    )
                ) { _, _ in
                    GRDBStorage.shared.write { db in
                        try SessionThread
                            .filter(id: threadInfo.id)
                            .updateAll(db, SessionThread.Columns.isPinned.set(to: !threadInfo.isPinned))
                    }
                }
                
                guard threadInfo.variant == .contact && !threadInfo.isNoteToSelf else {
                    return [ delete, pin ]
                }

                let block: UITableViewRowAction = UITableViewRowAction(
                    style: .normal,
                    title: (threadInfo.isBlocked ?
                        "BLOCK_LIST_UNBLOCK_BUTTON".localized() :
                        "BLOCK_LIST_BLOCK_BUTTON".localized()
                    )
                ) { _, _ in
                    GRDBStorage.shared.write { db in
                        try Contact
                            .filter(id: threadInfo.id)
                            .updateAll(db, Contact.Columns.isBlocked.set(to: !threadInfo.isBlocked))
                        try MessageSender.syncConfiguration(db, forceSyncNow: true)
                            .retainUntilComplete()
                    }
                }
                block.backgroundColor = Colors.unimportant
                
                return [ delete, block, pin ]
        }
    }
    
    // MARK: - Interaction
    
    func handleContinueButtonTapped(from seedReminderView: SeedReminderView) {
        let seedVC = SeedVC()
        let navigationController = OWSNavigationController(rootViewController: seedVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    func show(
        _ threadId: String,
        with action: ConversationViewModel.Action,
        highlightedInteractionId: Int64?,
        animated: Bool
    ) {
        guard let conversationVC: ConversationVC = ConversationVC(threadId: threadId) else {
            return
        }
        
        if let presentedVC = self.presentedViewController {
            presentedVC.dismiss(animated: false, completion: nil)
        }
        self.navigationController?.setViewControllers([ self, conversationVC ], animated: true)
    }
    
    @objc private func openSettings() {
        let settingsVC = SettingsVC()
        let navigationController = OWSNavigationController(rootViewController: settingsVC)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc private func showSearchUI() {
        if let presentedVC = self.presentedViewController {
            presentedVC.dismiss(animated: false, completion: nil)
        }
        let searchController = GlobalSearchViewController()
        self.navigationController?.setViewControllers([ self, searchController ], animated: true)
    }
    
    @objc func joinOpenGroup() {
        let joinOpenGroupVC = JoinOpenGroupVC()
        let navigationController = OWSNavigationController(rootViewController: joinOpenGroupVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc func createNewDM() {
        let newDMVC = NewDMVC()
        let navigationController = OWSNavigationController(rootViewController: newDMVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc(createNewDMFromDeepLink:)
    func createNewDMFromDeepLink(sessionID: String) {
        let newDMVC = NewDMVC(sessionID: sessionID)
        let navigationController = OWSNavigationController(rootViewController: newDMVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc func createClosedGroup() {
        let newClosedGroupVC = NewClosedGroupVC()
        let navigationController = OWSNavigationController(rootViewController: newClosedGroupVC)
        present(navigationController, animated: true, completion: nil)
    }
}
