//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol StoryGroupReplyDelegate: AnyObject {
    func storyGroupReplyViewControllerDidBeginEditing(_ storyGroupReplyViewController: StoryGroupReplyViewController)
}

class StoryGroupReplyViewController: OWSViewController, StoryReplySheet {
    weak var delegate: StoryGroupReplyDelegate?

    private(set) lazy var tableView = UITableView()

    private let spoilerState: SpoilerRenderState
    let stickerImageCache = StickerReactionImageCache()

    let bottomBar = UIView()
    private(set) lazy var inputToolbar = StoryReplyInputToolbar(isGroupStory: true, spoilerState: spoilerState)
    private lazy var contextMenu = ContextMenuInteraction(delegate: self)

    private enum BottomBarMode {
        case member
        case nonMember
        case blockedByAnnouncementOnly
    }

    private var bottomBarMode: BottomBarMode?

    private lazy var emptyStateView: UIView = {
        let label = UILabel()
        label.textColor = .ows_gray45
        label.textAlignment = .center
        label.numberOfLines = 2
        label.attributedText = NSAttributedString(
            string: OWSLocalizedString("STORIES_NO_REPLIES_YET", comment: "Indicates that this story has no replies yet"),
            attributes: [NSAttributedString.Key.font: UIFont.dynamicTypeHeadline],
        ).stringByAppendingString(
            "\n",
        ).stringByAppendingString(
            OWSLocalizedString("STORIES_NO_REPLIES_SUBTITLE", comment: "The subtitle when this story has no replies"),
            attributes: [NSAttributedString.Key.font: UIFont.dynamicTypeSubheadline],
        )
        label.isHidden = true
        label.isUserInteractionEnabled = false
        return label
    }()

    let storyMessage: StoryMessage
    lazy var thread: TSThread? = SSKEnvironment.shared.databaseStorageRef.read { storyMessage.context.thread(transaction: $0) }

    init(storyMessage: StoryMessage, spoilerState: SpoilerRenderState) {
        self.storyMessage = storyMessage
        self.spoilerState = spoilerState

        super.init()

        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(attachmentDownloadProgress(_:)),
            name: AttachmentDownloads.attachmentDownloadProgressNotification,
            object: nil,
        )
    }

    @objc
    private func attachmentDownloadProgress(_ notification: Notification) {
        guard
            let attachmentId = notification
                .userInfo?[AttachmentDownloads.attachmentDownloadAttachmentIDKey]
                as? Attachment.IDType,
            replyLoader?.attachmentIds.contains(attachmentId) == true,
            let progress = notification
                .userInfo?[AttachmentDownloads.attachmentDownloadProgressKey]
                as? NSNumber,
            progress.floatValue >= 1.0
        else { return }
        replyLoader?.reload()
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
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        inputToolbar.delegate = self
        view.addSubview(bottomBar)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bottomBar.topAnchor.constraint(equalTo: tableView.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])
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
    }

    func updateBottomBarContents() {
        // Fetch the latest copy of the thread
        thread = SSKEnvironment.shared.databaseStorageRef.read { storyMessage.context.thread(transaction: $0) }

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
                    comment: "Text indicating you can't reply to a group story because you're not a member of the group",
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
    }

    func didSendMessage() {
        replyLoader?.reload()
        inputToolbar.setMessageBody(nil, txProvider: DependenciesBridge.shared.db.readTxProvider)
    }
}

extension StoryGroupReplyViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard
            let visibleRows = tableView.indexPathsForVisibleRows?.map({ $0.row }),
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

        askToResendMessage(for: item)
    }

    private func askToResendMessage(for item: StoryGroupReplyViewItem) {
        let message = SSKEnvironment.shared.databaseStorageRef.read { tx in
            TSOutgoingMessage.fetchOutgoingMessageViaCache(uniqueId: item.interactionUniqueId, transaction: tx)
        }
        guard let message else {
            return
        }
        let promptBuilder = ResendMessagePromptBuilder(
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            messageSenderJobQueue: SSKEnvironment.shared.messageSenderJobQueueRef,
        )

        var allowRetrySend = true
        if let groupThread = thread as? TSGroupThread {
            allowRetrySend = !groupThread.isTerminatedGroup
        }

        self.present(promptBuilder.build(for: message, allowRetrySend: allowRetrySend), animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let cell = cell as? StoryGroupReplyCell else {
            return
        }
        cell.setIsCellVisible(true)
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let cell = cell as? StoryGroupReplyCell else {
            return
        }
        cell.setIsCellVisible(false)
    }
}

extension StoryGroupReplyViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let item = replyLoader?.replyItem(for: indexPath) else {
            owsFailDebug("Missing item for cell at indexPath \(indexPath)")
            return UITableViewCell()
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: item.cellType.rawValue, for: indexPath) as! StoryGroupReplyCell
        cell.cellDelegate = self
        cell.configure(with: item, spoilerState: spoilerState, stickerImageCache: stickerImageCache)

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

extension StoryGroupReplyViewController: StoryGroupReplyCellDelegate {
    func storyGroupReplyCellDidTapStickerPack(_ cell: StoryGroupReplyCell, stickerPackInfo: StickerPackInfo) {
        let packView = StickerPackViewController(stickerPackInfo: stickerPackInfo)
        packView.present(from: self, animated: true)
    }

    func storyGroupReplyCellDidTapDownloadSticker(_ cell: StoryGroupReplyCell) {
        guard
            let indexPath = tableView.indexPath(for: cell),
            let item = replyLoader?.replyItem(for: indexPath)
        else { return }

        SSKEnvironment.shared.databaseStorageRef.write { tx in
            guard let message = TSMessage.fetchMessageViaCache(uniqueId: item.interactionUniqueId, transaction: tx) else {
                return
            }
            DependenciesBridge.shared.attachmentDownloadManager.enqueueDownloadOfAttachmentsForMessage(
                message,
                priority: .userInitiated,
                tx: tx,
            )
        }
    }
}

extension StoryGroupReplyViewController: StoryReplyInputToolbarDelegate {
    func storyReplyInputToolbarDidBeginEditing(_ storyReplyInputToolbar: StoryReplyInputToolbar) {
        delegate?.storyGroupReplyViewControllerDidBeginEditing(self)
    }
}

extension StoryGroupReplyViewController: ContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: ContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> ContextMenuConfiguration? {
        guard
            let indexPath = tableView.indexPathForRow(at: location),
            let item = replyLoader?.replyItem(for: indexPath) else { return nil }

        return .init(identifier: indexPath as NSCopying, forceDarkTheme: true) { _ in

            var actions = [ContextMenuAction]()

            if !item.cellType.isReaction {
                actions.append(.init(
                    title: OWSLocalizedString(
                        "STORIES_COPY_REPLY_ACTION",
                        comment: "Context menu action to copy the selected story reply",
                    ),
                    image: Theme.iconImage(.contextMenuCopy, isDarkThemeEnabled: true),
                    handler: { _ in
                        guard let displayableText = item.displayableText else { return }
                        BodyRangesTextView.copyToPasteboard(displayableText.fullTextValue)
                    },
                ))
            }

            actions.append(.init(
                title: OWSLocalizedString(
                    "STORIES_DELETE_REPLY_ACTION",
                    comment: "Context menu action to delete the selected story reply",
                ),
                image: Theme.iconImage(.contextMenuDelete, isDarkThemeEnabled: true),
                attributes: .destructive,
                handler: { [weak self] _ in
                    guard let self else { return }
                    guard
                        let message = SSKEnvironment.shared.databaseStorageRef.read(
                            block: { TSMessage.fetchMessageViaCache(uniqueId: item.interactionUniqueId, transaction: $0) },
                        ) else { return }
                    message.presentDeletionActionSheet(from: self, forceDarkTheme: true)
                },
            ))

            return .init(actions)
        }
    }

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: ContextMenuConfiguration) -> ContextMenuTargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath else { return nil }

        guard let cell = tableView.cellForRow(at: indexPath) else { return nil }

        let targetedPreview = ContextMenuTargetedPreview(
            view: cell,
            alignment: CurrentAppContext().isRTL ? .right : .left,
            accessoryViews: nil,
        )
        targetedPreview?.alignmentOffset = CGPoint(x: -52, y: 12)

        return targetedPreview
    }

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, willDisplayMenuForConfiguration: ContextMenuConfiguration) {}

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, willEndForConfiguration: ContextMenuConfiguration) {}

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, didEndForConfiguration configuration: ContextMenuConfiguration) {}
}

extension StoryGroupReplyViewController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard let thread, databaseChanges.didUpdate(thread: thread) else { return }
        updateBottomBarContents()
    }

    func databaseChangesDidUpdateExternally() {
        updateBottomBarContents()
    }

    func databaseChangesDidReset() {
        updateBottomBarContents()
    }
}
