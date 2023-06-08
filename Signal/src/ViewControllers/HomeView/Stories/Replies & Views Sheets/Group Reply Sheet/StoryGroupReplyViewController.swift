//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

protocol StoryGroupReplyDelegate: AnyObject {
    func storyGroupReplyViewControllerDidBeginEditing(_ storyGroupReplyViewController: StoryGroupReplyViewController)
}

class StoryGroupReplyViewController: OWSViewController, StoryReplySheet {
    weak var delegate: StoryGroupReplyDelegate?

    private(set) lazy var tableView = UITableView()

    let bottomBar = UIView()
    private(set) lazy var inputToolbar = StoryReplyInputToolbar()
    private lazy var bottomBarBottomConstraint = bottomBar.autoPinEdge(toSuperviewEdge: .bottom)
    private lazy var contextMenu = ContextMenuInteraction(delegate: self)

    private enum BottomBarMode {
        case member
        case nonMember
        case blockedByAnnouncementOnly
    }
    private var bottomBarMode: BottomBarMode?

    private lazy var inputAccessoryPlaceholder: InputAccessoryViewPlaceholder = {
        let placeholder = InputAccessoryViewPlaceholder()
        placeholder.delegate = self
        placeholder.referenceView = view
        return placeholder
    }()

    private lazy var emptyStateView: UIView = {
        let label = UILabel()
        label.font = .dynamicTypeBody
        label.textColor = .ows_gray45
        label.textAlignment = .center
        label.text = OWSLocalizedString("STORIES_NO_REPLIES_YET", comment: "Indicates that this story has no replies yet")
        label.isHidden = true
        label.isUserInteractionEnabled = false
        return label
    }()

    let storyMessage: StoryMessage
    lazy var thread: TSThread? = databaseStorage.read { storyMessage.context.thread(transaction: $0) }

    var reactionPickerBackdrop: UIView?
    var reactionPicker: MessageReactionPicker?

    init(storyMessage: StoryMessage) {
        self.storyMessage = storyMessage

        super.init()

        // Fetch profiles for everyone in the group to make sure we have the latest capability state
        if let thread = thread {
            bulkProfileFetch.fetchProfiles(addresses: thread.recipientAddressesWithSneakyTransaction)
        }

        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    fileprivate var replyLoader: StoryGroupReplyLoader?
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.keyboardDismissMode = .interactive
        tableView.backgroundColor = .ows_gray90
        tableView.addInteraction(contextMenu)

        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        inputToolbar.delegate = self
        view.addSubview(bottomBar)
        bottomBar.autoPinWidthToSuperview()
        bottomBarBottomConstraint.isActive = true
        // Its a bit silly but this is the easiest way to capture touches
        // and not let them pass up to any parent scrollviews. pans inside the
        // bottom bar shouldn't scroll anything.
        bottomBar.addGestureRecognizer(UIPanGestureRecognizer())

        for type in StoryGroupReplyCell.CellType.all {
            tableView.register(StoryGroupReplyCell.self, forCellReuseIdentifier: type.rawValue)
        }

        replyLoader = StoryGroupReplyLoader(storyMessage: storyMessage, threadUniqueId: thread?.uniqueId, tableView: tableView)

        view.insertSubview(emptyStateView, belowSubview: bottomBar)
        emptyStateView.autoPinWidthToSuperview()
        emptyStateView.autoPinEdge(toSuperviewEdge: .top)
        emptyStateView.autoPinEdge(.bottom, to: .top, of: bottomBar)

        updateBottomBarContents()
        updateBottomBarPosition()
    }

    public override var inputAccessoryView: UIView? { inputAccessoryPlaceholder }

    func didSendMessage() {
        replyLoader?.reload()
        inputToolbar.messageBody = nil
    }
}

extension StoryGroupReplyViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let visibleRows = tableView.indexPathsForVisibleRows?.map({ $0.row }),
              !visibleRows.isEmpty,
              let oldestLoadedRow = replyLoader?.oldestLoadedRow,
              let newestLoadedRow = replyLoader?.newestLoadedRow else { return }

        let rowsFromTop = (visibleRows.min() ?? oldestLoadedRow) - oldestLoadedRow
        let rowsFromBottom = newestLoadedRow - (visibleRows.max() ?? newestLoadedRow)

        if rowsFromTop <= 30 {
            replyLoader?.loadOlderPageIfNecessary()
        }

        if rowsFromBottom <= 30 {
            replyLoader?.loadNewerPageIfNecessary()
        }
    }
}

extension StoryGroupReplyViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        guard let item = replyLoader?.replyItem(for: indexPath) else { return }

        guard case .failed = item.recipientStatus else { return }

        do {
            try askToResendMessage(for: item)
        } catch {
            owsFailDebug("Failed to resend story reply \(error)")
        }
    }

    private func askToResendMessage(for item: StoryGroupReplyViewItem) throws {
        let (failedMessage, messageToSend) = try databaseStorage.read { transaction -> (TSOutgoingMessage, TSOutgoingMessage) in
            guard let message = TSOutgoingMessage.anyFetchOutgoingMessage(
                uniqueId: item.interactionUniqueId,
                transaction: transaction
            ) else {
                throw OWSAssertionError("Missing original message")
            }

            // If the message was remotely deleted, resend a *delete* message rather than the message itself.
            if message.wasRemotelyDeleted {
                guard let thread = thread else {
                    throw OWSAssertionError("Missing thread")
                }

                return (message, TSOutgoingDeleteMessage(thread: thread, message: message, transaction: transaction))
            } else {
                return (message, message)
            }
        }

        guard !askToConfirmSafetyNumberChangesIfNecessary(for: failedMessage, messageToSend: messageToSend) else { return }

        let actionSheet = ActionSheetController(
            message: failedMessage.mostRecentFailureText
        )
        actionSheet.addAction(OWSActionSheets.cancelAction)

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.deleteForMeButton,
            style: .destructive
        ) { _ in
            Self.databaseStorage.write { transaction in
                failedMessage.anyRemove(transaction: transaction)
            }
        })

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("SEND_AGAIN_BUTTON", comment: ""),
            style: .default
        ) { _ in
            Self.databaseStorage.write { transaction in
                Self.sskJobQueues.messageSenderJobQueue.add(
                    message: messageToSend.asPreparer,
                    transaction: transaction
                )
            }
        })

        self.presentActionSheet(actionSheet)
    }

    private func askToConfirmSafetyNumberChangesIfNecessary(for failedMessage: TSOutgoingMessage, messageToSend: TSOutgoingMessage) -> Bool {
        let recipientsWithChangedSafetyNumber = failedMessage.failedRecipientAddresses(errorCode: UntrustedIdentityError.errorCode)
        guard !recipientsWithChangedSafetyNumber.isEmpty else { return false }

        let sheet = SafetyNumberConfirmationSheet(
            addressesToConfirm: recipientsWithChangedSafetyNumber,
            confirmationText: MessageStrings.sendButton
        ) { confirmedSafetyNumberChange in
            guard confirmedSafetyNumberChange else { return }
            Self.databaseStorage.write { transaction in
                Self.sskJobQueues.messageSenderJobQueue.add(
                    message: messageToSend.asPreparer,
                    transaction: transaction
                )
            }
        }
        self.present(sheet, animated: true, completion: nil)

        return true
    }
}

extension StoryGroupReplyViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let item = replyLoader?.replyItem(for: indexPath) else {
            owsFailDebug("Missing item for cell at indexPath \(indexPath)")
            return UITableViewCell()
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: item.cellType.rawValue, for: indexPath) as! StoryGroupReplyCell
        cell.configure(with: item)

        return cell
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let numberOfRows = replyLoader?.numberOfRows ?? 0
        emptyStateView.isHidden = numberOfRows > 0
        return numberOfRows
    }
}

extension StoryGroupReplyViewController: InputAccessoryViewPlaceholderDelegate {
    public func inputAccessoryPlaceholderKeyboardIsPresenting(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        handleKeyboardStateChange(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    public func inputAccessoryPlaceholderKeyboardDidPresent() {
        updateBottomBarPosition()
        updateContentInsets(animated: false)
    }

    public func inputAccessoryPlaceholderKeyboardIsDismissing(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        handleKeyboardStateChange(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    public func inputAccessoryPlaceholderKeyboardDidDismiss() {
        updateBottomBarPosition()
        updateContentInsets(animated: false)
    }

    public func inputAccessoryPlaceholderKeyboardIsDismissingInteractively() {
        updateBottomBarPosition()
    }

    func handleKeyboardStateChange(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        guard animationDuration > 0 else {
            updateBottomBarPosition()
            updateContentInsets(animated: false)
            return
        }

        UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            options: animationCurve.asAnimationOptions,
            animations: { [self] in
                self.updateBottomBarPosition()
                self.updateContentInsets(animated: true)
            }
        )
    }

    func updateBottomBarPosition() {
        guard isViewLoaded else {
            return
        }

        bottomBarBottomConstraint.constant = -inputAccessoryPlaceholder.keyboardOverlap

        // We always want to apply the new bottom bar position immediately,
        // as this only happens during animations (interactive or otherwise)
        bottomBar.superview?.layoutIfNeeded()
    }

    func updateBottomBarContents() {
        // Fetch the latest copy of the thread
        thread = databaseStorage.read { storyMessage.context.thread(transaction: $0) }

        guard let groupThread = thread as? TSGroupThread else {
            bottomBar.removeAllSubviews()
            return owsFailDebug("Unexpectedly missing group thread")
        }

        if groupThread.canSendChatMessagesToThread() {
            switch bottomBarMode {
            case .member:
                // Nothing to do, we're already in the right state
                break
            case .nonMember, .blockedByAnnouncementOnly, .none:
                bottomBar.removeAllSubviews()
                bottomBar.addSubview(inputToolbar)
                inputToolbar.autoPinEdgesToSuperviewEdges()
            }

            bottomBarMode = .member
        } else if groupThread.isBlockedByAnnouncementOnly {
            switch bottomBarMode {
            case .blockedByAnnouncementOnly:
                // Nothing to do, we're already in the right state
                break
            case .member, .nonMember, .none:
                bottomBar.removeAllSubviews()

                let view = BlockingAnnouncementOnlyView(thread: groupThread, fromViewController: self, forceDarkMode: true)
                bottomBar.addSubview(view)
                view.autoPinWidthToSuperview()
                view.autoPinEdge(toSuperviewEdge: .top, withInset: 8)
                view.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 8)
            }

            bottomBarMode = .blockedByAnnouncementOnly
        } else {
            switch bottomBarMode {
            case .nonMember:
                // Nothing to do, we're already in the right state
                break
            case .member, .blockedByAnnouncementOnly, .none:
                bottomBar.removeAllSubviews()

                let label = UILabel()
                label.font = .dynamicTypeSubheadline
                label.text = OWSLocalizedString(
                    "STORIES_GROUP_REPLY_NOT_A_MEMBER",
                    comment: "Text indicating you can't reply to a group story because you're not a member of the group"
                )
                label.textColor = .ows_gray05
                label.textAlignment = .center
                label.numberOfLines = 0
                label.alpha = 0.7
                label.setContentHuggingVerticalHigh()

                bottomBar.addSubview(label)
                label.autoPinWidthToSuperview(withMargin: 37)
                label.autoPinEdge(toSuperviewEdge: .top, withInset: 8)
                label.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 8)
            }

            bottomBarMode = .nonMember
        }

        updateBottomBarPosition()
    }

    func updateContentInsets(animated: Bool) {
        let wasScrolledToBottom = replyLoader?.isScrolledToBottom ?? false
        tableView.contentInset.bottom = inputAccessoryPlaceholder.keyboardOverlap + bottomBar.height - view.safeAreaInsets.bottom
        if wasScrolledToBottom {
            replyLoader?.scrollToBottomOfLoadWindow(animated: animated)
        }
    }
}

extension StoryGroupReplyViewController: StoryReplyInputToolbarDelegate {
    func storyReplyInputToolbarDidBeginEditing(_ storyReplyInputToolbar: StoryReplyInputToolbar) {
        delegate?.storyGroupReplyViewControllerDidBeginEditing(self)
    }

    func storyReplyInputToolbarHeightDidChange(_ storyReplyInputToolbar: StoryReplyInputToolbar) {
        updateContentInsets(animated: false)
    }
}

extension StoryGroupReplyViewController: ContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: ContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> ContextMenuConfiguration? {
        guard let indexPath = tableView.indexPathForRow(at: location),
              let item = replyLoader?.replyItem(for: indexPath) else { return nil }

        return .init(identifier: indexPath as NSCopying, forceDarkTheme: true) { _ in

            var actions = [ContextMenuAction]()

            if !item.cellType.isReaction {
                actions.append(.init(
                    title: OWSLocalizedString(
                        "STORIES_COPY_REPLY_ACTION",
                        comment: "Context menu action to copy the selected story reply"),
                    image: Theme.iconImage(.messageActionCopy, isDarkThemeEnabled: true),
                    handler: { _ in
                        guard let displayableText = item.displayableText else { return }
                        MentionTextView.copyAttributedStringToPasteboard(displayableText.fullAttributedText)
                    }))
            }

            actions.append(.init(
                title: OWSLocalizedString(
                    "STORIES_DELETE_REPLY_ACTION",
                    comment: "Context menu action to delete the selected story reply"),
                image: Theme.iconImage(.messageActionDelete, isDarkThemeEnabled: true),
                attributes: .destructive,
                handler: { [weak self] _ in
                    guard let self = self else { return }
                    guard let message = Self.databaseStorage.read(
                        block: { TSMessage.anyFetchMessage(uniqueId: item.interactionUniqueId, transaction: $0) }
                    ) else { return }
                    message.presentDeletionActionSheet(from: self, forceDarkTheme: true)
                }))

            return .init(actions)
        }
    }

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: ContextMenuConfiguration) -> ContextMenuTargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath else { return nil }

        guard let cell = tableView.cellForRow(at: indexPath) else { return nil }

        let targetedPreview = ContextMenuTargetedPreview(
            view: cell,
            alignment: .leading,
            accessoryViews: nil
        )
        targetedPreview?.alignmentOffset = CGPoint(x: 52, y: 12)

        return targetedPreview
    }

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, willDisplayMenuForConfiguration: ContextMenuConfiguration) {}

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, willEndForConfiguration: ContextMenuConfiguration) {}

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, didEndForConfiguration configuration: ContextMenuConfiguration) {}
}

extension StoryGroupReplyViewController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard let thread = thread, databaseChanges.didUpdate(thread: thread) else { return }
        updateBottomBarContents()
    }

    func databaseChangesDidUpdateExternally() {
        updateBottomBarContents()
    }

    func databaseChangesDidReset() {
        updateBottomBarContents()
    }
}
