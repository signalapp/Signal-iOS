
// TODO
// • Tapping replies
// • Mentions
// • Remaining send logic
// • Recording voice messages
// • Slight paging glitch
// • Scrolling bug
// • Scroll button bug
// • Image detail VC transition glitch

final class ConversationVC : BaseVC, ConversationViewModelDelegate, UITableViewDataSource, UITableViewDelegate {
    let thread: TSThread
    private let focusedMessageID: String?
    private var didConstrainScrollButton = false
    // Audio playback & recording
    var audioPlayer: OWSAudioPlayer?
    var audioRecorder: AVAudioRecorder?
    var audioTimer: Timer?
    // Context menu
    var contextMenuWindow: ContextMenuWindow?
    var contextMenuVC: ContextMenuVC?
    // Scrolling & paging
    private var isUserScrolling = false
    private var hasPerformedInitialScroll = false
    private var isLoadingMore = false
    private var scrollDistanceToBottomBeforeUpdate: CGFloat?

    var audioSession: OWSAudioSession { Environment.shared.audioSession }
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
        result.countLimit = 40
        return result
    }()

    lazy var recordVoiceMessageActivity = AudioActivity(audioDescription: "Voice message", behavior: .playAndRecord)
    
    // MARK: UI Components
    private lazy var titleView = ConversationTitleViewV2(thread: thread)

    lazy var messagesTableView: MessagesTableView = {
        let result = MessagesTableView()
        result.dataSource = self
        result.delegate = self
        return result
    }()
    
    lazy var snInputView = InputView(delegate: self)
    
    private lazy var scrollButton = ScrollToBottomButton(delegate: self)
    
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
            self.messagesTableView.keyboardHeight = newHeight
            self.scrollButton.alpha = 0
        }
    }
    
    @objc private func handleKeyboardWillHideNotification(_ notification: Notification) {
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
    
    @objc private func addOrRemoveBlockedBanner() {
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
    
    // MARK: General
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

    func showLinkPreviewSuggestionModal() {
        let linkPreviewModel = LinkPreviewModal() { [weak self] in
            self?.snInputView.autoGenerateLinkPreview()
        }
        linkPreviewModel.modalPresentationStyle = .overFullScreen
        linkPreviewModel.modalTransitionStyle = .crossDissolve
        present(linkPreviewModel, animated: true, completion: nil)
    }

    func showFailedMessageSheet(for tsMessage: TSOutgoingMessage) {
        let thread = self.thread
        let sheet = UIAlertController(title: tsMessage.mostRecentFailureText, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            Storage.write { transaction in
                tsMessage.remove(with: transaction)
                Storage.shared.cancelPendingMessageSendJobIfNeeded(for: tsMessage.timestamp, using: transaction)
            }
        }))
        sheet.addAction(UIAlertAction(title: "Resend", style: .default, handler: { _ in
            let message = VisibleMessage.from(tsMessage)
            Storage.write { transaction in
                var attachments: [TSAttachmentStream] = []
                tsMessage.attachmentIds.forEach { attachmentID in
                    guard let attachmentID = attachmentID as? String else { return }
                    let attachment = TSAttachment.fetch(uniqueId: attachmentID, transaction: transaction)
                    guard let stream = attachment as? TSAttachmentStream else { return }
                    attachments.append(stream)
                }
                MessageSender.prep(attachments, for: message, using: transaction)
                MessageSender.send(message, in: thread, using: transaction)
            }
        }))
        present(sheet, animated: true, completion: nil)
    }
    
    // MARK: Convenience
    private func getScrollButtonOpacity() -> CGFloat {
        let contentOffsetY = messagesTableView.contentOffset.y
        let x = (lastPageTop - ConversationVC.bottomInset - contentOffsetY).clamp(0, .greatestFiniteMagnitude)
        let a = 1 / (ConversationVC.scrollButtonFullVisibilityThreshold - ConversationVC.scrollButtonNoVisibilityThreshold)
        return a * x
    }
}
