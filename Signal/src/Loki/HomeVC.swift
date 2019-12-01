
final class HomeVC : UIViewController, UITableViewDataSource, UITableViewDelegate, UIViewControllerPreviewingDelegate {
    private var threadViewModelCache: [String:ThreadViewModel] = [:]
    private var isObservingDatabase = true
    private var isViewVisible = false { didSet { updateIsObservingDatabase() } }
    
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
    public override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    
    // MARK: Components
    private lazy var searchBar = SearchBar()
    
    private lazy var tableView: UITableView = {
        let result = UITableView()
        result.backgroundColor = .clear
        result.separatorStyle = .none
        result.register(ConversationCell.self, forCellReuseIdentifier: ConversationCell.reuseIdentifier)
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
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
        // Set up the navigation bar buttons
        updateNavigationBarButtons()
        // Customize title
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("Messages", comment: "")
        titleLabel.textColor = Colors.text
        titleLabel.font = UIFont.boldSystemFont(ofSize: Values.veryLargeFontSize)
        navigationItem.titleView = titleLabel
        // Set up table view
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.pin(to: view)
        // Set up search bar
        tableView.tableHeaderView = searchBar
        searchBar.sizeToFit()
        tableView.contentOffset = CGPoint(x: 0, y: searchBar.frame.height)
        // Set up new conversation button
//        let newConversationButton = UIImageView(image: #imageLiteral(resourceName: "ic_plus_24").asTintedImage(color: UIColor(hex: 0x121212)))
//        newConversationButton.backgroundColor = Colors.accent
//        newConversationButton.set(.width, to: Values.newConversationButtonSize)
//        newConversationButton.set(.height, to: Values.newConversationButtonSize)
//        view.addSubview(newConversationButton)
//        newConversationButton.center(.horizontal, in: view)
//        newConversationButton.center(.vertical, in: view)
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
        notificationCenter.addObserver(self, selector: #selector(handleLocalProfileDidChangeNotification(_:)), name: Notification.Name(kNSNotificationName_LocalProfileDidChange), object: nil)
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
            case .delete: tableView.deleteRows(at: [ rowChange.indexPath! ], with: UITableView.RowAnimation.automatic)
            case .insert: tableView.insertRows(at: [ rowChange.newIndexPath! ], with: UITableView.RowAnimation.automatic)
            case .move:
                tableView.deleteRows(at: [ rowChange.indexPath! ], with: UITableView.RowAnimation.automatic)
                tableView.insertRows(at: [ rowChange.newIndexPath! ], with: UITableView.RowAnimation.automatic)
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
    
    @objc private func handleLocalProfileDidChangeNotification(_ notification: Notification) {
        updateNavigationBarButtons()
    }
    
    private func updateNavigationBarButtons() {
        let profilePictureSize = Values.verySmallProfilePictureSize
        let profilePictureView = ProfilePictureView()
        profilePictureView.size = profilePictureSize
        let userHexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
        profilePictureView.hexEncodedPublicKey = userHexEncodedPublicKey
        profilePictureView.update()
        profilePictureView.set(.width, to: profilePictureSize)
        profilePictureView.set(.height, to: profilePictureSize)
        profilePictureView.onTap = { [weak self] in self?.openSettings() }
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: profilePictureView)
        let createPrivateGroupChatButton = UIBarButtonItem(image: #imageLiteral(resourceName: "People"), style: .plain, target: self, action: #selector(createPrivateGroupChat))
        createPrivateGroupChatButton.tintColor = Colors.text
        let joinPublicChatButton = UIBarButtonItem(image: #imageLiteral(resourceName: "Globe"), style: .plain, target: self, action: #selector(joinPublicChat))
        joinPublicChatButton.tintColor = Colors.text
        navigationItem.rightBarButtonItems = [ createPrivateGroupChatButton, joinPublicChatButton ]
    }
    
    // MARK: Interaction
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
        show(thread, with: ConversationViewAction.none, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    private func show(_ thread: TSThread, with action: ConversationViewAction, animated: Bool) {
        DispatchMainThreadSafe {
            let conversationVC = ConversationViewController()
            conversationVC.configure(for: thread, action: action, focusMessageId: nil) // TODO: focusMessageId
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
                    thread.remove(with: transaction)
                }
                NotificationCenter.default.post(name: .threadDeleted, object: nil, userInfo: [ "threadId" : thread.uniqueId! ])
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("TXT_CANCEL_TITLE", comment: ""), style: .default) { _ in })
            guard let self = self else { return }
            self.present(alert, animated: true, completion: nil)
        }
        if let publicChat = publicChat {
            return publicChat.isDeletable ? [ delete ] : []
        } else {
            return [ delete ]
        }
    }
    
    @objc private func openSettings() {
        let navigationController = AppSettingsViewController.inModalNavigationController()
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc private func joinPublicChat() {
        let joinPublicChatVC = JoinPublicChatVC()
        let navigationController = OWSNavigationController(rootViewController: joinPublicChatVC)
        present(navigationController, animated: true, completion: nil)
    }
    
    @objc private func createPrivateGroupChat() {
        // TODO: Implement
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
