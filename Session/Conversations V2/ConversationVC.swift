
// TODO
// • Tapping replies
// • Moderator icons
// • Slight paging glitch
// • Image detail VC transition glitch
// • Photo rounding
// • Disappearing messages timer
// • Scroll button behind mentions view
// • Remaining search bugs

final class ConversationVC : BaseVC, ConversationViewModelDelegate, OWSConversationSettingsViewDelegate, ConversationSearchControllerDelegate, UITableViewDataSource, UITableViewDelegate {
    let thread: TSThread
    let focusedMessageID: String?
    var didConstrainScrollButton = false
    var isShowingSearchUI = false
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

    var audioSession: OWSAudioSession { Environment.shared.audioSession }
    var dbConnection: YapDatabaseConnection { OWSPrimaryStorage.shared().uiDatabaseConnection }
    var viewItems: [ConversationViewItem] { viewModel.viewState.viewItems }
    func conversationStyle() -> ConversationStyle { return ConversationStyle(thread: thread) }
    override var inputAccessoryView: UIView? { isShowingSearchUI ? searchController.resultsBar : snInputView }
    override var canBecomeFirstResponder: Bool { true }

    var tableViewUnobscuredHeight: CGFloat {
        let bottomInset = messagesTableView.adjustedContentInset.bottom
        return messagesTableView.bounds.height - bottomInset
    }

    var lastPageTop: CGFloat {
        return messagesTableView.contentSize.height - tableViewUnobscuredHeight
    }
    
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
        return result
    }()
    
    // MARK: UI Components
    lazy var titleView = ConversationTitleViewV2(thread: thread)

    lazy var messagesTableView: MessagesTableView = {
        let result = MessagesTableView()
        result.dataSource = self
        result.delegate = self
        return result
    }()
    
    lazy var snInputView = InputView(delegate: self)
    
    lazy var scrollButton = ScrollToBottomButton(delegate: self)
    
    lazy var blockedBanner: InfoBanner = {
        let name: String
        if let thread = thread as? TSContactThread {
            let publicKey = thread.contactIdentifier()
            name = OWSProfileManager.shared().profileNameForRecipient(withID: publicKey, avoidingWriteTransaction: true) ?? publicKey
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
    static let bottomInset = Values.mediumSpacing
    static let loadMoreThreshold: CGFloat = 120
    /// The button will be fully visible once the user has scrolled this amount from the bottom of the table view.
    static let scrollButtonFullVisibilityThreshold: CGFloat = 80
    /// The button will be invisible until the user has scrolled at least this amount from the bottom of the table view.
    static let scrollButtonNoVisibilityThreshold: CGFloat = 20
    
    // MARK: Lifecycle
    init(thread: TSThread, focusedMessageID: String? = nil) {
        self.thread = thread
        self.focusedMessageID = focusedMessageID
        super.init(nibName: nil, bundle: nil)
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
        scrollButton.pin(.right, to: .right, of: view, withInset: -Values.mediumSpacing)
        // Blocked banner
        addOrRemoveBlockedBanner()
        // Notifications
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleKeyboardWillChangeFrameNotification(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleKeyboardWillHideNotification(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleAudioDidFinishPlayingNotification(_:)), name: .SNAudioDidFinishPlaying, object: nil)
        notificationCenter.addObserver(self, selector: #selector(addOrRemoveBlockedBanner), name: NSNotification.Name(rawValue: kNSNotificationName_BlockListDidChange), object: nil)
        // Mentions
        MentionsManager.populateUserPublicKeyCacheIfNeeded(for: thread.uniqueId!)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didFinishInitialLayout {
            DispatchQueue.main.async {
                self.scrollToBottom(isAnimated: false)
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didFinishInitialLayout = true
        markAllAsRead()
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
        cell.conversationStyle = conversationStyle()
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
        if !didConstrainScrollButton {
            // Bit of a hack to do this here, but it works out.
            scrollButton.pin(.bottom, to: .bottom, of: view, withInset: -(newHeight + Values.mediumSpacing))
            didConstrainScrollButton = true
        }
        UIView.animate(withDuration: 0.25) {
            self.messagesTableView.keyboardHeight = newHeight
            self.scrollButton.alpha = 0
        }
    }
    
    @objc func handleKeyboardWillHideNotification(_ notification: Notification) {
        UIView.animate(withDuration: 0.25) {
            self.messagesTableView.keyboardHeight = 0
            self.scrollButton.alpha = self.getScrollButtonOpacity()
        }
    }
    
    func conversationViewModelWillUpdate() {
        
    }
    
    func conversationViewModelDidUpdate(_ conversationUpdate: ConversationUpdate) {
        guard self.isViewLoaded else { return }
        // TODO: Reload the thread if it's a group thread?
        let updateType = conversationUpdate.conversationUpdateType
        guard updateType != .minor else { return } // No view items were affected
        if updateType == .reload {
            return messagesTableView.reloadData()
        }
        var shouldScrollToBottom = false
        let shouldAnimate = conversationUpdate.shouldAnimateUpdates
        let batchUpdates: () -> Void = {
            for update in conversationUpdate.updateItems! {
                switch update.updateItemType {
                case .delete:
                    self.messagesTableView.deleteRows(at: [ IndexPath(row: Int(update.oldIndex), section: 0) ], with: .fade)
                case .insert:
                    // Perform inserts before updates
                    self.messagesTableView.insertRows(at: [ IndexPath(row: Int(update.newIndex), section: 0) ], with: .fade)
                    let viewItem = update.viewItem
                    if viewItem?.interaction is TSOutgoingMessage {
                        shouldScrollToBottom = true
                    }
                case .update:
                    self.messagesTableView.reloadRows(at: [ IndexPath(row: Int(update.oldIndex), section: 0) ], with: .fade)
                default: preconditionFailure()
                }
            }
        }
        let batchUpdatesCompletion: (Bool) -> Void = { isFinished in
            // TODO: Update last visible sort ID?
            if shouldScrollToBottom {
                self.scrollToBottom(isAnimated: true)
            }
            // TODO: Update last known distance from bottom
        }
        if shouldAnimate {
            messagesTableView.performBatchUpdates(batchUpdates, completion: batchUpdatesCompletion)
        } else {
            // HACK: We use `UIView.animateWithDuration:0` rather than `UIView.performWithAnimation` to work around a
            // UIKit Crash like:
            //
            //     *** Assertion failure in -[ConversationViewLayout prepareForCollectionViewUpdates:],
            //     /BuildRoot/Library/Caches/com.apple.xbs/Sources/UIKit_Sim/UIKit-3600.7.47/UICollectionViewLayout.m:760
            //     *** Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'While
            //     preparing update a visible view at <NSIndexPath: 0xc000000011c00016> {length = 2, path = 0 - 142}
            //     wasn't found in the current data model and was not in an update animation. This is an internal
            //     error.'
            //
            // I'm unclear if this is a bug in UIKit, or if we're doing something crazy in
            // ConversationViewLayout#prepareLayout. To reproduce, rapidily insert and delete items into the
            // conversation.
            UIView.animate(withDuration: 0) {
                self.messagesTableView.performBatchUpdates(batchUpdates, completion: batchUpdatesCompletion)
                if shouldScrollToBottom {
                    self.scrollToBottom(isAnimated: false)
                }
            }
        }
        // TODO: Set last reload date?
    }
    
    func conversationViewModelWillLoadMoreItems() {
        view.layoutIfNeeded()
        scrollDistanceToBottomBeforeUpdate = messagesTableView.contentSize.height - messagesTableView.contentOffset.y
    }
    
    func conversationViewModelDidLoadMoreItems() {
        guard let scrollDistanceToBottomBeforeUpdate = scrollDistanceToBottomBeforeUpdate else { return }
        view.layoutIfNeeded()
        messagesTableView.contentOffset.y = messagesTableView.contentSize.height - scrollDistanceToBottomBeforeUpdate
        isLoadingMore = false
    }
    
    func conversationViewModelDidLoadPrevPage() {
        
    }
    
    func conversationViewModelRangeDidChange() {
        
    }
    
    func conversationViewModelDidReset() {
        
    }
    
    // MARK: General
    @objc func addOrRemoveBlockedBanner() {
        func detach() {
            blockedBanner.removeFromSuperview()
        }
        guard let thread = thread as? TSContactThread else { return detach() }
        if OWSBlockingManager.shared().isRecipientIdBlocked(thread.contactIdentifier()) {
            view.addSubview(blockedBanner)
            blockedBanner.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top, UIView.HorizontalEdge.right ], to: view)
        } else {
            detach()
        }
    }
    
    func markAllAsRead() {
        guard let lastSortID = viewItems.last?.interaction.sortId else { return }
        OWSReadReceiptManager.shared().markAsReadLocally(beforeSortId: lastSortID, thread: thread)
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
        // TODO: Did scroll to bottom
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserScrolling = true
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        isUserScrolling = false
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollButton.alpha = getScrollButtonOpacity()
        autoLoadMoreIfNeeded()
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
        // Do nothing
    }
    
    // MARK: Search
    func conversationSettingsDidRequestConversationSearch(_ conversationSettingsViewController: OWSConversationSettingsViewController) {
        showSearchUI()
        popAllConversationSettingsViews {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
    }
    
    func didDismissSearchController(_ searchController: UISearchController) {
        hideSearchUI()
    }
    
    func conversationSearchController(_ conversationSearchController: ConversationSearchController, didUpdateSearchResults resultSet: ConversationScreenSearchResultSet?) {
        messagesTableView.reloadRows(at: messagesTableView.indexPathsForVisibleRows ?? [], with: UITableView.RowAnimation.none)
    }
    
    func conversationSearchController(_ conversationSearchController: ConversationSearchController, didSelectMessageId interactionID: String) {
        scrollToInteraction(with: interactionID)
    }
    
    private func scrollToInteraction(with interactionID: String) {
        guard let indexPath = viewModel.ensureLoadWindowContainsInteractionId(interactionID) else { return }
        messagesTableView.scrollToRow(at: indexPath, at: UITableView.ScrollPosition.middle, animated: true)
    }
}
