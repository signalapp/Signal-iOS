// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

// TODO:
// • Slight paging glitch when scrolling up and loading more content
// • Photo rounding (the small corners don't have the correct rounding)
// • Remaining search glitchiness

final class ConversationVC: BaseVC, OWSConversationSettingsViewDelegate, ConversationSearchControllerDelegate, UITableViewDataSource, UITableViewDelegate {
    internal let viewModel: ConversationViewModel
    private var dataChangeObservable: DatabaseCancellable?
    private var hasLoadedInitialData: Bool = false
    
    var focusedMessageIndexPath: IndexPath?
    var initialUnreadCount: UInt = 0
    var unreadViewItems: [ConversationViewItem] = []
    var scrollButtonBottomConstraint: NSLayoutConstraint?
    var scrollButtonMessageRequestsBottomConstraint: NSLayoutConstraint?
    var messageRequestsViewBotomConstraint: NSLayoutConstraint?
    
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
    var currentMentionStartIndex: String.Index?
    var mentions: [ConversationViewModel.MentionInfo] = []
    
    // Scrolling & paging
    var isUserScrolling = false
    var didFinishInitialLayout = false
    var isLoadingMore = false
    var scrollDistanceToBottomBeforeUpdate: CGFloat?
    var baselineKeyboardHeight: CGFloat = 0

    var audioSession: OWSAudioSession { Environment.shared.audioSession }
    override var canBecomeFirstResponder: Bool { true }

    override var inputAccessoryView: UIView? {
        guard
            viewModel.viewData.thread.variant != .closedGroup ||
            viewModel.viewData.isClosedGroupMember
        else { return nil }
        
        return (isShowingSearchUI ? searchController.resultsBar : snInputView)
    }

    /// The height of the visible part of the table view, i.e. the distance from the navigation bar (where the table view's origin is)
    /// to the top of the input view (`tableView.adjustedContentInset.bottom`).
    var tableViewUnobscuredHeight: CGFloat {
        let bottomInset = tableView.adjustedContentInset.bottom
        return tableView.bounds.height - bottomInset
    }

    /// The offset at which the table view is exactly scrolled to the bottom.
    var lastPageTop: CGFloat {
        return tableView.contentSize.height - tableViewUnobscuredHeight
    }

    var isCloseToBottom: Bool {
        let margin = (self.lastPageTop - self.tableView.contentOffset.y)
        return margin <= ConversationVC.scrollToBottomMargin
    }

    lazy var mnemonic: String = {
        if let hexEncodedSeed: String = Identity.fetchHexEncodedSeed() {
            return Mnemonic.encode(hexEncodedString: hexEncodedSeed)
        }

        // Legacy account
        return Mnemonic.encode(hexEncodedString: Identity.fetchUserPrivateKey()!.toHexString())
    }()

    // FIXME: Would be good to create a Swift-based cache and replace this
    lazy var mediaCache: NSCache<NSString, AnyObject> = {
        let result = NSCache<NSString, AnyObject>()
        result.countLimit = 40
        return result
    }()

    lazy var recordVoiceMessageActivity = AudioActivity(audioDescription: "Voice message", behavior: .playAndRecord)

    lazy var searchController: ConversationSearchController = {
        let result: ConversationSearchController = ConversationSearchController()
        result.uiSearchController.obscuresBackgroundDuringPresentation = false
        result.delegate = self
        
        return result
    }()

    // MARK: - UI

    private static let messageRequestButtonHeight: CGFloat = 34

    lazy var titleView: ConversationTitleView = {
        let result: ConversationTitleView = ConversationTitleView()
        let tapGestureRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleTitleViewTapped)
        )
        result.addGestureRecognizer(tapGestureRecognizer)
        
        return result
    }()

    lazy var tableView: UITableView = {
        let result: UITableView = UITableView()
        result.separatorStyle = .none
        result.backgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        result.contentInsetAdjustmentBehavior = .never
        result.keyboardDismissMode = .interactive
        result.contentInset = UIEdgeInsets(
            top: 0,
            leading: 0,
            bottom: Values.mediumSpacing,
            trailing: 0
        )
        result.register(view: VisibleMessageCell.self)
        result.register(view: InfoMessageCell.self)
        result.register(view: TypingIndicatorCell.self)
        result.dataSource = self
        result.delegate = self

        return result
    }()

    lazy var snInputView: InputView = InputView(
        threadVariant: viewModel.viewData.thread.variant,
        delegate: self
    )

    lazy var unreadCountView: UIView = {
        let result: UIView = UIView()
        result.backgroundColor = Colors.text.withAlphaComponent(Values.veryLowOpacity)
        result.set(.width, greaterThanOrEqualTo: ConversationVC.unreadCountViewSize)
        result.set(.height, to: ConversationVC.unreadCountViewSize)
        result.layer.masksToBounds = true
        result.layer.cornerRadius = (ConversationVC.unreadCountViewSize / 2)
        
        return result
    }()

    lazy var unreadCountLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        result.textColor = Colors.text
        result.textAlignment = .center
        
        return result
    }()

    lazy var blockedBanner: InfoBanner = {
        let result: InfoBanner = InfoBanner(
            message: viewModel.blockedBannerMessage,
            backgroundColor: Colors.destructive
        )
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(unblock))
        result.addGestureRecognizer(tapGestureRecognizer)
        
        return result
    }()

    lazy var footerControlsStackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.axis = .vertical
        result.alignment = .trailing
        result.distribution = .equalSpacing
        result.spacing = 10
        result.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        result.isLayoutMarginsRelativeArrangement = true

        return result
    }()

    lazy var scrollButton: ScrollToBottomButton = ScrollToBottomButton(delegate: self)

    lazy var messageRequestView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isHidden = !viewModel.viewData.threadIsMessageRequest
        result.setGradient(Gradients.defaultBackground)

        return result
    }()

    private let messageRequestDescriptionLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = UIFont.systemFont(ofSize: 12)
        result.text = NSLocalizedString("MESSAGE_REQUESTS_INFO", comment: "")
        result.textColor = Colors.sessionMessageRequestsInfoText
        result.textAlignment = .center
        result.numberOfLines = 2

        return result
    }()

    private let messageRequestAcceptButton: UIButton = {
        let result: UIButton = UIButton()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.clipsToBounds = true
        result.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        result.setTitle(NSLocalizedString("TXT_DELETE_ACCEPT", comment: ""), for: .normal)
        result.setTitleColor(Colors.sessionHeading, for: .normal)
        result.setBackgroundImage(
            Colors.sessionHeading
                .withAlphaComponent(isDarkMode ? 0.2 : 0.06)
                .toImage(isDarkMode: isDarkMode),
            for: .highlighted
        )
        result.layer.cornerRadius = (ConversationVC.messageRequestButtonHeight / 2)
        result.layer.borderColor = {
            if #available(iOS 13.0, *) {
                return Colors.sessionHeading
                    .resolvedColor(
                        // Note: This is needed for '.cgColor' to support dark mode
                        with: UITraitCollection(userInterfaceStyle: isDarkMode ? .dark : .light)
                    ).cgColor
            }

            return Colors.sessionHeading.cgColor
        }()
        result.layer.borderWidth = 1
        result.addTarget(self, action: #selector(acceptMessageRequest), for: .touchUpInside)

        return result
    }()

    private let messageRequestDeleteButton: UIButton = {
        let result: UIButton = UIButton()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.clipsToBounds = true
        result.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        result.setTitle(NSLocalizedString("TXT_DELETE_TITLE", comment: ""), for: .normal)
        result.setTitleColor(Colors.destructive, for: .normal)
        result.setBackgroundImage(
            Colors.destructive
                .withAlphaComponent(isDarkMode ? 0.2 : 0.06)
                .toImage(isDarkMode: isDarkMode),
            for: .highlighted
        )
        result.layer.cornerRadius = (ConversationVC.messageRequestButtonHeight / 2)
        result.layer.borderColor = {
            if #available(iOS 13.0, *) {
                return Colors.destructive
                    .resolvedColor(
                        // Note: This is needed for '.cgColor' to support dark mode
                        with: UITraitCollection(userInterfaceStyle: isDarkMode ? .dark : .light)
                    ).cgColor
            }

            return Colors.destructive.cgColor
        }()
        result.layer.borderWidth = 1
        result.addTarget(self, action: #selector(deleteMessageRequest), for: .touchUpInside)

        return result
    }()

    // MARK: - Settings
    
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

    // MARK: - Initialization
    
    init?(threadId: String, focusedInteractionId: Int64? = nil) {
        guard let viewModel: ConversationViewModel = ConversationViewModel(threadId: threadId, focusedInteractionId: focusedInteractionId) else {
            return nil
        }
        
        self.viewModel = viewModel
        
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(thread:) instead.")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Gradient
        setUpGradientBackground()
        
        // Nav bar
        setUpNavBarStyle()
        navigationItem.titleView = titleView
        
        titleView.update(
            with: viewModel.viewData.threadName,
            mutedUntilTimestamp: viewModel.viewData.thread.mutedUntilTimestamp,
            onlyNotifyForMentions: viewModel.viewData.thread.onlyNotifyForMentions,
            userCount: viewModel.viewData.userCount
        )
        updateNavBarButtons(viewData: viewModel.viewData)
        
        // Constraints
        view.addSubview(tableView)
        tableView.pin(to: view)

        // Blocked banner
        addOrRemoveBlockedBanner(threadIsBlocked: viewModel.viewData.threadIsBlocked)

        // Message requests view & scroll to bottom
        view.addSubview(scrollButton)
        view.addSubview(messageRequestView)

        messageRequestView.addSubview(messageRequestDescriptionLabel)
        messageRequestView.addSubview(messageRequestAcceptButton)
        messageRequestView.addSubview(messageRequestDeleteButton)

        scrollButton.pin(.right, to: .right, of: view, withInset: -20)
        messageRequestView.pin(.left, to: .left, of: view)
        messageRequestView.pin(.right, to: .right, of: view)
        self.messageRequestsViewBotomConstraint = messageRequestView.pin(.bottom, to: .bottom, of: view, withInset: -16)
        self.scrollButtonBottomConstraint = scrollButton.pin(.bottom, to: .bottom, of: view, withInset: -16)
        self.scrollButtonBottomConstraint?.isActive = false // Note: Need to disable this to avoid a conflict with the other bottom constraint
        self.scrollButtonMessageRequestsBottomConstraint = scrollButton.pin(.bottom, to: .top, of: messageRequestView, withInset: -16)
        self.scrollButtonMessageRequestsBottomConstraint?.isActive = viewModel.viewData.threadIsMessageRequest
        self.scrollButtonBottomConstraint?.isActive = !viewModel.viewData.threadIsMessageRequest
        
        messageRequestDescriptionLabel.pin(.top, to: .top, of: messageRequestView, withInset: 10)
        messageRequestDescriptionLabel.pin(.left, to: .left, of: messageRequestView, withInset: 40)
        messageRequestDescriptionLabel.pin(.right, to: .right, of: messageRequestView, withInset: -40)

        messageRequestAcceptButton.pin(.top, to: .bottom, of: messageRequestDescriptionLabel, withInset: 20)
        messageRequestAcceptButton.pin(.left, to: .left, of: messageRequestView, withInset: 20)
        messageRequestAcceptButton.pin(.bottom, to: .bottom, of: messageRequestView)
        messageRequestAcceptButton.set(.height, to: ConversationVC.messageRequestButtonHeight)

        messageRequestAcceptButton.pin(.top, to: .bottom, of: messageRequestDescriptionLabel, withInset: 20)
        messageRequestAcceptButton.pin(.left, to: .left, of: messageRequestView, withInset: 20)
        messageRequestAcceptButton.pin(.bottom, to: .bottom, of: messageRequestView)
        messageRequestAcceptButton.set(.height, to: ConversationVC.messageRequestButtonHeight)

        messageRequestDeleteButton.pin(.top, to: .bottom, of: messageRequestDescriptionLabel, withInset: 20)
        messageRequestDeleteButton.pin(.left, to: .right, of: messageRequestAcceptButton, withInset: 20)
        messageRequestDeleteButton.pin(.right, to: .right, of: messageRequestView, withInset: -20)
        messageRequestDeleteButton.pin(.bottom, to: .bottom, of: messageRequestView)
        messageRequestDeleteButton.set(.width, to: .width, of: messageRequestAcceptButton)
        messageRequestDeleteButton.set(.height, to: ConversationVC.messageRequestButtonHeight)

        // Unread count view
        view.addSubview(unreadCountView)
        unreadCountView.addSubview(unreadCountLabel)
        unreadCountLabel.pin(.top, to: .top, of: unreadCountView)
        unreadCountLabel.pin(.bottom, to: .bottom, of: unreadCountView)
        unreadCountView.pin(.leading, to: .leading, of: unreadCountLabel, withInset: -4)
        unreadCountView.pin(.trailing, to: .trailing, of: unreadCountLabel, withInset: 4)
        unreadCountView.centerYAnchor.constraint(equalTo: scrollButton.topAnchor).isActive = true
        unreadCountView.center(.horizontal, in: scrollButton)
        updateUnreadCountView(unreadCount: viewModel.viewData.unreadCount)

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillChangeFrameNotification(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillHideNotification(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        // Mentions
        MentionsManager.populateUserPublicKeyCacheIfNeeded(for: viewModel.viewData.thread.id)
        
        // Draft
        if let draft: String = viewModel.viewData.thread.messageDraft, !draft.isEmpty {
            snInputView.text = draft
        }

        // Update the input state
        snInputView.setEnabledMessageTypes(viewModel.viewData.enabledMessageTypes, message: nil)

    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        guard !didFinishInitialLayout else { return }
        
        // Scroll to the last unread message if possible; otherwise scroll to the bottom.
        // When the unread message count is more than the number of view items of a page,
        // the screen will scroll to the bottom instead of the first unread message.
        // unreadIndicatorIndex is calculated during loading of the viewItems, so it's
        // supposed to be accurate.
        DispatchQueue.main.async {
            if let focusedInteractionId: Int64 = self.viewModel.focusedInteractionId {
                self.scrollToInteraction(with: focusedInteractionId, isAnimated: false, highlighted: true)
            }
            else if let firstUnreadInteractionId: Int64 = self.viewModel.viewData.firstUnreadInteractionId {
                self.scrollToInteraction(with: firstUnreadInteractionId, position: .top, isAnimated: false)
                self.unreadCountView.alpha = self.scrollButton.alpha
            }
            else {
                self.scrollToBottom(isAnimated: false)
            }
            
            self.scrollButton.alpha = self.getScrollButtonOpacity()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        startObservingChanges()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        highlightFocusedMessageIfNeeded()
        didFinishInitialLayout = true
        viewModel.markAllAsRead()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Stop observing database changes
        dataChangeObservable?.cancel()
        viewModel.updateDraft(to: snInputView.text)
        inputAccessoryView?.resignFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        mediaCache.removeAllObjects()
    }
    
    @objc func applicationDidBecomeActive(_ notification: Notification) {
        startObservingChanges()
    }
    
    @objc func applicationDidResignActive(_ notification: Notification) {
        // Stop observing database changes
        dataChangeObservable?.cancel()
    }
    
    // MARK: - Updating
    
    private func startObservingChanges() {
        // Start observing for data changes
        dataChangeObservable = GRDBStorage.shared.start(
            viewModel.observableViewData,
            onError:  { error in
            },
            onChange: { [weak self] viewData in
                // The default scheduler emits changes on the main thread
                self?.handleUpdates(viewData)
            }
        )
    }
    
    private func handleUpdates(_ updatedViewData: ConversationViewModel.ViewData, initialLoad: Bool = false) {
        // Ensure the first load runs without animations (if we don't do this the cells will animate
        // in from a frame of CGRect.zero)
        guard hasLoadedInitialData else {
            hasLoadedInitialData = true
            UIView.performWithoutAnimation { handleUpdates(updatedViewData, initialLoad: true) }
            return
        }
        // Update general conversation UI
        
        if
            initialLoad ||
            viewModel.viewData.threadName != updatedViewData.threadName ||
            viewModel.viewData.thread.mutedUntilTimestamp != updatedViewData.thread.mutedUntilTimestamp ||
            viewModel.viewData.thread.onlyNotifyForMentions != updatedViewData.thread.onlyNotifyForMentions ||
            viewModel.viewData.userCount != updatedViewData.userCount
        {
            titleView.update(
                with: updatedViewData.threadName,
                mutedUntilTimestamp: updatedViewData.thread.mutedUntilTimestamp,
                onlyNotifyForMentions: updatedViewData.thread.onlyNotifyForMentions,
                userCount: updatedViewData.userCount
            )
        }
        
        if
            initialLoad ||
            viewModel.viewData.requiresApproval != updatedViewData.requiresApproval ||
            viewModel.viewData.threadAvatarProfiles != updatedViewData.threadAvatarProfiles
        {
            updateNavBarButtons(viewData: updatedViewData)
        }
        
        if initialLoad || viewModel.viewData.enabledMessageTypes != updatedViewData.enabledMessageTypes {
            snInputView.setEnabledMessageTypes(
                updatedViewData.enabledMessageTypes,
                message: nil
            )
        }
        
        if initialLoad || viewModel.viewData.threadIsBlocked != updatedViewData.threadIsBlocked {
            addOrRemoveBlockedBanner(threadIsBlocked: updatedViewData.threadIsBlocked)
        }
        
        if initialLoad || viewModel.viewData.unreadCount != updatedViewData.unreadCount {
            updateUnreadCountView(unreadCount: updatedViewData.unreadCount)
        }
        
        // Reload the table content (animate changes after the first load)
        let changeset = StagedChangeset(source: viewModel.viewData.items, target: updatedViewData.items)
        tableView.reload(
            using: StagedChangeset(source: viewModel.viewData.items, target: updatedViewData.items),
            interrupt: {
                return $0.changeCount > 100
            }    // Prevent too many changes from causing performance issues
        ) { [weak self] items in
            self?.viewModel.updateData(updatedViewData.with(items: items))
        }
        
        // Scroll to the bottom if we just inserted a message and are close enough
        // to the bottom
        if
            changeset.contains(where: { !$0.elementInserted.isEmpty }) && (
                updatedViewData.items.last?.interactionVariant == .standardOutgoing ||
                isCloseToBottom
            )
        {
            scrollToBottom(isAnimated: true)
        }
        
        // Mark received messages as read
        viewModel.markAllAsRead()
        viewModel.sentMessageBeforeUpdate = false
    }
    
    func updateNavBarButtons(viewData: ConversationViewModel.ViewData) {
        navigationItem.hidesBackButton = isShowingSearchUI

        if isShowingSearchUI {
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItems = []
        }
        else {
            guard !viewData.requiresApproval else {
                // Note: Adding an empty button because without it the title alignment is
                // busted (Note: The size was taken from the layout inspector for the back
                // button in Xcode
                navigationItem.rightBarButtonItem = UIBarButtonItem(
                    customView: UIView(
                        frame: CGRect(
                            x: 0,
                            y: 0,
                            width: (44 - 16), // Width of the standard back button
                            height: 44
                        )
                    )
                )
                return
            }
            
            switch viewData.thread.variant {
                case .contact:
                    let profilePictureView = ProfilePictureView()
                    profilePictureView.size = Values.verySmallProfilePictureSize
                    profilePictureView.update(
                        publicKey: viewData.thread.id,  // Contact thread uses the contactId
                        profile: viewData.threadAvatarProfiles.first,
                        threadVariant: viewData.thread.variant
                    )
                    profilePictureView.set(.width, to: (44 - 16))   // Width of the standard back button
                    profilePictureView.set(.height, to: Values.verySmallProfilePictureSize)

                    let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(openSettings))
                    profilePictureView.addGestureRecognizer(tapGestureRecognizer)

                    let rightBarButtonItem: UIBarButtonItem = UIBarButtonItem(customView: profilePictureView)
                    rightBarButtonItem.accessibilityLabel = "Settings button"
                    rightBarButtonItem.isAccessibilityElement = true

                    navigationItem.rightBarButtonItem = rightBarButtonItem
                    
                default:
                    let rightBarButtonItem: UIBarButtonItem = UIBarButtonItem(image: UIImage(named: "Gear"), style: .plain, target: self, action: #selector(openSettings))
                    rightBarButtonItem.accessibilityLabel = "Settings button"
                    rightBarButtonItem.isAccessibilityElement = true

                    navigationItem.rightBarButtonItem = rightBarButtonItem
            }
        }
    }
    
    private func highlightFocusedMessageIfNeeded() {
        if let indexPath = focusedMessageIndexPath, let cell = tableView.cellForRow(at: indexPath) as? VisibleMessageCell {
            cell.highlight()
            focusedMessageIndexPath = nil
        }
    }

    @objc func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        // Please refer to https://github.com/mapbox/mapbox-navigation-ios/issues/1600
        // and https://stackoverflow.com/a/25260930 to better understand what we are
        // doing with the UIViewAnimationOptions
        let userInfo: [AnyHashable: Any] = (notification.userInfo ?? [:])
        let duration = ((userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0)
        let curveValue: Int = ((userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? Int(UIView.AnimationOptions.curveEaseInOut.rawValue))
        let options: UIView.AnimationOptions = UIView.AnimationOptions(rawValue: UInt(curveValue << 16))
        let keyboardRect: CGRect = ((userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? CGRect.zero)

        // Calculate new positions (Need the ensure the 'messageRequestView' has been layed out as it's
        // needed for proper calculations, so force an initial layout if it doesn't have a size)
        var hasDoneLayout: Bool = true

        if messageRequestView.bounds.height <= CGFloat.leastNonzeroMagnitude {
            hasDoneLayout = false

            UIView.performWithoutAnimation {
                self.view.layoutIfNeeded()
            }
        }

        let keyboardTop = (UIScreen.main.bounds.height - keyboardRect.minY)
        let messageRequestsOffset: CGFloat = (messageRequestView.isHidden ? 0 : messageRequestView.bounds.height + 16)
        let oldContentInset: UIEdgeInsets = tableView.contentInset
        let newContentInset: UIEdgeInsets = UIEdgeInsets(
            top: 0,
            leading: 0,
            bottom: (Values.mediumSpacing + keyboardTop + messageRequestsOffset),
            trailing: 0
        )
        let newContentOffsetY: CGFloat = (tableView.contentOffset.y + (newContentInset.bottom - oldContentInset.bottom))
        let changes = { [weak self] in
            self?.scrollButtonBottomConstraint?.constant = -(keyboardTop + 16)
            self?.messageRequestsViewBotomConstraint?.constant = -(keyboardTop + 16)
            self?.tableView.contentInset = newContentInset
            self?.tableView.contentOffset.y = newContentOffsetY

            let scrollButtonOpacity: CGFloat = (self?.getScrollButtonOpacity() ?? 0)
            self?.scrollButton.alpha = scrollButtonOpacity

            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
        }

        // Perform the changes (don't animate if the initial layout hasn't been completed)
        guard hasDoneLayout else {
            UIView.performWithoutAnimation {
                changes()
            }
            return
        }

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: options,
            animations: changes,
            completion: nil
        )
    }

    @objc func handleKeyboardWillHideNotification(_ notification: Notification) {
        // Please refer to https://github.com/mapbox/mapbox-navigation-ios/issues/1600
        // and https://stackoverflow.com/a/25260930 to better understand what we are
        // doing with the UIViewAnimationOptions
        let userInfo: [AnyHashable: Any] = (notification.userInfo ?? [:])
        let duration = ((userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0)
        let curveValue: Int = ((userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? Int(UIView.AnimationOptions.curveEaseInOut.rawValue))
        let options: UIView.AnimationOptions = UIView.AnimationOptions(rawValue: UInt(curveValue << 16))

        let keyboardRect: CGRect = ((userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? CGRect.zero)
        let keyboardTop = (UIScreen.main.bounds.height - keyboardRect.minY)

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: options,
            animations: { [weak self] in
                self?.scrollButtonBottomConstraint?.constant = -(keyboardTop + 16)
                self?.messageRequestsViewBotomConstraint?.constant = -(keyboardTop + 16)

                let scrollButtonOpacity: CGFloat = (self?.getScrollButtonOpacity() ?? 0)
                self?.scrollButton.alpha = scrollButtonOpacity
                self?.unreadCountView.alpha = scrollButtonOpacity

                self?.view.setNeedsLayout()
                self?.view.layoutIfNeeded()
            },
            completion: nil
        )
    }
    
    func conversationViewModelWillUpdate() {
        // Not currently in use
    }
    
    func conversationViewModelDidUpdate(_ conversationUpdate: ConversationUpdate) {
        guard self.isViewLoaded else { return }
        let updateType = conversationUpdate.conversationUpdateType
        guard updateType != .minor else { return } // No view items were affected
        if updateType == .reload {
            if threadStartedAsMessageRequest {
                updateNavBarButtons()   // In case the message request was approved
            }
            
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
                
                // Update the nav items if the message request was approved
                if (update.viewItem?.interaction as? TSInfoMessage)?.messageType == .messageRequestAccepted {
                    self.updateNavBarButtons()
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
        }
        
        // Update the input state if this is a contact thread
        if let contactThread: TSContactThread = thread as? TSContactThread {
            let contact: Contact? = GRDBStorage.shared.read { db in try Contact.fetchOne(db, id: contactThread.contactSessionID()) }
            
            // If the contact doesn't exist yet then it's a message request without the first message sent
            // so only allow text-based messages
            self.snInputView.setEnabledMessageTypes(
                (thread.isNoteToSelf() || contact?.didApproveMe == true || thread.isMessageRequest() ?
                    .all : .textOnly
                ),
                message: nil
            )
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
            guard let indexPaths = self.tableView.indexPathsForVisibleRows else { return }
            var indexPathsToReload: [IndexPath] = []
            for indexPath in indexPaths {
                guard let cell = self.tableView.cellForRow(at: indexPath) as? VisibleMessageCell else { continue }
                let isLast = (indexPath.item == (self.tableView.numberOfRows(inSection: 0) - 1))
                guard !isLast else { continue }
                if !cell.messageStatusImageView.isHidden {
                    indexPathsToReload.append(indexPath)
                }
            }
            UIView.performWithoutAnimation {
                self.tableView.reloadRows(at: indexPathsToReload, with: .none)
            }
        }
    }

    // MARK: - General

    func addOrRemoveBlockedBanner(threadIsBlocked: Bool) {
        guard threadIsBlocked else {
            self.blockedBanner.removeFromSuperview()
            return
        }

        self.view.addSubview(self.blockedBanner)
        self.blockedBanner.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top, UIView.HorizontalEdge.right ], to: self.view)
    }

    // MARK: - UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.viewData.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item: ConversationViewModel.Item = viewModel.viewData.items[indexPath.row]
        let cell: MessageCell = tableView.dequeue(type: MessageCell.cellType(for: item), for: indexPath)
        cell.update(
            with: item,
            mediaCache: mediaCache,
            playbackInfo: viewModel.playbackInfo(for: item) { [weak self] updatedInfo, error in
                DispatchQueue.main.async {
                    guard error == nil else {
                        OWSAlerts.showErrorAlert(message: "INVALID_AUDIO_FILE_ALERT_ERROR_MESSAGE".localized())
                        return
                    }
                    
                    cell.dynamicUpdate(with: item, playbackInfo: updatedInfo)
                }
            },
            lastSearchText: viewModel.viewData.lastSearchedText
        )
        cell.delegate = self
        
        return cell
    }
    
    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func scrollToBottom(isAnimated: Bool) {
        guard !isUserScrolling && !viewModel.viewData.items.isEmpty else { return }
        
        tableView.scrollToRow(
            at: IndexPath(
                row: viewModel.viewData.items.count - 1,
                section: 0),
            at: .bottom,
            animated: isAnimated
        )
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
    }

    func updateUnreadCountView(unreadCount: Int) {
        let fontSize: CGFloat = (unreadCount < 10000 ? Values.verySmallFontSize : 8)
        unreadCountLabel.text = (unreadCount < 10000 ? "\(unreadCount)" : "9999+")
        unreadCountLabel.font = .boldSystemFont(ofSize: fontSize)
        unreadCountView.isHidden = (unreadCount == 0)
    }

    func autoLoadMoreIfNeeded() {
        let isMainAppAndActive = CurrentAppContext().isMainAppAndActive
        guard isMainAppAndActive && didFinishInitialLayout && viewModel.canLoadMoreItems() && !isLoadingMore
            && messagesTableView.contentOffset.y < ConversationVC.loadMoreThreshold else { return }
        isLoadingMore = true
        viewModel.loadAnotherPageOfMessages()
    }

    func getScrollButtonOpacity() -> CGFloat {
        let contentOffsetY = tableView.contentOffset.y
        let x = (lastPageTop - ConversationVC.bottomInset - contentOffsetY).clamp(0, .greatestFiniteMagnitude)
        let a = 1 / (ConversationVC.scrollButtonFullVisibilityThreshold - ConversationVC.scrollButtonNoVisibilityThreshold)
        return a * x
    }

    func groupWasUpdated(_ groupModel: TSGroupModel) {
        // Not currently in use
    }

    // MARK: - Search
    
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
        searchBar.setUpSessionStyle()
        navigationItem.titleView = searchBar
        
        // Nav bar buttons
        updateNavBarButtons(viewData: viewModel.viewData)
        
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
        updateNavBarButtons(viewData: viewModel.viewData)
        
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
        tableView.reloadRows(at: tableView.indexPathsForVisibleRows ?? [], with: UITableView.RowAnimation.none)
    }

    func conversationSearchController(_ conversationSearchController: ConversationSearchController, didSelectInteractionId interactionId: Int64) {
        scrollToInteraction(with: interactionId)
    }

    func scrollToInteraction(
        with interactionId: Int64,
        position: UITableView.ScrollPosition = .middle,
        isAnimated: Bool = true,
        highlighted: Bool = false
    ) {
    }
}
