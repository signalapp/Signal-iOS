
final class HomeVC : BaseVC, UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate, UIViewControllerPreviewingDelegate, NewConversationButtonSetDelegate, SeedReminderViewDelegate {
    private var threadViewModelCache: [String:ThreadViewModel] = [:]
    private var isObservingDatabase = true
    private var isViewVisible = false { didSet { updateIsObservingDatabase() } }
    private var tableViewTopConstraint: NSLayoutConstraint!
    private var wasDatabaseModifiedExternally = false
    
    private var threads: YapDatabaseViewMappings = {
        let result = YapDatabaseViewMappings(groups: [ TSInboxGroup ], view: TSThreadDatabaseViewExtensionName)
        result.setIsReversed(true, forGroup: TSInboxGroup)
        return result
    }()
    
    private let uiDatabaseConnection: YapDatabaseConnection = {
        let result = OWSPrimaryStorage.shared().newDatabaseConnection()
        result.objectCacheLimit = 500
        return result
    }()
    
    private let editingDatabaseConnection = OWSPrimaryStorage.shared().newDatabaseConnection()

    private var threadCount: UInt {
        threads.numberOfItems(inGroup: TSInboxGroup)
    }
    
    // MARK: Components
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
    
    private lazy var searchBar = SearchBar()
    
    private lazy var tableView: UITableView = {
        let result = UITableView()
        result.backgroundColor = .clear
        result.separatorStyle = .none
        result.register(ConversationCell.self, forCellReuseIdentifier: ConversationCell.reuseIdentifier)
        let bottomInset = Values.newConversationButtonBottomOffset + Values.newConversationButtonExpandedSize + Values.largeSpacing + Values.newConversationButtonCollapsedSize
        result.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        result.showsVerticalScrollIndicator = false
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
        createNewPrivateChatButton.addTarget(self, action: #selector(createNewPrivateChat), for: UIControl.Event.touchUpInside)
        createNewPrivateChatButton.set(.width, to: 196)
        let result = UIStackView(arrangedSubviews: [ explanationLabel, createNewPrivateChatButton ])
        result.axis = .vertical
        result.spacing = Values.mediumSpacing
        result.alignment = .center
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        SignalApp.shared().homeViewController = self
        setUpGradientBackground()
        if navigationController?.navigationBar != nil {
            setUpNavBarStyle()
        }
        updateNavigationBarButtons()
        setNavBarTitle("Messages")
        // Set up seed reminder view if needed
        let userDefaults = UserDefaults.standard
        let hasViewedSeed = userDefaults[.hasViewedSeed]
        if !hasViewedSeed {
            view.addSubview(seedReminderView)
            seedReminderView.pin(.leading, to: .leading, of: view)
            seedReminderView.pin(.top, to: .top, of: view)
            seedReminderView.pin(.trailing, to: .trailing, of: view)
        }
        // Set up table view
        tableView.dataSource = self
        tableView.delegate = self
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
        // Set up empty state view
        view.addSubview(emptyStateView)
        emptyStateView.center(.horizontal, in: view)
        let verticalCenteringConstraint = emptyStateView.center(.vertical, in: view)
        verticalCenteringConstraint.constant = -16 // Makes things appear centered visually
        // Set up new conversation button set
        view.addSubview(newConversationButtonSet)
        newConversationButtonSet.center(.horizontal, in: view)
        newConversationButtonSet.pin(.bottom, to: .bottom, of: view, withInset: -Values.newConversationButtonBottomOffset) // Negative due to how the constraint is set up
        // Set up previewing
        if traitCollection.forceTouchCapability == .available {
            registerForPreviewing(with: self, sourceView: tableView)
        }
        // Listen for notifications
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleYapDatabaseModifiedNotification(_:)), name: .YapDatabaseModified, object: OWSPrimaryStorage.shared().dbNotificationObject)
        notificationCenter.addObserver(self, selector: #selector(handleApplicationDidBecomeActiveNotification(_:)), name: .OWSApplicationDidBecomeActive, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleApplicationWillResignActiveNotification(_:)), name: .OWSApplicationWillResignActive, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleProfileDidChangeNotification(_:)), name: NSNotification.Name(rawValue: kNSNotificationName_OtherUsersProfileDidChange), object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleLocalProfileDidChangeNotification(_:)), name: Notification.Name(kNSNotificationName_LocalProfileDidChange), object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleSeedViewedNotification(_:)), name: .seedViewed, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleBlockedContactsUpdatedNotification(_:)), name: .blockedContactsUpdated, object: nil)
        // Set up public chats and RSS feeds if needed
        if OWSIdentityManager.shared().identityKeyPair() != nil {
            let appDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.startPollerIfNeeded()
            appDelegate.startClosedGroupPollerIfNeeded()
            appDelegate.startOpenGroupPollersIfNeeded()
        }
        // Populate onion request path countries cache
        DispatchQueue.global(qos: .utility).async {
            let _ = IP2Country.shared.populateCacheIfNeeded()
        }
        // Do initial update
        reload()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isViewVisible = true
        UserDefaults.standard[.hasLaunchedOnce] = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        isViewVisible = false
        super.viewWillDisappear(animated)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Data
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Int(threadCount)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ConversationCell.reuseIdentifier) as! ConversationCell
        cell.threadViewModel = threadViewModel(at: indexPath.row)
        return cell
    }
        
    // MARK: Updating
    private func updateIsObservingDatabase() {
        isObservingDatabase = isViewVisible && CurrentAppContext().isAppForegroundAndActive()
    }
    
    private func reload() {
        AssertIsOnMainThread()
        uiDatabaseConnection.beginLongLivedReadTransaction()
        uiDatabaseConnection.read { transaction in
            self.threads.update(with: transaction)
        }
        threadViewModelCache.removeAll()
        tableView.reloadData()
        emptyStateView.isHidden = (threadCount != 0)
    }

    @objc private func handleYapDatabaseModifiedNotification(_ notification: Notification) {
        AssertIsOnMainThread()
        let notifications = uiDatabaseConnection.beginLongLivedReadTransaction()
        let ext = uiDatabaseConnection.ext(TSThreadDatabaseViewExtensionName) as! YapDatabaseViewConnection
        let hasChanges = ext.hasChanges(forGroup: TSInboxGroup, in: notifications)
        guard isObservingDatabase else {
            wasDatabaseModifiedExternally = hasChanges
            return
        }
        guard hasChanges else {
            uiDatabaseConnection.read { transaction in
                self.threads.update(with: transaction)
            }
            return
        }
        // If changes were made in a different process (e.g. the Notification Service Extension) the thread mapping can be out of date
        // at this point, causing the app to crash. The code below prevents that by force syncing the database before proceeding.
        if notifications.count > 0 {
            if let firstChangeSet = notifications[0].userInfo {
                let firstSnapshot = firstChangeSet[YapDatabaseSnapshotKey] as! UInt64
                if threads.snapshotOfLastUpdate != firstSnapshot - 1 {
                    return reload()
                }
            }
        }
        var sectionChanges = NSArray()
        var rowChanges = NSArray()
        ext.getSectionChanges(&sectionChanges, rowChanges: &rowChanges, for: notifications, with: threads)
        guard sectionChanges.count > 0 || rowChanges.count > 0 else { return }
        tableView.beginUpdates()
        rowChanges.forEach { rowChange in
            let rowChange = rowChange as! YapDatabaseViewRowChange
            let key = rowChange.collectionKey.key
            threadViewModelCache[key] = nil
            switch rowChange.type {
            case .delete: tableView.deleteRows(at: [ rowChange.indexPath! ], with: UITableView.RowAnimation.fade)
            case .insert: tableView.insertRows(at: [ rowChange.newIndexPath! ], with: UITableView.RowAnimation.fade)
            case .move:
                tableView.deleteRows(at: [ rowChange.indexPath! ], with: UITableView.RowAnimation.fade)
                tableView.insertRows(at: [ rowChange.newIndexPath! ], with: UITableView.RowAnimation.fade)
            case .update:
                tableView.reloadRows(at: [ rowChange.indexPath! ], with: UITableView.RowAnimation.none)
            default: break
            }
        }
        tableView.endUpdates()
        emptyStateView.isHidden = (threadCount != 0)
    }
    
    @objc private func handleApplicationDidBecomeActiveNotification(_ notification: Notification) {
        updateIsObservingDatabase()
        if wasDatabaseModifiedExternally {
            reload()
            wasDatabaseModifiedExternally = false
        }
    }
    
    @objc private func handleApplicationWillResignActiveNotification(_ notification: Notification) {
        updateIsObservingDatabase()
    }
    
    @objc private func handleProfileDidChangeNotification(_ notification: Notification) {
        tableView.reloadData() // TODO: Just reload the affected cell
    }
    
    @objc private func handleLocalProfileDidChangeNotification(_ notification: Notification) {
        updateNavigationBarButtons()
    }
    
    @objc private func handleSeedViewedNotification(_ notification: Notification) {
        tableViewTopConstraint.isActive = false
        tableViewTopConstraint = tableView.pin(.top, to: .top, of: view, withInset: Values.smallSpacing)
        seedReminderView.removeFromSuperview()
    }

    @objc private func handleBlockedContactsUpdatedNotification(_ notification: Notification) {
        self.tableView.reloadData() // TODO: Just reload the affected cell
    }
    
    private func updateNavigationBarButtons() {
        let profilePictureSize = Values.verySmallProfilePictureSize
        let profilePictureView = ProfilePictureView()
        profilePictureView.size = profilePictureSize
        profilePictureView.hexEncodedPublicKey = getUserHexEncodedPublicKey()
        profilePictureView.update()
        profilePictureView.set(.width, to: profilePictureSize)
        profilePictureView.set(.height, to: profilePictureSize)
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(openSettings))
        profilePictureView.addGestureRecognizer(tapGestureRecognizer)
        let profilePictureViewContainer = UIView()
        profilePictureViewContainer.addSubview(profilePictureView)
        profilePictureView.pin(.leading, to: .leading, of: profilePictureViewContainer, withInset: 4)
        profilePictureView.pin(.top, to: .top, of: profilePictureViewContainer)
        profilePictureView.pin(.trailing, to: .trailing, of: profilePictureViewContainer)
        profilePictureView.pin(.bottom, to: .bottom, of: profilePictureViewContainer)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: profilePictureViewContainer)
        let pathStatusViewContainer = UIView()
        let pathStatusViewContainerSize = Values.verySmallProfilePictureSize // Match the profile picture view
        pathStatusViewContainer.set(.width, to: pathStatusViewContainerSize)
        pathStatusViewContainer.set(.height, to: pathStatusViewContainerSize)
        let pathStatusView = PathStatusView()
        pathStatusView.set(.width, to: Values.pathStatusViewSize)
        pathStatusView.set(.height, to: Values.pathStatusViewSize)
        pathStatusViewContainer.addSubview(pathStatusView)
        pathStatusView.center(.horizontal, in: pathStatusViewContainer)
        pathStatusView.center(.vertical, in: pathStatusViewContainer)
        pathStatusViewContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showPath)))
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: pathStatusViewContainer)
    }

    @objc override internal func handleAppModeChangedNotification(_ notification: Notification) {
        super.handleAppModeChangedNotification(notification)
        let gradient = Gradients.homeVCFade
        fadeView.setGradient(gradient) // Re-do the gradient
        tableView.reloadData()
    }
    
    // MARK: Interaction
    func handleContinueButtonTapped(from seedReminderView: SeedReminderView) {
        let seedVC = SeedVC()
        let navigationController = OWSNavigationController(rootViewController: seedVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        searchBar.resignFirstResponder()
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        guard let indexPath = tableView.indexPathForRow(at: location), let thread = self.thread(at: indexPath.row) else { return nil }
        previewingContext.sourceRect = tableView.rectForRow(at: indexPath)
        let conversationVC = ConversationViewController()
        conversationVC.configure(for: thread, action: .none, focusMessageId: nil)
        conversationVC.peekSetup()
        return conversationVC
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        guard let conversationVC = viewControllerToCommit as? ConversationViewController else { return }
        conversationVC.popped()
        navigationController?.pushViewController(conversationVC, animated: false)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let thread = self.thread(at: indexPath.row) else { return }
        show(thread, with: ConversationViewAction.none, highlightedMessageID: nil, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    @objc func show(_ thread: TSThread, with action: ConversationViewAction, highlightedMessageID: String?, animated: Bool) {
        DispatchMainThreadSafe {
            if let presentedVC = self.presentedViewController {
                presentedVC.dismiss(animated: false, completion: nil)
            }
            let conversationVC = ConversationViewController()
            conversationVC.configure(for: thread, action: action, focusMessageId: highlightedMessageID)
            self.navigationController?.setViewControllers([ self, conversationVC ], animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        guard let thread = self.thread(at: indexPath.row) else { return [] }
        let publicChat = Storage.shared.getOpenGroup(for: thread.uniqueId!)
        let delete = UITableViewRowAction(style: .destructive, title: NSLocalizedString("TXT_DELETE_TITLE", comment: "")) { [weak self] _, _ in
            let alert = UIAlertController(title: NSLocalizedString("CONVERSATION_DELETE_CONFIRMATION_ALERT_TITLE", comment: ""), message: NSLocalizedString("CONVERSATION_DELETE_CONFIRMATION_ALERT_MESSAGE", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("TXT_DELETE_TITLE", comment: ""), style: .destructive) { _ in
                Storage.writeSync { transaction in
                    if let publicChat = publicChat {
                        var messageIDs: Set<String> = []
                        thread.enumerateInteractions(with: transaction) { interaction, _ in
                            messageIDs.insert(interaction.uniqueId!)
                        }
                        OWSPrimaryStorage.shared().updateMessageIDCollectionByPruningMessagesWithIDs(messageIDs, in: transaction)
                        transaction.removeObject(forKey: "\(publicChat.server).\(publicChat.channel)", inCollection: Storage.lastMessageServerIDCollection)
                        transaction.removeObject(forKey: "\(publicChat.server).\(publicChat.channel)", inCollection: Storage.lastDeletionServerIDCollection)
                        let _ = OpenGroupAPI.leave(publicChat.channel, on: publicChat.server)
                        thread.removeAllThreadInteractions(with: transaction)
                        thread.remove(with: transaction)
                    } else if let thread = thread as? TSGroupThread, thread.usesSharedSenderKeys == true {
                        let groupID = thread.groupModel.groupId
                        let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
                        let _ = ClosedGroupsProtocol.leave(groupPublicKey, using: transaction).ensure {
                            Storage.writeSync { transaction in
                                thread.removeAllThreadInteractions(with: transaction)
                                thread.remove(with: transaction)
                            }
                        }
                    } else {
                        thread.removeAllThreadInteractions(with: transaction)
                        thread.remove(with: transaction)
                    }
                }
                NotificationCenter.default.post(name: .threadDeleted, object: nil, userInfo: [ "threadId" : thread.uniqueId! ])
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("TXT_CANCEL_TITLE", comment: ""), style: .default) { _ in })
            guard let self = self else { return }
            self.present(alert, animated: true, completion: nil)
        }
        delete.backgroundColor = Colors.destructive
        if thread is TSContactThread {
            let publicKey = thread.contactIdentifier()!
            let blockingManager = SSKEnvironment.shared.blockingManager
            let isBlocked = blockingManager.isRecipientIdBlocked(publicKey)
            let block = UITableViewRowAction(style: .normal, title: NSLocalizedString("BLOCK_LIST_BLOCK_BUTTON", comment: "")) { _, _ in
                blockingManager.addBlockedPhoneNumber(publicKey)
                tableView.reloadRows(at: [ indexPath ], with: UITableView.RowAnimation.fade)
            }
            block.backgroundColor = Colors.unimportant
            let unblock = UITableViewRowAction(style: .normal, title: NSLocalizedString("BLOCK_LIST_UNBLOCK_BUTTON", comment: "")) { _, _ in
                blockingManager.removeBlockedPhoneNumber(publicKey)
                tableView.reloadRows(at: [ indexPath ], with: UITableView.RowAnimation.fade)
            }
            unblock.backgroundColor = Colors.unimportant
            return [ delete, (isBlocked ? unblock : block) ]
        } else {
            return [ delete ]
        }
    }
    
    @objc private func openSettings() {
        let settingsVC = SettingsVC()
        let navigationController = OWSNavigationController(rootViewController: settingsVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc private func showPath() {
        let pathVC = PathVC()
        let navigationController = OWSNavigationController(rootViewController: pathVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc func joinOpenGroup() {
        let joinPublicChatVC = JoinPublicChatVC()
        let navigationController = OWSNavigationController(rootViewController: joinPublicChatVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc func createNewPrivateChat() {
        let newPrivateChatVC = NewPrivateChatVC()
        let navigationController = OWSNavigationController(rootViewController: newPrivateChatVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc func createNewClosedGroup() {
        let newClosedGroupVC = NewClosedGroupVC()
        let navigationController = OWSNavigationController(rootViewController: newClosedGroupVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    // MARK: Convenience
    private func thread(at index: Int) -> TSThread? {
        var thread: TSThread? = nil
        uiDatabaseConnection.read { transaction in
            thread = ((transaction as YapDatabaseReadTransaction).ext(TSThreadDatabaseViewExtensionName) as! YapDatabaseViewTransaction).object(atRow: UInt(index), inSection: 0, with: self.threads) as! TSThread?
        }
        return thread
    }
    
    private func threadViewModel(at index: Int) -> ThreadViewModel? {
        guard let thread = thread(at: index) else { return nil }
        if let cachedThreadViewModel = threadViewModelCache[thread.uniqueId!] {
            return cachedThreadViewModel
        } else {
            var threadViewModel: ThreadViewModel? = nil
            uiDatabaseConnection.read { transaction in
                threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
            }
            threadViewModelCache[thread.uniqueId!] = threadViewModel
            return threadViewModel
        }
    }
}
