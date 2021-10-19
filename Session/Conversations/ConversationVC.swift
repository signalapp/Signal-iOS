
// TODO:
// • Slight paging glitch when scrolling up and loading more content
// • Photo rounding (the small corners don't have the correct rounding)
// • Remaining search glitchiness

final class ConversationVC : BaseVC, ConversationViewModelDelegate, OWSConversationSettingsViewDelegate, ConversationSearchControllerDelegate, UITableViewDataSource, UITableViewDelegate {
    let isUnsendRequestsEnabled = true // Set to true once unsend requests are done on all platforms
    let thread: TSThread
    let focusedMessageID: String? // This isn't actually used ATM
    var unreadViewItems: [ConversationViewItem] = []
    var scrollButtonConstraint: NSLayoutConstraint?
    // Search
    var isShowingSearchUI = false
    var lastSearchedText: String?
    // Audio playback & recording
    var audioPlayer: OWSAudioPlayer?
    var audioRecorder: AVAudioRecorder?
    var audioTimer: Timer?
    // Context menu
    var contextMenuWindow: ContextMenuWindow?
    var contextMenuVC: ContextMenuVC?
    // Mentions
    var oldText = ""
    var currentMentionStartIndex: String.Index?
    var mentions: [Mention] = []
    // Scrolling & paging
    var isUserScrolling = false
    var didFinishInitialLayout = false
    var isLoadingMore = false
    var scrollDistanceToBottomBeforeUpdate: CGFloat?
    var baselineKeyboardHeight: CGFloat = 0

    var audioSession: OWSAudioSession { Environment.shared.audioSession }
    var dbConnection: YapDatabaseConnection { OWSPrimaryStorage.shared().uiDatabaseConnection }
    var viewItems: [ConversationViewItem] { viewModel.viewState.viewItems }
    override var canBecomeFirstResponder: Bool { true }
    
    override var inputAccessoryView: UIView? {
        if let thread = thread as? TSGroupThread, thread.groupModel.groupType == .closedGroup && !thread.isCurrentUserMemberInGroup() {
            return nil
        } else {
            return isShowingSearchUI ? searchController.resultsBar : snInputView
        }
    }

    /// The height of the visible part of the table view, i.e. the distance from the navigation bar (where the table view's origin is)
    /// to the top of the input view (`messagesTableView.adjustedContentInset.bottom`).
    var tableViewUnobscuredHeight: CGFloat {
        let bottomInset = messagesTableView.adjustedContentInset.bottom
        return messagesTableView.bounds.height - bottomInset
    }

    /// The offset at which the table view is exactly scrolled to the bottom.
    var lastPageTop: CGFloat {
        return messagesTableView.contentSize.height - tableViewUnobscuredHeight
    }
    
    var isCloseToBottom: Bool {
        let margin = (self.lastPageTop - self.messagesTableView.contentOffset.y)
        return margin <= ConversationVC.scrollToBottomMargin
    }
    
    lazy var mnemonic: String = {
        let identityManager = OWSIdentityManager.shared()
        let databaseConnection = identityManager.value(forKey: "dbConnection") as! YapDatabaseConnection
        var hexEncodedSeed: String! = databaseConnection.object(forKey: "LKLokiSeed", inCollection: OWSPrimaryStorageIdentityKeyStoreCollection) as! String?
        if hexEncodedSeed == nil {
            hexEncodedSeed = identityManager.identityKeyPair()!.hexEncodedPrivateKey // Legacy account
        }
        return Mnemonic.encode(hexEncodedString: hexEncodedSeed)
    }()
    
    lazy var viewModel = ConversationViewModel(thread: thread, focusMessageIdOnOpen: focusedMessageID, delegate: self)
    
    lazy var mediaCache: NSCache<NSString, AnyObject> = {
        let result = NSCache<NSString, AnyObject>()
        result.countLimit = 40
        return result
    }()

    lazy var recordVoiceMessageActivity = AudioActivity(audioDescription: "Voice message", behavior: .playAndRecord)
    
    lazy var searchController: ConversationSearchController = {
        let result = ConversationSearchController(thread: thread)
        result.delegate = self
        if #available(iOS 13, *) {
            result.uiSearchController.obscuresBackgroundDuringPresentation = false
        } else {
            result.uiSearchController.dimsBackgroundDuringPresentation = false
        }
        return result
    }()
    
    // MARK: UI Components
    lazy var titleView: ConversationTitleView = {
        let result = ConversationTitleView(thread: thread)
        result.delegate = self
        return result
    }()

    lazy var messagesTableView: MessagesTableView = {
        let result = MessagesTableView()
        result.dataSource = self
        result.delegate = self
        return result
    }()
    
    lazy var snInputView = InputView(delegate: self)
    
    lazy var unreadCountView: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.text.withAlphaComponent(Values.veryLowOpacity)
        let size = ConversationVC.unreadCountViewSize
        result.set(.width, to: size)
        result.set(.height, to: size)
        result.layer.masksToBounds = true
        result.layer.cornerRadius = size / 2
        return result
    }()
    
    lazy var unreadCountLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        result.textColor = Colors.text
        result.textAlignment = .center
        return result
    }()
    
    lazy var scrollButton = ScrollToBottomButton(delegate: self)
    
    lazy var blockedBanner: InfoBanner = {
        let name: String
        if let thread = thread as? TSContactThread {
            let publicKey = thread.contactSessionID()
            let context = Contact.context(for: thread)
            name = Storage.shared.getContact(with: publicKey)?.displayName(for: context) ?? publicKey
        } else {
            name = "Thread"
        }
        let message = "\(name) is blocked. Unblock them?"
        let result = InfoBanner(message: message, backgroundColor: Colors.destructive)
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(unblock))
        result.addGestureRecognizer(tapGestureRecognizer)
        return result
    }()
    
    // MARK: Settings
    static let unreadCountViewSize: CGFloat = 20
    /// The table view's bottom inset (content will have this distance to the bottom if the table view is fully scrolled down).
    static let bottomInset = Values.mediumSpacing
    /// The table view will start loading more content when the content offset becomes less than this.
    static let loadMoreThreshold: CGFloat = 120
    /// The button will be fully visible once the user has scrolled this amount from the bottom of the table view.
    static let scrollButtonFullVisibilityThreshold: CGFloat = 80
    /// The button will be invisible until the user has scrolled at least this amount from the bottom of the table view.
    static let scrollButtonNoVisibilityThreshold: CGFloat = 20
    /// Automatically scroll to the bottom of the conversation when sending a message if the scroll distance from the bottom is less than this number.
    static let scrollToBottomMargin: CGFloat = 60
    
    // MARK: Lifecycle
    init(thread: TSThread, focusedMessageID: String? = nil) {
        self.thread = thread
        self.focusedMessageID = focusedMessageID
        super.init(nibName: nil, bundle: nil)
        var unreadCount: UInt = 0
        Storage.read { transaction in
            unreadCount = self.thread.unreadMessageCount(transaction: transaction)
        }
        let clampedUnreadCount = min(unreadCount, UInt(kConversationInitialMaxRangeSize), UInt(viewItems.endIndex))
        unreadViewItems = clampedUnreadCount != 0 ? [ConversationViewItem](viewItems[viewItems.endIndex - Int(clampedUnreadCount) ..< viewItems.endIndex]) : []
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(thread:) instead.")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Gradient
        setUpGradientBackground()
        // Nav bar
        setUpNavBarStyle()
        navigationItem.titleView = titleView
        updateNavBarButtons()
        // Constraints
        view.addSubview(messagesTableView)
        messagesTableView.pin(to: view)
        view.addSubview(scrollButton)
        scrollButton.pin(.right, to: .right, of: view, withInset: -16)
        scrollButtonConstraint = scrollButton.pin(.bottom, to: .bottom, of: view, withInset: -16)
        // Unread count view
        view.addSubview(unreadCountView)
        unreadCountView.addSubview(unreadCountLabel)
        unreadCountLabel.pin(to: unreadCountView)
        unreadCountView.centerYAnchor.constraint(equalTo: scrollButton.topAnchor).isActive = true
        unreadCountView.center(.horizontal, in: scrollButton)
        updateUnreadCountView()
        // Blocked banner
        addOrRemoveBlockedBanner()
        // Notifications
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleKeyboardWillChangeFrameNotification(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleKeyboardWillHideNotification(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleAudioDidFinishPlayingNotification(_:)), name: .SNAudioDidFinishPlaying, object: nil)
        notificationCenter.addObserver(self, selector: #selector(addOrRemoveBlockedBanner), name: NSNotification.Name(rawValue: kNSNotificationName_BlockListDidChange), object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleGroupUpdatedNotification), name: .groupThreadUpdated, object: nil)
        notificationCenter.addObserver(self, selector: #selector(sendScreenshotNotificationIfNeeded), name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleMessageSentStatusChanged), name: .messageSentStatusDidChange, object: nil)
        // Mentions
        MentionsManager.populateUserPublicKeyCacheIfNeeded(for: thread.uniqueId!)
        // Draft
        var draft = ""
        Storage.read { transaction in
            draft = self.thread.currentDraft(with: transaction)
        }
        if !draft.isEmpty {
            snInputView.text = draft
        }
        // Update member count if this is a V2 open group
        if let v2OpenGroup = Storage.shared.getV2OpenGroup(for: thread.uniqueId!) {
            OpenGroupAPIV2.getMemberCount(for: v2OpenGroup.room, on: v2OpenGroup.server).retainUntilComplete()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didFinishInitialLayout {
            // Scroll to the last unread message if possible; otherwise scroll to the bottom.
            var unreadCount: UInt = 0
            Storage.read { transaction in
                unreadCount = self.thread.unreadMessageCount(transaction: transaction)
            }
            // When the unread message count is more than the number of view items of a page,
            // the screen will scroll to the bottom instead of the first unread message.
            // unreadIndicatorIndex is calculated during loading of the viewItems, so it's
            // supposed to be accurate.
            DispatchQueue.main.async {
                let firstUnreadMessageIndex = self.viewModel.viewState.unreadIndicatorIndex?.intValue
                    ?? (self.viewItems.count - self.unreadViewItems.count)
                if unreadCount > 0, let viewItem = self.viewItems[ifValid: firstUnreadMessageIndex], let interactionID = viewItem.interaction.uniqueId {
                    self.scrollToInteraction(with: interactionID, position: .top, isAnimated: false)
                    self.unreadCountView.alpha = self.scrollButton.alpha
                } else {
                    self.scrollToBottom(isAnimated: false)
                }
                self.scrollButton.alpha = self.getScrollButtonOpacity()
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didFinishInitialLayout = true
        markAllAsRead()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let text = snInputView.text
        Storage.write { transaction in
            self.thread.setDraft(text, transaction: transaction)
        }
        inputAccessoryView?.resignFirstResponder()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        mediaCache.removeAllObjects()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Table View Data Source
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let viewItem = viewItems[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.getCellType(for: viewItem).identifier) as! MessageCell
        cell.delegate = self
        cell.viewItem = viewItem
        return cell
    }
    
    // MARK: Updating
    func updateNavBarButtons() {
        navigationItem.hidesBackButton = isShowingSearchUI
        if isShowingSearchUI {
            navigationItem.rightBarButtonItems = []
        } else {
            let rightBarButtonItem: UIBarButtonItem
            if thread is TSContactThread {
                let size = Values.verySmallProfilePictureSize
                let profilePictureView = ProfilePictureView()
                profilePictureView.accessibilityLabel = "Settings button"
                profilePictureView.size = size
                profilePictureView.update(for: thread)
                profilePictureView.set(.width, to: size)
                profilePictureView.set(.height, to: size)
                let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(openSettings))
                profilePictureView.addGestureRecognizer(tapGestureRecognizer)
                rightBarButtonItem = UIBarButtonItem(customView: profilePictureView)
            } else {
                rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "Gear"), style: .plain, target: self, action: #selector(openSettings))
            }
            rightBarButtonItem.accessibilityLabel = "Settings button"
            rightBarButtonItem.isAccessibilityElement = true
            navigationItem.rightBarButtonItem = rightBarButtonItem
        }
    }
    
    @objc func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        guard let newHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.size.height else { return }
        if (newHeight > 0 && baselineKeyboardHeight == 0) {
            baselineKeyboardHeight = newHeight
            self.messagesTableView.keyboardHeight = newHeight
        }
        scrollButtonConstraint?.constant = -(newHeight + 16)
        let newContentOffsetY = max(self.messagesTableView.contentOffset.y + min(lastPageTop, 0) + newHeight - self.messagesTableView.keyboardHeight, 0.0)
        self.messagesTableView.contentOffset.y = newContentOffsetY
        self.messagesTableView.keyboardHeight = newHeight
        self.scrollButton.alpha = self.getScrollButtonOpacity()
    }
    
    @objc func handleKeyboardWillHideNotification(_ notification: Notification) {
        self.messagesTableView.contentOffset.y -= (self.messagesTableView.keyboardHeight - self.baselineKeyboardHeight)
        self.messagesTableView.keyboardHeight = self.baselineKeyboardHeight
        scrollButtonConstraint?.constant = -(self.baselineKeyboardHeight + 16)
        self.scrollButton.alpha = self.getScrollButtonOpacity()
        self.unreadCountView.alpha = self.scrollButton.alpha
    }
    
    func conversationViewModelWillUpdate() {
        // Not currently in use
    }
    
    func conversationViewModelDidUpdate(_ conversationUpdate: ConversationUpdate) {
        guard self.isViewLoaded else { return }
        let updateType = conversationUpdate.conversationUpdateType
        guard updateType != .minor else { return } // No view items were affected
        if updateType == .reload {
            return messagesTableView.reloadData()
        }
        var shouldScrollToBottom = false
        let batchUpdates: () -> Void = {
            for update in conversationUpdate.updateItems! {
                switch update.updateItemType {
                case .delete:
                    self.messagesTableView.deleteRows(at: [ IndexPath(row: Int(update.oldIndex), section: 0) ], with: .none)
                case .insert:
                    // Perform inserts before updates
                    self.messagesTableView.insertRows(at: [ IndexPath(row: Int(update.newIndex), section: 0) ], with: .none)
                    if update.viewItem?.interaction is TSOutgoingMessage {
                        shouldScrollToBottom = true
                    } else {
                        shouldScrollToBottom = self.isCloseToBottom
                    }
                case .update:
                    self.messagesTableView.reloadRows(at: [ IndexPath(row: Int(update.oldIndex), section: 0) ], with: .none)
                default: preconditionFailure()
                }
            }
        }
        UIView.performWithoutAnimation {
            messagesTableView.performBatchUpdates(batchUpdates) { _ in
                if shouldScrollToBottom {
                    self.scrollToBottom(isAnimated: false)
                }
                self.markAllAsRead()
            }
            if shouldScrollToBottom {
                self.scrollToBottom(isAnimated: false)
            }
        }
    }
    
    func conversationViewModelWillLoadMoreItems() {
        view.layoutIfNeeded()
        // The scroll distance to bottom will be restored in conversationViewModelDidLoadMoreItems
        scrollDistanceToBottomBeforeUpdate = messagesTableView.contentSize.height - messagesTableView.contentOffset.y
    }
    
    func conversationViewModelDidLoadMoreItems() {
        guard let scrollDistanceToBottomBeforeUpdate = scrollDistanceToBottomBeforeUpdate else { return }
        view.layoutIfNeeded()
        messagesTableView.contentOffset.y = messagesTableView.contentSize.height - scrollDistanceToBottomBeforeUpdate
        isLoadingMore = false
    }
    
    func conversationViewModelDidLoadPrevPage() {
        // Not currently in use
    }
    
    func conversationViewModelRangeDidChange() {
        // Not currently in use
    }
    
    func conversationViewModelDidReset() {
        // Not currently in use
    }
    
    @objc private func handleGroupUpdatedNotification() {
        thread.reload() // Needed so that thread.isCurrentUserMemberInGroup() is up to date
        reloadInputViews()
    }
    
    @objc private func handleMessageSentStatusChanged() {
        DispatchQueue.main.async {
            guard let indexPaths = self.messagesTableView.indexPathsForVisibleRows else { return }
            var indexPathsToReload: [IndexPath] = []
            for indexPath in indexPaths {
                guard let cell = self.messagesTableView.cellForRow(at: indexPath) as? VisibleMessageCell else { continue }
                let isLast = (indexPath.item == (self.messagesTableView.numberOfRows(inSection: 0) - 1))
                guard !isLast else { continue }
                if !cell.messageStatusImageView.isHidden {
                    indexPathsToReload.append(indexPath)
                }
            }
            UIView.performWithoutAnimation {
                self.messagesTableView.reloadRows(at: indexPathsToReload, with: .none)
            }
        }
    }
    
    // MARK: General
    @objc func addOrRemoveBlockedBanner() {
        func detach() {
            blockedBanner.removeFromSuperview()
        }
        guard let thread = thread as? TSContactThread else { return detach() }
        if OWSBlockingManager.shared().isRecipientIdBlocked(thread.contactSessionID()) {
            view.addSubview(blockedBanner)
            blockedBanner.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top, UIView.HorizontalEdge.right ], to: view)
        } else {
            detach()
        }
    }
    
    func markAllAsRead() {
        guard let lastSortID = viewItems.last?.interaction.sortId else { return }
        OWSReadReceiptManager.shared().markAsReadLocally(beforeSortId: lastSortID, thread: thread)
        SSKEnvironment.shared.disappearingMessagesJob.cleanupMessagesWhichFailedToStartExpiringFromNow()
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func getMediaCache() -> NSCache<NSString, AnyObject> {
        return mediaCache
    }
    
    func scrollToBottom(isAnimated: Bool) {
        guard !isUserScrolling else { return }
        // Ensure the view is fully up to date before we try to scroll to the bottom, since
        // we use the table view's bounds to determine where the bottom is.
        view.layoutIfNeeded()
        let firstContentPageTop: CGFloat = 0
        let contentOffsetY = max(firstContentPageTop, lastPageTop)
        messagesTableView.setContentOffset(CGPoint(x: 0, y: contentOffsetY), animated: isAnimated)
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserScrolling = true
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        isUserScrolling = false
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollButton.alpha = getScrollButtonOpacity()
        unreadCountView.alpha = scrollButton.alpha
        autoLoadMoreIfNeeded()
        updateUnreadCountView()
    }
    
    func updateUnreadCountView() {
        let visibleViewItems = (messagesTableView.indexPathsForVisibleRows ?? []).map { viewItems[ifValid: $0.row] }
        for visibleItem in visibleViewItems {
            guard let index = unreadViewItems.firstIndex(where: { $0 === visibleItem }) else { continue }
            unreadViewItems.remove(at: index)
        }
        let unreadCount = unreadViewItems.count
        unreadCountLabel.text = unreadCount < 100 ? "\(unreadCount)" : "99+"
        let fontSize = (unreadCount < 100) ? Values.verySmallFontSize : 8
        unreadCountLabel.font = .boldSystemFont(ofSize: fontSize)
        unreadCountView.isHidden = (unreadCount == 0)
    }
    
    func autoLoadMoreIfNeeded() {
        let isMainAppAndActive = CurrentAppContext().isMainAppAndActive
        guard isMainAppAndActive && viewModel.canLoadMoreItems() && !isLoadingMore
            && messagesTableView.contentOffset.y < ConversationVC.loadMoreThreshold else { return }
        isLoadingMore = true
        viewModel.loadAnotherPageOfMessages()
    }
    
    func getScrollButtonOpacity() -> CGFloat {
        let contentOffsetY = messagesTableView.contentOffset.y
        let x = (lastPageTop - ConversationVC.bottomInset - contentOffsetY).clamp(0, .greatestFiniteMagnitude)
        let a = 1 / (ConversationVC.scrollButtonFullVisibilityThreshold - ConversationVC.scrollButtonNoVisibilityThreshold)
        return a * x
    }
    
    func groupWasUpdated(_ groupModel: TSGroupModel) {
        // Not currently in use
    }
    
    // MARK: Search
    func conversationSettingsDidRequestConversationSearch(_ conversationSettingsViewController: OWSConversationSettingsViewController) {
        showSearchUI()
        popAllConversationSettingsViews {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // Without this delay the search bar doesn't show
                self.searchController.uiSearchController.searchBar.becomeFirstResponder()
            }
        }
    }
    
    func popAllConversationSettingsViews(completion completionBlock: (() -> Void)? = nil) {
        if presentedViewController != nil {
            dismiss(animated: true) {
                self.navigationController!.popToViewController(self, animated: true, completion: completionBlock)
            }
        } else {
            navigationController!.popToViewController(self, animated: true, completion: completionBlock)
        }
    }
    
    func showSearchUI() {
        isShowingSearchUI = true
        // Search bar
        let searchBar = searchController.uiSearchController.searchBar
        searchBar.searchBarStyle = .minimal
        searchBar.barStyle = .black
        searchBar.tintColor = Colors.accent
        let searchIcon = UIImage(named: "searchbar_search")!.asTintedImage(color: Colors.searchBarPlaceholder)
        searchBar.setImage(searchIcon, for: .search, state: UIControl.State.normal)
        let clearIcon = UIImage(named: "searchbar_clear")!.asTintedImage(color: Colors.searchBarPlaceholder)
        searchBar.setImage(clearIcon, for: .clear, state: UIControl.State.normal)
        let searchTextField: UITextField
        if #available(iOS 13, *) {
            searchTextField = searchBar.searchTextField
        } else {
            searchTextField = searchBar.value(forKey: "_searchField") as! UITextField
        }
        searchTextField.backgroundColor = Colors.searchBarBackground
        searchTextField.textColor = Colors.text
        searchTextField.attributedPlaceholder = NSAttributedString(string: "Search", attributes: [ .foregroundColor : Colors.searchBarPlaceholder ])
        searchTextField.keyboardAppearance = isLightMode ? .default : .dark
        searchBar.setPositionAdjustment(UIOffset(horizontal: 4, vertical: 0), for: .search)
        searchBar.searchTextPositionAdjustment = UIOffset(horizontal: 2, vertical: 0)
        searchBar.setPositionAdjustment(UIOffset(horizontal: -4, vertical: 0), for: .clear)
        navigationItem.titleView = searchBar
        // Nav bar buttons
        updateNavBarButtons()
        // Hack so that the ResultsBar stays on the screen when dismissing the search field
        // keyboard.
        //
        // Details:
        //
        // When the search UI is activated, both the SearchField and the ConversationVC
        // have the resultsBar as their inputAccessoryView.
        //
        // So when the SearchField is first responder, the ResultsBar is shown on top of the keyboard.
        // When the ConversationVC is first responder, the ResultsBar is shown at the bottom of the
        // screen.
        //
        // When the user swipes to dismiss the keyboard, trying to see more of the content while
        // searching, we want the ResultsBar to stay at the bottom of the screen - that is, we
        // want the ConversationVC to becomeFirstResponder.
        //
        // If the SearchField were a subview of ConversationVC.view, this would all be automatic,
        // as first responder status is percolated up the responder chain via `nextResponder`, which
        // basically travereses each superView, until you're at a rootView, at which point the next
        // responder is the ViewController which controls that View.
        //
        // However, because SearchField lives in the Navbar, it's "controlled" by the
        // NavigationController, not the ConversationVC.
        //
        // So here we stub the next responder on the navBar so that when the searchBar resigns
        // first responder, the ConversationVC will be in it's responder chain - keeeping the
        // ResultsBar on the bottom of the screen after dismissing the keyboard.
        let navBar = navigationController!.navigationBar as! OWSNavigationBar
        navBar.stubbedNextResponder = self
    }
    
    func hideSearchUI() {
        isShowingSearchUI = false
        navigationItem.titleView = titleView
        updateNavBarButtons()
        let navBar = navigationController!.navigationBar as! OWSNavigationBar
        navBar.stubbedNextResponder = nil
        becomeFirstResponder()
        reloadInputViews()
    }
    
    func didDismissSearchController(_ searchController: UISearchController) {
        hideSearchUI()
    }
    
    func conversationSearchController(_ conversationSearchController: ConversationSearchController, didUpdateSearchResults resultSet: ConversationScreenSearchResultSet?) {
        lastSearchedText = resultSet?.searchText
        messagesTableView.reloadRows(at: messagesTableView.indexPathsForVisibleRows ?? [], with: UITableView.RowAnimation.none)
    }
    
    func conversationSearchController(_ conversationSearchController: ConversationSearchController, didSelectMessageId interactionID: String) {
        scrollToInteraction(with: interactionID)
    }
    
    func scrollToInteraction(with interactionID: String, position: UITableView.ScrollPosition = .middle, isAnimated: Bool = true) {
        guard let indexPath = viewModel.ensureLoadWindowContainsInteractionId(interactionID) else { return }
        messagesTableView.scrollToRow(at: indexPath, at: position, animated: isAnimated)
    }
}
