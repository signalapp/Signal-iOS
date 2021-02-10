
// TODO
// • Tapping replies
// • Mentions
// • Remaining send logic
// • Paging glitch
// • Blocking
// • Subtitle
// • Resending failed messages
// • Linkification
// • Link previews
// • Canceling replies

final class ConversationVC : BaseVC, ConversationViewModelDelegate, UITableViewDataSource, UITableViewDelegate {
    let thread: TSThread
    private let focusedMessageID: String?
    var audioPlayer: OWSAudioPlayer?
    private var didConstrainScrollButton = false
    // Context menu
    var contextMenuWindow: ContextMenuWindow?
    var contextMenuVC: ContextMenuVC?
    // Scrolling & paging
    private var isUserScrolling = false
    private var hasPerformedInitialScroll = false
    private var isLoadingMore = false
    private var scrollDistanceToBottomBeforeUpdate: CGFloat?
    
    private var dbConnection: YapDatabaseConnection { OWSPrimaryStorage.shared().uiDatabaseConnection }
    var viewItems: [ConversationViewItem] { viewModel.viewState.viewItems }
    func conversationStyle() -> ConversationStyle { return ConversationStyle(thread: thread) }
    override var inputAccessoryView: UIView? { snInputView }
    override var canBecomeFirstResponder: Bool { true }

    private var tableViewUnobscuredHeight: CGFloat {
        let bottomInset = messagesTableView.adjustedContentInset.bottom + ConversationVC.bottomInset
        return messagesTableView.bounds.height - bottomInset
    }

    private var lastPageTop: CGFloat {
        return messagesTableView.contentSize.height - tableViewUnobscuredHeight
    }
    
    lazy var viewModel = ConversationViewModel(thread: thread, focusMessageIdOnOpen: focusedMessageID, delegate: self)
    
    private lazy var mediaCache: NSCache<NSString, AnyObject> = {
        let result = NSCache<NSString, AnyObject>()
        result.countLimit = 24
        return result
    }()
    
    // MARK: UI Components
    lazy var messagesTableView: UITableView = {
        let result = UITableView()
        result.dataSource = self
        result.delegate = self
        result.register(VisibleMessageCell.self, forCellReuseIdentifier: VisibleMessageCell.identifier)
        result.register(InfoMessageCell.self, forCellReuseIdentifier: InfoMessageCell.identifier)
        result.register(TypingIndicatorCellV2.self, forCellReuseIdentifier: TypingIndicatorCellV2.identifier)
        result.separatorStyle = .none
        result.backgroundColor = .clear
        result.contentInset = UIEdgeInsets(top: 0, leading: 0, bottom: ConversationVC.bottomInset, trailing: 0)
        result.showsVerticalScrollIndicator = false
        result.contentInsetAdjustmentBehavior = .never
        result.keyboardDismissMode = .interactive
        return result
    }()
    
    lazy var snInputView = InputView(delegate: self)
    
    private lazy var scrollButton = ScrollToBottomButton(delegate: self)
    
    // MARK: Settings
    private static let bottomInset = Values.mediumSpacing
    private static let loadMoreThreshold: CGFloat = 120
    /// The button will be fully visible once the user has scrolled this amount from the bottom of the table view.
    private static let scrollButtonFullVisibilityThreshold: CGFloat = 80
    /// The button will be invisible until the user has scrolled at least this amount from the bottom of the table view.
    private static let scrollButtonNoVisibilityThreshold: CGFloat = 20
    
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
        setNavBarTitle(getTitle())
        updateNavBarButtons()
        // Constraints
        view.addSubview(messagesTableView)
        messagesTableView.pin(to: view)
        view.addSubview(scrollButton)
        scrollButton.pin(.right, to: .right, of: view, withInset: -Values.mediumSpacing)
        // Notifications
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleKeyboardWillChangeFrameNotification(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleKeyboardWillHideNotification(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleAudioDidFinishPlayingNotification(_:)), name: .SNAudioDidFinishPlaying, object: nil)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !hasPerformedInitialScroll {
            scrollToBottom(isAnimated: false)
            hasPerformedInitialScroll = true
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let lastSortID = viewItems.last?.interaction.sortId else { return }
        OWSReadReceiptManager.shared().markAsReadLocally(beforeSortId: lastSortID, thread: thread)
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
    private func updateNavBarButtons() {
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
    
    @objc private func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        guard let newHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.size.height else { return }
        if !didConstrainScrollButton {
            // Bit of a hack to do this here, but it works out.
            scrollButton.pin(.bottom, to: .bottom, of: view, withInset: -(newHeight + Values.mediumSpacing))
            didConstrainScrollButton = true
        }
        UIView.animate(withDuration: 0.25) {
            self.messagesTableView.contentInset = UIEdgeInsets(top: 0, leading: 0, bottom: newHeight + ConversationVC.bottomInset, trailing: 0)
            self.scrollButton.alpha = 0
        }
    }
    
    @objc private func handleKeyboardWillHideNotification(_ notification: Notification) {
        UIView.animate(withDuration: 0.25) {
            self.messagesTableView.contentInset = UIEdgeInsets(top: 0, leading: 0, bottom: ConversationVC.bottomInset, trailing: 0)
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
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func getMediaCache() -> NSCache<NSString, AnyObject> {
        return mediaCache
    }

    @objc private func handleAudioDidFinishPlayingNotification(_ notification: Notification) {
        guard let audioPlayer = audioPlayer, let viewItem = audioPlayer.owner as? ConversationViewItem,
            let index = viewItems.firstIndex(where: { $0 === viewItem }), index < (viewItems.endIndex - 1) else { return }
        let nextViewItem = viewItems[index + 1]
        guard nextViewItem.messageCellType == .audio else { return }
        playOrPauseAudio(for: nextViewItem)
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
    
    private func autoLoadMoreIfNeeded() {
        let isMainAppAndActive = CurrentAppContext().isMainAppAndActive
        guard isMainAppAndActive && viewModel.canLoadMoreItems() && !isLoadingMore
            && messagesTableView.contentOffset.y < ConversationVC.loadMoreThreshold else { return }
        isLoadingMore = true
        viewModel.loadAnotherPageOfMessages()
    }
    
    // MARK: Convenience
    private func getTitle() -> String {
        if let thread = thread as? TSGroupThread {
            return thread.groupModel.groupName!
        } else if thread.isNoteToSelf() {
            return "Note to Self"
        } else {
            let sessionID = thread.contactIdentifier()!
            var result = sessionID
            Storage.read { transaction in
                result = Storage.shared.getContact(with: sessionID)?.displayName ?? "Anonymous"
            }
            return result
        }
    }
    
    private func getScrollButtonOpacity() -> CGFloat {
        let contentOffsetY = messagesTableView.contentOffset.y
        let x = (lastPageTop - ConversationVC.bottomInset - contentOffsetY).clamp(0, .greatestFiniteMagnitude)
        let a = 1 / (ConversationVC.scrollButtonFullVisibilityThreshold - ConversationVC.scrollButtonNoVisibilityThreshold)
        return a * x
    }
}
