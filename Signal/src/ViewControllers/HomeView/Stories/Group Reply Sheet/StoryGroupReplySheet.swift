//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalServiceKit

class StoryGroupReplySheet: InteractiveSheetViewController {
    override var renderExternalHandle: Bool { false }

    private lazy var tableView = UITableView()
    private lazy var inputToolbar = StoryReplyInputToolbar()
    private lazy var inputToolbarBottomConstraint = inputToolbar.autoPinEdge(toSuperviewEdge: .bottom)

    private lazy var inputAccessoryPlaceholder: InputAccessoryViewPlaceholder = {
        let placeholder = InputAccessoryViewPlaceholder()
        placeholder.delegate = self
        placeholder.referenceView = view
        return placeholder
    }()

    private let storyMessage: StoryMessage
    private let thread: TSThread?

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
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    fileprivate var replyLoader: StoryGroupReplyLoader?
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.keyboardDismissMode = .interactive
        tableView.contentInset = UIEdgeInsets(top: 30, left: 0, bottom: 0, right: 0)

        contentView.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        // We add the handle directly to the content view,
        // so that it doesn't scroll with the table.
        let handleContainer = UIView()
        contentView.addSubview(handleContainer)
        handleContainer.autoPinWidthToSuperview()
        handleContainer.autoPinEdge(toSuperviewEdge: .top)

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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        replyLoader?.scrollToBottomOfLoadWindow(animated: true)
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

    }

    func storyReplyInputToolbarDidTapSend(_ storyReplyInputToolbar: StoryReplyInputToolbar) {
        guard let messageBody = storyReplyInputToolbar.messageBody, !messageBody.text.isEmpty else {
            return owsFailDebug("Unexpectedly missing message body")
        }

        tryToSendTextMessage(messageBody)
    }

    func tryToSendTextMessage(_ messageBody: MessageBody) {
        owsAssertDebug(!messageBody.text.isEmpty)

        guard let thread = thread else {
            return owsFailDebug("Unexpectedly missing thread")
        }

        guard !blockingManager.isThreadBlocked(thread) else {
            BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self) { [weak self] isBlocked in
                guard !isBlocked else { return }
                self?.tryToSendTextMessage(messageBody)
            }
            return
        }

        guard !SafetyNumberConfirmationSheet.presentIfNecessary(
            addresses: thread.recipientAddresses,
            confirmationText: SafetyNumberStrings.confirmSendButton,
            completion: { [weak self] didConfirmIdentity in
                guard didConfirmIdentity else { return }
                self?.tryToSendTextMessage(messageBody)
            }
        ) else { return }

        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.messageBody = messageBody.text
        builder.bodyRanges = messageBody.ranges
        builder.storyTimestamp = NSNumber(value: storyMessage.timestamp)
        builder.storyAuthorAddress = storyMessage.authorAddress
        let message = builder.build()

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
