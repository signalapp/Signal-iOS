
final class HomeVC : UIViewController, UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate, UIViewControllerPreviewingDelegate, SeedReminderViewDelegate {
    private var threadViewModelCache: [String:ThreadViewModel] = [:]
    private var isObservingDatabase = true
    private var isViewVisible = false { didSet { updateIsObservingDatabase() } }
    private var tableViewTopConstraint: NSLayoutConstraint!
    
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
    
    // MARK: Settings
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    
    // MARK: Components
    private lazy var seedReminderView: SeedReminderView = {
        let result = SeedReminderView(hasContinueButton: true)
        let title = "You're almost finished! 80%"
        let attributedTitle = NSMutableAttributedString(string: title)
        attributedTitle.addAttribute(.foregroundColor, value: Colors.accent, range: (title as NSString).range(of: "80%"))
        result.title = attributedTitle
        result.subtitle = NSLocalizedString("Secure your account by saving your recovery phrase", comment: "")
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
        return result
    }()
    
    private lazy var newConversationButton: UIButton = {
        let result = UIButton()
        result.setTitle("+", for: UIControl.State.normal)
        result.titleLabel!.font = .systemFont(ofSize: 35)
        result.setTitleColor(UIColor(hex: 0x121212), for: UIControl.State.normal)
        result.titleEdgeInsets = UIEdgeInsets(top: 0, left: 1, bottom: 4, right: 0) // Slight adjustment to make the plus exactly centered
        result.backgroundColor = Colors.accent
        let size = Values.newConversationButtonSize
        result.layer.cornerRadius = size / 2
        result.layer.shadowPath = UIBezierPath(ovalIn: CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: size, height: size))).cgPath
        result.layer.shadowColor = Colors.newConversationButtonShadow.cgColor
        result.layer.shadowOffset = CGSize(width: 0, height: 0.8)
        result.layer.shadowOpacity = 1
        result.layer.shadowRadius = 6
        result.layer.masksToBounds = false
        result.set(.width, to: size)
        result.set(.height, to: size)
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        SignalApp.shared().homeViewController = self
        // Set gradient background
        view.backgroundColor = .clear
        let gradient = Gradients.defaultLokiBackground
        view.setGradient(gradient)
        // Set navigation bar background color
        if let navigationBar = navigationController?.navigationBar {
            navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
            navigationBar.shadowImage = UIImage()
            navigationBar.isTranslucent = false
            navigationBar.barTintColor = Colors.navigationBarBackground
        }
        // Set up navigation bar buttons
        updateNavigationBarButtons()
        // Customize title
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("Messages", comment: "")
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        navigationItem.titleView = titleLabel
        // Set up seed reminder view if needed
        let hasViewedSeed = UserDefaults.standard.bool(forKey: "hasViewedSeed")
        let isMasterDevice = (UserDefaults.standard.string(forKey: "masterDeviceHexEncodedPublicKey") == nil)
        if !hasViewedSeed && isMasterDevice {
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
        if !hasViewedSeed && isMasterDevice {
            tableViewTopConstraint = tableView.pin(.top, to: .bottom, of: seedReminderView)
        } else {
            tableViewTopConstraint = tableView.pin(.top, to: .top, of: view, withInset: Values.smallSpacing)
        }
        tableView.pin(.trailing, to: .trailing, of: view)
        tableView.pin(.bottom, to: .bottom, of: view)
        // Set up search bar
//        tableView.tableHeaderView = searchBar
//        searchBar.sizeToFit()
//        tableView.contentOffset = CGPoint(x: 0, y: searchBar.frame.height)
        // Set up new conversation button
        newConversationButton.addTarget(self, action: #selector(createPrivateChat), for: UIControl.Event.touchUpInside)
        view.addSubview(newConversationButton)
        newConversationButton.center(.horizontal, in: view)
        newConversationButton.pin(.bottom, to: .bottom, of: view, withInset: -Values.newConversationButtonBottomOffset) // Negative due to how the constraint is set up
        // Set up previewing
        if (traitCollection.forceTouchCapability == .available) {
            registerForPreviewing(with: self, sourceView: tableView)
        }
        // Listen for notifications
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleYapDatabaseModifiedNotification(_:)), name: .YapDatabaseModified, object: OWSPrimaryStorage.shared().dbNotificationObject)
        notificationCenter.addObserver(self, selector: #selector(handleYapDatabaseModifiedExternallyNotification(_:)), name: .YapDatabaseModifiedExternally, object: OWSPrimaryStorage.shared().dbNotificationObject)
        notificationCenter.addObserver(self, selector: #selector(handleApplicationDidBecomeActiveNotification(_:)), name: .OWSApplicationDidBecomeActive, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleApplicationWillResignActiveNotification(_:)), name: .OWSApplicationWillResignActive, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleProfileDidChangeNotification(_:)), name: NSNotification.Name(rawValue: kNSNotificationName_OtherUsersProfileDidChange), object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleLocalProfileDidChangeNotification(_:)), name: Notification.Name(kNSNotificationName_LocalProfileDidChange), object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleSeedViewedNotification(_:)), name: .seedViewed, object: nil)
        // Set up public chats and RSS feeds if needed
        if OWSIdentityManager.shared().identityKeyPair() != nil {
            let appDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.setUpDefaultPublicChatsIfNeeded()
            appDelegate.createRSSFeedsIfNeeded()
            LokiPublicChatManager.shared.startPollersIfNeeded()
            appDelegate.startRSSFeedPollersIfNeeded()
        }
        // Do initial update
        reload()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isViewVisible = true
//        let hasSeenOpenGroupSuggestionSheet = UserDefaults.standard.bool(forKey: "hasSeenOpenGroupSuggestionSheet")
//        if !hasSeenOpenGroupSuggestionSheet {
//            let openGroupSuggestionSheet = OpenGroupSuggestionSheet()
//            openGroupSuggestionSheet.modalPresentationStyle = .overFullScreen
//            openGroupSuggestionSheet.modalTransitionStyle = .crossDissolve
//            present(openGroupSuggestionSheet, animated: true, completion: nil)
//        }
        UserDefaults.standard.set(true, forKey: "hasLaunchedOnce")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewVisible = false
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Data
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Int(threads.numberOfItems(inGroup: TSInboxGroup))
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
        uiDatabaseConnection.beginLongLivedReadTransaction()
        uiDatabaseConnection.read { transaction in
            self.threads.update(with: transaction)
        }
        tableView.reloadData()
    }
    
    @objc private func handleYapDatabaseModifiedExternallyNotification(_ notification: Notification) {
        guard isObservingDatabase else { return }
        reload()
    }
    
    @objc private func handleYapDatabaseModifiedNotification(_ notification: Notification) {
        guard isObservingDatabase else { return }
        let transaction = uiDatabaseConnection.beginLongLivedReadTransaction()
        let hasChanges = (uiDatabaseConnection.ext(TSThreadDatabaseViewExtensionName) as! YapDatabaseViewConnection).hasChanges(forGroup: TSInboxGroup, in: transaction)
        guard hasChanges else {
            uiDatabaseConnection.read { transaction in
                self.threads.update(with: transaction)
            }
            return
        }
        var sectionChanges = NSArray()
        var rowChanges = NSArray()
        (uiDatabaseConnection.ext(TSThreadDatabaseViewExtensionName) as! YapDatabaseViewConnection).getSectionChanges(&sectionChanges, rowChanges: &rowChanges, for: transaction, with: threads)
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
    }
    
    @objc private func handleApplicationDidBecomeActiveNotification(_ notification: Notification) {
        updateIsObservingDatabase()
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
    
    private func updateNavigationBarButtons() {
        let profilePictureSize = Values.verySmallProfilePictureSize
        let profilePictureView = ProfilePictureView()
        profilePictureView.size = profilePictureSize
        let userHexEncodedPublicKey = getUserHexEncodedPublicKey()
        profilePictureView.hexEncodedPublicKey = userHexEncodedPublicKey
        profilePictureView.update()
        profilePictureView.set(.width, to: profilePictureSize)
        profilePictureView.set(.height, to: profilePictureSize)
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(openSettings))
        profilePictureView.addGestureRecognizer(tapGestureRecognizer)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: profilePictureView)
        let newClosedGroupButton = UIButton(type: .custom)
        newClosedGroupButton.setImage(#imageLiteral(resourceName: "btnGroup--white"), for: UIControl.State.normal)
        newClosedGroupButton.addTarget(self, action: #selector(createClosedGroup), for: UIControl.Event.touchUpInside)
        newClosedGroupButton.tintColor = Colors.text
        let joinPublicChatButton = UIButton(type: .custom)
        joinPublicChatButton.setImage(#imageLiteral(resourceName: "Globe"), for: UIControl.State.normal)
        joinPublicChatButton.addTarget(self, action: #selector(joinPublicChat), for: UIControl.Event.touchUpInside)
        joinPublicChatButton.tintColor = Colors.text
        let buttonStackView = UIStackView(arrangedSubviews: [ newClosedGroupButton, joinPublicChatButton ])
        buttonStackView.axis = .horizontal
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: buttonStackView)
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
            let conversationVC = ConversationViewController()
            conversationVC.configure(for: thread, action: action, focusMessageId: highlightedMessageID)
            self.navigationController?.setViewControllers([ self, conversationVC ], animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let threadID = self.thread(at: indexPath.row)?.uniqueId else { return false }
        var publicChat: LokiPublicChat?
        OWSPrimaryStorage.shared().dbReadConnection.read { transaction in
            publicChat = LokiDatabaseUtilities.getPublicChat(for: threadID, in: transaction)
        }
        if let publicChat = publicChat {
            return publicChat.isDeletable
        } else {
            return true
        }
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        guard let thread = self.thread(at: indexPath.row) else { return [] }
        var publicChat: LokiPublicChat?
        OWSPrimaryStorage.shared().dbReadConnection.read { transaction in
            publicChat = LokiDatabaseUtilities.getPublicChat(for: thread.uniqueId!, in: transaction)
        }
        let delete = UITableViewRowAction(style: .destructive, title: NSLocalizedString("Delete", comment: "")) { [weak self] action, indexPath in
            let alert = UIAlertController(title: NSLocalizedString("CONVERSATION_DELETE_CONFIRMATION_ALERT_TITLE", comment: ""), message: NSLocalizedString("CONVERSATION_DELETE_CONFIRMATION_ALERT_MESSAGE", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("TXT_DELETE_TITLE", comment: ""), style: .destructive) { _ in
                guard let self = self else { return }
                self.editingDatabaseConnection.readWrite { transaction in
                    if let publicChat = publicChat {
                        var messageIDs: Set<String> = []
                        thread.enumerateInteractions(with: transaction) { interaction, _ in
                            messageIDs.insert(interaction.uniqueId!)
                        }
                        OWSPrimaryStorage.shared().updateMessageIDCollectionByPruningMessagesWithIDs(messageIDs, in: transaction)
                        transaction.removeObject(forKey: "\(publicChat.server).\(publicChat.channel)", inCollection: LokiPublicChatAPI.lastMessageServerIDCollection)
                        transaction.removeObject(forKey: "\(publicChat.server).\(publicChat.channel)", inCollection: LokiPublicChatAPI.lastDeletionServerIDCollection)
                        let _ = LokiPublicChatAPI.leave(publicChat.channel, on: publicChat.server)
                    }
                    thread.removeAllThreadInteractions(with: transaction)
                    thread.remove(with: transaction)
                }
                NotificationCenter.default.post(name: .threadDeleted, object: nil, userInfo: [ "threadId" : thread.uniqueId! ])
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("TXT_CANCEL_TITLE", comment: ""), style: .default) { _ in })
            guard let self = self else { return }
            self.present(alert, animated: true, completion: nil)
        }
        delete.backgroundColor = Colors.destructive
        if let publicChat = publicChat {
            return publicChat.isDeletable ? [ delete ] : []
        } else {
            return [ delete ]
        }
    }
    
    @objc private func openSettings() {
        let settingsVC = SettingsVC()
        let navigationController = OWSNavigationController(rootViewController: settingsVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc private func joinPublicChat() {
        let joinPublicChatVC = JoinPublicChatVC()
        let navigationController = OWSNavigationController(rootViewController: joinPublicChatVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc private func createClosedGroup() {
        let newClosedGroupVC = NewClosedGroupVC()
        let navigationController = OWSNavigationController(rootViewController: newClosedGroupVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc func createPrivateChat() {
        let newPrivateChatVC = NewPrivateChatVC()
        let navigationController = OWSNavigationController(rootViewController: newPrivateChatVC)
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
