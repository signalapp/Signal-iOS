//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalServiceKit

class StoryGroupReplySheet: InteractiveSheetViewController {
    override var renderExternalHandle: Bool { false }
    override var interactiveScrollViews: [UIScrollView] { [tableView] }
    override var minHeight: CGFloat { CurrentAppContext().frame.height * 0.6 }

    private lazy var tableView = UITableView()
    private lazy var inputToolbar = StoryReplyInputToolbar()
    private lazy var inputToolbarBottomConstraint = inputToolbar.autoPinEdge(toSuperviewEdge: .bottom)
    private lazy var contextMenu = ContextMenuInteraction(delegate: self)

    private lazy var inputAccessoryPlaceholder: InputAccessoryViewPlaceholder = {
        let placeholder = InputAccessoryViewPlaceholder()
        placeholder.delegate = self
        placeholder.referenceView = view
        return placeholder
    }()

    private let storyMessage: StoryMessage
    private let thread: TSThread?

    fileprivate var reactionPickerBackdrop: UIView?
    fileprivate var reactionPicker: MessageReactionPicker?

    var dismissHandler: (() -> Void)?

    init(storyMessage: StoryMessage) {
        self.storyMessage = storyMessage
        self.thread = Self.databaseStorage.read { transaction in
            if let groupId = storyMessage.groupId {
                return TSGroupThread.fetch(groupId: groupId, transaction: transaction)
            } else {
                owsFailDebug("Unexpectedly received non-group thread for story reply sheet.")
                return TSContactThread.getWithContactAddress(storyMessage.authorAddress, transaction: transaction)
            }
        }

        super.init()

        // Fetch profiles for everyone in the group to make sure we have the latest capability state
        if let thread = thread {
            bulkProfileFetch.fetchProfiles(addresses: thread.recipientAddresses)
        }
    }

    public required init() {
        notImplemented()
    }

    fileprivate var replyLoader: StoryGroupReplyLoader?
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.keyboardDismissMode = .interactive
        tableView.addInteraction(contextMenu)

        contentView.addSubview(tableView)
        tableView.autoPinWidthToSuperview()
        tableView.autoPinEdge(toSuperviewEdge: .bottom)

        // We add the handle directly to the content view,
        // so that it doesn't scroll with the table.
        let handleContainer = UIView()
        contentView.addSubview(handleContainer)
        handleContainer.autoPinWidthToSuperview()
        handleContainer.autoPinEdge(toSuperviewEdge: .top)
        handleContainer.autoPinEdge(.bottom, to: .top, of: tableView)

        let handle = UIView()
        handle.backgroundColor = .ows_gray65
        handle.autoSetDimensions(to: CGSize(width: 36, height: 5))
        handle.layer.cornerRadius = 5 / 2
        handleContainer.addSubview(handle)
        handle.autoPinHeightToSuperview(withMargin: 12)
        handle.autoHCenterInSuperview()

        inputToolbar.delegate = self
        contentView.addSubview(inputToolbar)
        inputToolbar.autoPinWidthToSuperview()
        inputToolbarBottomConstraint.isActive = true

        contentView.backgroundColor = .ows_gray90
        tableView.backgroundColor = .ows_gray90
        handleContainer.backgroundColor = .ows_gray90

        for type in StoryGroupReplyCell.CellType.allCases {
            tableView.register(StoryGroupReplyCell.self, forCellReuseIdentifier: type.rawValue)
        }

        replyLoader = StoryGroupReplyLoader(storyMessage: storyMessage, threadUniqueId: thread?.uniqueId, tableView: tableView)
    }

    public override var canBecomeFirstResponder: Bool { true }

    public override var inputAccessoryView: UIView? { inputAccessoryPlaceholder }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { [dismissHandler] in
            completion?()
            dismissHandler?()
        }
    }

    fileprivate func tryToSendMessage(_ message: TSOutgoingMessage) {
        guard let thread = thread else {
            return owsFailDebug("Unexpectedly missing thread")
        }
        let isThreadBlocked = databaseStorage.read { blockingManager.isThreadBlocked(thread, transaction: $0) }

        guard !isThreadBlocked else {
            BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self) { [weak self] isBlocked in
                guard !isBlocked else { return }
                self?.tryToSendMessage(message)
            }
            return
        }

        guard !SafetyNumberConfirmationSheet.presentIfNecessary(
            addresses: thread.recipientAddresses,
            confirmationText: SafetyNumberStrings.confirmSendButton,
            completion: { [weak self] didConfirmIdentity in
                guard didConfirmIdentity else { return }
                self?.tryToSendMessage(message)
            }
        ) else { return }

        ThreadUtil.enqueueSendAsyncWrite { [weak self] transaction in
            ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(thread: thread, setDefaultTimerIfNecessary: false, transaction: transaction)

            message.anyInsert(transaction: transaction)

            Self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)

            transaction.addAsyncCompletionOnMain {
                self?.replyLoader?.reload()
                self?.inputToolbar.messageBody = nil
            }
        }
    }

    func tryToSendReaction(_ reaction: String) {
        owsAssertDebug(reaction.isSingleEmoji)

        guard let thread = thread else {
            return owsFailDebug("Unexpectedly missing thread")
        }

        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.storyReactionEmoji = reaction
        builder.storyTimestamp = NSNumber(value: storyMessage.timestamp)
        builder.storyAuthorAddress = storyMessage.authorAddress

        tryToSendMessage(builder.build())
    }
}

extension StoryGroupReplySheet: UIScrollViewDelegate {
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

extension StoryGroupReplySheet: UITableViewDelegate {

}

extension StoryGroupReplySheet: UITableViewDataSource {
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
        replyLoader?.numberOfRows ?? 0
    }
}

extension StoryGroupReplySheet: InputAccessoryViewPlaceholderDelegate {
    public func inputAccessoryPlaceholderKeyboardIsPresenting(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        handleKeyboardStateChange(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    public func inputAccessoryPlaceholderKeyboardDidPresent() {
        updateInputToolbarPosition()
        updateContentInsets(animated: false)
    }

    public func inputAccessoryPlaceholderKeyboardIsDismissing(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        handleKeyboardStateChange(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    public func inputAccessoryPlaceholderKeyboardDidDismiss() {
        updateInputToolbarPosition()
        updateContentInsets(animated: false)
    }

    public func inputAccessoryPlaceholderKeyboardIsDismissingInteractively() {
        updateInputToolbarPosition()
    }

    func handleKeyboardStateChange(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        guard animationDuration > 0 else {
            updateInputToolbarPosition()
            updateContentInsets(animated: false)
            return
        }

        UIView.beginAnimations("keyboardStateChange", context: nil)
        UIView.setAnimationBeginsFromCurrentState(true)
        UIView.setAnimationCurve(animationCurve)
        UIView.setAnimationDuration(animationDuration)
        updateInputToolbarPosition()
        updateContentInsets(animated: true)
        UIView.commitAnimations()
    }

    func updateInputToolbarPosition() {
        inputToolbarBottomConstraint.constant = -inputAccessoryPlaceholder.keyboardOverlap

        // We always want to apply the new bottom bar position immediately,
        // as this only happens during animations (interactive or otherwise)
        inputToolbar.superview?.layoutIfNeeded()
    }

    func updateContentInsets(animated: Bool) {
        let wasScrolledToBottom = replyLoader?.isScrolledToBottom ?? false
        tableView.contentInset.bottom = inputAccessoryPlaceholder.keyboardOverlap + inputToolbar.height - view.safeAreaInsets.bottom
        if wasScrolledToBottom {
            replyLoader?.scrollToBottomOfLoadWindow(animated: animated)
        }
    }
}

extension StoryGroupReplySheet: StoryReplyInputToolbarDelegate {
    func storyReplyInputToolbarDidTapReact(_ storyReplyInputToolbar: StoryReplyInputToolbar) {
        presentReactionPicker()
    }

    func storyReplyInputToolbarDidTapSend(_ storyReplyInputToolbar: StoryReplyInputToolbar) {
        guard let messageBody = storyReplyInputToolbar.messageBody, !messageBody.text.isEmpty else {
            return owsFailDebug("Unexpectedly missing message body")
        }

        guard let thread = thread else {
            return owsFailDebug("Unexpectedly missing thread")
        }

        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.messageBody = messageBody.text
        builder.bodyRanges = messageBody.ranges
        builder.storyTimestamp = NSNumber(value: storyMessage.timestamp)
        builder.storyAuthorAddress = storyMessage.authorAddress

        tryToSendMessage(builder.build())
    }

    func storyReplyInputToolbarDidBeginEditing(_ storyReplyInputToolbar: StoryReplyInputToolbar) {
        maximizeHeight()
    }

    func storyReplyInputToolbarHeightDidChange(_ storyReplyInputToolbar: StoryReplyInputToolbar) {
        updateContentInsets(animated: false)
    }

    func storyReplyInputToolbarMentionPickerPossibleAddresses(_ storyReplyInputToolbar: StoryReplyInputToolbar) -> [SignalServiceAddress] {
        return thread?.recipientAddresses ?? []
    }
}

extension StoryGroupReplySheet: MessageReactionPickerDelegate {
    func didSelectReaction(reaction: String, isRemoving: Bool, inPosition position: Int) {
        dismissReactionPicker()

        tryToSendReaction(reaction)
    }

    func didSelectAnyEmoji() {
        dismissReactionPicker()

        let sheet = EmojiPickerSheet { [weak self] selectedEmoji in
            guard let selectedEmoji = selectedEmoji else { return }
            self?.tryToSendReaction(selectedEmoji.rawValue)
        }
        present(sheet, animated: true)
    }

    @objc
    func didTapReactionPickerBackdrop() {
        dismissReactionPicker()
    }

    func presentReactionPicker() {
        guard self.reactionPicker == nil else { return }

        let backdrop = UIView()
        backdrop.backgroundColor = .ows_blackAlpha40
        view.addSubview(backdrop)
        backdrop.autoPinEdgesToSuperviewEdges()
        backdrop.alpha = 0
        self.reactionPickerBackdrop = backdrop

        let backdropTapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapReactionPickerBackdrop))
        backdrop.addGestureRecognizer(backdropTapGesture)
        backdrop.isUserInteractionEnabled = true

        let reactionPicker = MessageReactionPicker(selectedEmoji: nil, delegate: self, forceDarkTheme: true)

        view.addSubview(reactionPicker)
        reactionPicker.autoPinEdge(.bottom, to: .top, of: inputToolbar, withOffset: -15)
        reactionPicker.autoPinEdge(toSuperviewEdge: .trailing, withInset: 12)

        reactionPicker.playPresentationAnimation(duration: 0.2)

        UIView.animate(withDuration: 0.2) { backdrop.alpha = 1 }

        self.reactionPicker = reactionPicker
    }

    func dismissReactionPicker() {
        UIView.animate(withDuration: 0.2) {
            self.reactionPickerBackdrop?.alpha = 0
        } completion: { _ in
            self.reactionPickerBackdrop?.removeFromSuperview()
            self.reactionPickerBackdrop = nil
        }

        reactionPicker?.playDismissalAnimation(duration: 0.2) {
            self.reactionPicker?.removeFromSuperview()
            self.reactionPicker = nil
        }
    }
}

extension StoryGroupReplySheet: ContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: ContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> ContextMenuConfiguration? {
        guard let indexPath = tableView.indexPathForRow(at: location),
              let item = replyLoader?.replyItem(for: indexPath) else { return nil }

        return .init(identifier: indexPath as NSCopying, forceDarkTheme: true) { _ in

            var actions = [ContextMenuAction]()

            actions.append(.init(
                title: NSLocalizedString(
                    "STORIES_PRIVATE_REPLY_ACTION",
                    comment: "Context menu action to privately reply to the selected story reply"),
                image: Theme.iconImage(.messageActionReply, isDarkThemeEnabled: true),
                handler: { _ in
                    OWSActionSheets.showActionSheet(title: LocalizationNotNeeded("Private replies are not yet implemented."))
                }))

            if item.cellType != .reaction {
                actions.append(.init(
                    title: NSLocalizedString(
                        "STORIES_COPY_REPLY_ACTION",
                        comment: "Context menu action to copy the selected story reply"),
                    image: Theme.iconImage(.messageActionCopy, isDarkThemeEnabled: true),
                    handler: { _ in
                        guard let displayableText = item.displayableText else { return }
                        MentionTextView.copyAttributedStringToPasteboard(displayableText.fullAttributedText)
                    }))
            }

            actions.append(.init(
                title: NSLocalizedString(
                    "STORIES_DELETE_REPLY_ACTION",
                    comment: "Context menu action to delete the selected story reply"),
                image: Theme.iconImage(.messageActionDelete, isDarkThemeEnabled: true),
                attributes: .destructive,
                handler: { [weak self] _ in
                    guard let self = self else { return }
                    guard let message = Self.databaseStorage.read(
                        block: { TSMessage.anyFetchMessage(uniqueId: item.interactionUniqueId, transaction: $0) }
                    ) else { return }
                    message.presentDeletionActionSheet(from: self)
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
