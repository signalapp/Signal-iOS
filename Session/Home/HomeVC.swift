// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import DifferenceKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

final class HomeVC: BaseVC, UITableViewDataSource, UITableViewDelegate, SeedReminderViewDelegate {
    private static let loadingHeaderHeight: CGFloat = 20
    public static let newConversationButtonSize: CGFloat = 60
    
    private let viewModel: HomeViewModel = HomeViewModel()
    private var dataChangeObservable: DatabaseCancellable?
    private var hasLoadedInitialStateData: Bool = false
    private var hasLoadedInitialThreadData: Bool = false
    private var isLoadingMore: Bool = false
    private var isAutoLoadingNextPage: Bool = false
    private var viewHasAppeared: Bool = false
    
    // MARK: - Intialization
    
    init() {
        Storage.shared.addObserver(viewModel.pagedDataObserver)
        
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init() instead.")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
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
        result.isHidden = !self.viewModel.state.showViewedSeedBanner
        
        return result
    }()
    
    private lazy var loadingConversationsLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = UIFont.systemFont(ofSize: Values.smallFontSize)
        result.text = "LOADING_CONVERSATIONS".localized()
        result.textColor = Colors.text
        result.textAlignment = .center
        result.numberOfLines = 0
        
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
                Values.largeSpacing +
                HomeVC.newConversationButtonSize
            ),
            right: 0
        )
        result.showsVerticalScrollIndicator = false
        result.register(view: MessageRequestsCell.self)
        result.register(view: FullConversationCell.self)
        result.dataSource = self
        result.delegate = self
        
        if #available(iOS 15.0, *) {
            result.sectionHeaderTopPadding = 0
        }
        
        return result
    }()
    
    private lazy var newConversationButton: UIButton = {
        let result = UIButton(type: .system)
        let iconSize = CGFloat(24)
        let icon = #imageLiteral(resourceName: "Plus").scaled(to: CGSize(width: iconSize, height: iconSize))
        let glowConfiguration = UIView.CircularGlowConfiguration(
            size: Self.newConversationButtonSize,
            color: Colors.expandedButtonGlowColor,
            isAnimated: false,
            radius: isLightMode ? 4 : 6
        )
        result.setImage(icon, for: .normal)
        result.set(.width, to: Self.newConversationButtonSize)
        result.set(.height, to: Self.newConversationButtonSize)
        result.contentMode = .center
        result.backgroundColor = Colors.accent
        result.layer.cornerRadius = Self.newConversationButtonSize / 2
        result.setCircularGlow(with: glowConfiguration)
        result.layer.masksToBounds = false
        result.tintColor = .white
        result.addTarget(self, action: #selector(createNewConversation), for: .touchUpInside)
        
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
        createNewPrivateChatButton.set(.width, to: Values.iPadButtonWidth)
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
        view.addSubview(seedReminderView)
        seedReminderView.pin(.leading, to: .leading, of: view)
        seedReminderView.pin(.top, to: .top, of: view)
        seedReminderView.pin(.trailing, to: .trailing, of: view)
        
        // Loading conversations label
        view.addSubview(loadingConversationsLabel)
        
        loadingConversationsLabel.pin(.top, to: .top, of: view, withInset: Values.veryLargeSpacing)
        loadingConversationsLabel.pin(.leading, to: .leading, of: view, withInset: 50)
        loadingConversationsLabel.pin(.trailing, to: .trailing, of: view, withInset: -50)
        
        // Table view
        view.addSubview(tableView)
        tableView.pin(.leading, to: .leading, of: view)
        if self.viewModel.state.showViewedSeedBanner {
            tableViewTopConstraint = tableView.pin(.top, to: .bottom, of: seedReminderView)
        }
        else {
            tableViewTopConstraint = tableView.pin(.top, to: .top, of: view)
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
        
        // New conversation button
        view.addSubview(newConversationButton)
        newConversationButton.center(.horizontal, in: view)
        newConversationButton.pin(.bottom, to: .bottom, of: view, withInset: -Values.newConversationButtonBottomOffset) // Negative due to how the constraint is set up
        
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
        
        // Start polling if needed (i.e. if the user just created or restored their Session ID)
        if Identity.userExists(), let appDelegate: AppDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.startPollersIfNeeded()
            
            // Do this only if we created a new Session ID, or if we already received the initial configuration message
            if UserDefaults.standard[.hasSyncedInitialConfiguration] {
                appDelegate.syncConfigurationIfNeeded()
            }
        }
        
        // Onion request path countries cache
        IP2Country.shared.populateCacheIfNeededAsync()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        startObservingChanges()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.viewHasAppeared = true
        self.autoLoadNextPageIfNeeded()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        stopObservingChanges()
    }
    
    @objc func applicationDidBecomeActive(_ notification: Notification) {
        startObservingChanges(didReturnFromBackground: true)
    }
    
    @objc func applicationDidResignActive(_ notification: Notification) {
        stopObservingChanges()
    }
    
    // MARK: - Updating
    
    private func startObservingChanges(didReturnFromBackground: Bool = false) {
        // Start observing for data changes
        dataChangeObservable = Storage.shared.start(
            viewModel.observableState,
            // If we haven't done the initial load the trigger it immediately (blocking the main
            // thread so we remain on the launch screen until it completes to be consistent with
            // the old behaviour)
            scheduling: (hasLoadedInitialStateData ?
                .async(onQueue: .main) :
                .immediate
            ),
            onError: { _ in },
            onChange: { [weak self] state in
                // The default scheduler emits changes on the main thread
                self?.handleUpdates(state)
            }
        )
        
        self.viewModel.onThreadChange = { [weak self] updatedThreadData in
            self?.handleThreadUpdates(updatedThreadData)
        }
        
        // Note: When returning from the background we could have received notifications but the
        // PagedDatabaseObserver won't have them so we need to force a re-fetch of the current
        // data to ensure everything is up to date
        if didReturnFromBackground {
            self.viewModel.pagedDataObserver?.reload()
        }
    }
    
    private func stopObservingChanges() {
        // Stop observing database changes
        dataChangeObservable?.cancel()
        self.viewModel.onThreadChange = nil
    }
    
    private func handleUpdates(_ updatedState: HomeViewModel.State, initialLoad: Bool = false) {
        // Ensure the first load runs without animations (if we don't do this the cells will animate
        // in from a frame of CGRect.zero)
        guard hasLoadedInitialStateData else {
            hasLoadedInitialStateData = true
            UIView.performWithoutAnimation { handleUpdates(updatedState, initialLoad: true) }
            return
        }
        
        if updatedState.userProfile != self.viewModel.state.userProfile {
            updateNavBarButtons()
        }
        
        // Update the 'view seed' UI
        if updatedState.showViewedSeedBanner != self.viewModel.state.showViewedSeedBanner {
            tableViewTopConstraint.isActive = false
            seedReminderView.isHidden = !updatedState.showViewedSeedBanner
            
            if updatedState.showViewedSeedBanner {
                tableViewTopConstraint = tableView.pin(.top, to: .bottom, of: seedReminderView)
            }
            else {
                tableViewTopConstraint = tableView.pin(.top, to: .top, of: view, withInset: Values.smallSpacing)
            }
        }
        
        self.viewModel.updateState(updatedState)
    }
    
    private func handleThreadUpdates(_ updatedData: [HomeViewModel.SectionModel], initialLoad: Bool = false) {
        // Ensure the first load runs without animations (if we don't do this the cells will animate
        // in from a frame of CGRect.zero)
        guard hasLoadedInitialThreadData else {
            hasLoadedInitialThreadData = true
            UIView.performWithoutAnimation { handleThreadUpdates(updatedData, initialLoad: true) }
            return
        }
        
        // Hide the 'loading conversations' label (now that we have received conversation data)
        loadingConversationsLabel.isHidden = true
        
        // Show the empty state if there is no data
        emptyStateView.isHidden = (
            !updatedData.isEmpty &&
            updatedData.contains(where: { !$0.elements.isEmpty })
        )
        
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            // Complete page loading
            self?.isLoadingMore = false
            self?.autoLoadNextPageIfNeeded()
        }
        
        // Reload the table content (animate changes after the first load)
        tableView.reload(
            using: StagedChangeset(source: viewModel.threadData, target: updatedData),
            deleteSectionsAnimation: .none,
            insertSectionsAnimation: .none,
            reloadSectionsAnimation: .none,
            deleteRowsAnimation: .bottom,
            insertRowsAnimation: .none,
            reloadRowsAnimation: .none,
            interrupt: { $0.changeCount > 100 }    // Prevent too many changes from causing performance issues
        ) { [weak self] updatedData in
            self?.viewModel.updateThreadData(updatedData)
        }
        
        CATransaction.commit()
    }
    
    private func autoLoadNextPageIfNeeded() {
        guard !self.isAutoLoadingNextPage && !self.isLoadingMore else { return }
        
        self.isAutoLoadingNextPage = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + PagedData.autoLoadNextPageDelay) { [weak self] in
            self?.isAutoLoadingNextPage = false
            
            // Note: We sort the headers as we want to prioritise loading newer pages over older ones
            let sections: [(HomeViewModel.Section, CGRect)] = (self?.viewModel.threadData
                .enumerated()
                .map { index, section in (section.model, (self?.tableView.rectForHeader(inSection: index) ?? .zero)) })
                .defaulting(to: [])
            let shouldLoadMore: Bool = sections
                .contains { section, headerRect in
                    section == .loadMore &&
                    headerRect != .zero &&
                    (self?.tableView.bounds.contains(headerRect) == true)
                }
            
            guard shouldLoadMore else { return }
            
            self?.isLoadingMore = true
            
            DispatchQueue.global(qos: .default).async { [weak self] in
                self?.viewModel.pagedDataObserver?.load(.pageAfter)
            }
        }
    }
    
    private func updateNewConversationButton() {
        let glowConfiguration = UIView.CircularGlowConfiguration(
            size: Self.newConversationButtonSize,
            color: Colors.expandedButtonGlowColor,
            isAnimated: false,
            radius: isLightMode ? 4 : 6
        )
        newConversationButton.setCircularGlow(with: glowConfiguration)
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
        updateNewConversationButton()
        tableView.reloadData()
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.threadData.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let section: HomeViewModel.SectionModel = viewModel.threadData[section]
        
        return section.elements.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section: HomeViewModel.SectionModel = viewModel.threadData[indexPath.section]
        
        switch section.model {
            case .messageRequests:
                let threadViewModel: SessionThreadViewModel = section.elements[indexPath.row]
                let cell: MessageRequestsCell = tableView.dequeue(type: MessageRequestsCell.self, for: indexPath)
                cell.update(with: Int(threadViewModel.threadUnreadCount ?? 0))
                return cell
                
            case .threads:
                let threadViewModel: SessionThreadViewModel = section.elements[indexPath.row]
                let cell: FullConversationCell = tableView.dequeue(type: FullConversationCell.self, for: indexPath)
                cell.update(with: threadViewModel)
                return cell
                
            default: preconditionFailure("Other sections should have no content")
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section: HomeViewModel.SectionModel = viewModel.threadData[section]
        
        switch section.model {
            case .loadMore:
                let loadingIndicator: UIActivityIndicatorView = UIActivityIndicatorView(style: .medium)
                loadingIndicator.tintColor = Colors.text
                loadingIndicator.alpha = 0.5
                loadingIndicator.startAnimating()
                
                let view: UIView = UIView()
                view.addSubview(loadingIndicator)
                loadingIndicator.center(in: view)
                
                return view
            
            default: return nil
        }
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section: HomeViewModel.SectionModel = viewModel.threadData[section]
        
        switch section.model {
            case .loadMore: return HomeVC.loadingHeaderHeight
            default: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard self.hasLoadedInitialThreadData && self.viewHasAppeared && !self.isLoadingMore else { return }
        
        let section: HomeViewModel.SectionModel = self.viewModel.threadData[section]
        
        switch section.model {
            case .loadMore:
                self.isLoadingMore = true
                
                DispatchQueue.global(qos: .default).async { [weak self] in
                    self?.viewModel.pagedDataObserver?.load(.pageAfter)
                }
                
            default: break
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let section: HomeViewModel.SectionModel = self.viewModel.threadData[indexPath.section]
        
        switch section.model {
            case .messageRequests:
                let viewController: MessageRequestsViewController = MessageRequestsViewController()
                self.navigationController?.pushViewController(viewController, animated: true)
                
            case .threads:
                let threadViewModel: SessionThreadViewModel = section.elements[indexPath.row]
                show(
                    threadViewModel.threadId,
                    variant: threadViewModel.threadVariant,
                    isMessageRequest: (threadViewModel.threadIsMessageRequest == true),
                    with: .none,
                    focusedInteractionId: nil,
                    animated: true
                )
                
            default: break
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let section: HomeViewModel.SectionModel = self.viewModel.threadData[indexPath.section]
        
        switch section.model {
            case .messageRequests:
                let hide = UITableViewRowAction(style: .destructive, title: "TXT_HIDE_TITLE".localized()) { _, _ in
                    Storage.shared.write { db in db[.hasHiddenMessageRequests] = true }
                }
                hide.backgroundColor = Colors.destructive
                
                return [hide]
                
            case .threads:
                let threadViewModel: SessionThreadViewModel = section.elements[indexPath.row]
                let delete: UITableViewRowAction = UITableViewRowAction(
                    style: .destructive,
                    title: "TXT_DELETE_TITLE".localized()
                ) { [weak self] _, _ in
                    let message = (threadViewModel.currentUserIsClosedGroupAdmin == true ?
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
                        Storage.shared.writeAsync { db in
                            switch threadViewModel.threadVariant {
                                case .closedGroup:
                                    try MessageSender
                                        .leave(db, groupPublicKey: threadViewModel.threadId)
                                        .retainUntilComplete()
                                    
                                case .openGroup:
                                    OpenGroupManager.shared.delete(db, openGroupId: threadViewModel.threadId)
                                    
                                default: break
                            }
                            
                            _ = try SessionThread
                                .filter(id: threadViewModel.threadId)
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
                    title: (threadViewModel.threadIsPinned ?
                        "UNPIN_BUTTON_TEXT".localized() :
                        "PIN_BUTTON_TEXT".localized()
                    )
                ) { _, _ in
                    Storage.shared.writeAsync { db in
                        try SessionThread
                            .filter(id: threadViewModel.threadId)
                            .updateAll(db, SessionThread.Columns.isPinned.set(to: !threadViewModel.threadIsPinned))
                    }
                }
                
                guard threadViewModel.threadVariant == .contact && !threadViewModel.threadIsNoteToSelf else {
                    return [ delete, pin ]
                }

                let block: UITableViewRowAction = UITableViewRowAction(
                    style: .normal,
                    title: (threadViewModel.threadIsBlocked == true ?
                        "BLOCK_LIST_UNBLOCK_BUTTON".localized() :
                        "BLOCK_LIST_BLOCK_BUTTON".localized()
                    )
                ) { _, _ in
                    Storage.shared.writeAsync { db in
                        try Contact
                            .filter(id: threadViewModel.threadId)
                            .updateAll(
                                db,
                                Contact.Columns.isBlocked.set(
                                    to: (threadViewModel.threadIsBlocked == false ?
                                        true:
                                        false
                                    )
                                )
                            )
                        
                        try MessageSender.syncConfiguration(db, forceSyncNow: true)
                            .retainUntilComplete()
                    }
                }
                block.backgroundColor = Colors.blockActionBackground
                
                return [ delete, block, pin ]
                
            default: return []
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
        variant: SessionThread.Variant,
        isMessageRequest: Bool,
        with action: ConversationViewModel.Action,
        focusedInteractionId: Int64?,
        animated: Bool
    ) {
        if let presentedVC = self.presentedViewController {
            presentedVC.dismiss(animated: false, completion: nil)
        }
        
        let finalViewControllers: [UIViewController] = [
            self,
            (isMessageRequest ? MessageRequestsViewController() : nil),
            ConversationVC(
                threadId: threadId,
                threadVariant: variant,
                focusedInteractionId: focusedInteractionId
            )
        ].compactMap { $0 }
        
        self.navigationController?.setViewControllers(finalViewControllers, animated: animated)
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
    
    @objc func createNewConversation() {
        let newConversationVC = NewConversationVC()
        let navigationController = OWSNavigationController(rootViewController: newConversationVC)
        if UIDevice.current.isIPad {
            navigationController.modalPresentationStyle = .fullScreen
        }
        navigationController.modalPresentationCapturesStatusBarAppearance = true
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc func createNewDM() {
        let newDMVC = NewDMVC(shouldShowBackButton: false)
        let navigationController = OWSNavigationController(rootViewController: newDMVC)
        if UIDevice.current.isIPad {
            navigationController.modalPresentationStyle = .fullScreen
        }
        navigationController.modalPresentationCapturesStatusBarAppearance = true
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc(createNewDMFromDeepLink:)
    func createNewDMFromDeepLink(sessionID: String) {
        let newDMVC = NewDMVC(sessionID: sessionID, shouldShowBackButton: false)
        let navigationController = OWSNavigationController(rootViewController: newDMVC)
        if UIDevice.current.isIPad {
            navigationController.modalPresentationStyle = .fullScreen
        }
        navigationController.modalPresentationCapturesStatusBarAppearance = true
        present(navigationController, animated: true, completion: nil)
    }
}
