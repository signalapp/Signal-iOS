//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import UIKit
import SignalUI

class StoriesViewController: OWSViewController {
    let tableView = UITableView()
    private var presentedContextOrder: [StoryContext]?
    private var models = [IncomingStoryViewModel]()

    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.secondaryTextAndIconColor
        label.font = .ows_dynamicTypeBody
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = NSLocalizedString("STORIES_NO_RECENT_MESSAGES", comment: "Indicates that there are no recent stories to render")
        label.isHidden = true
        label.isUserInteractionEnabled = false
        tableView.backgroundView = label
        return label
    }()

    private lazy var contextMenu = ContextMenuInteraction(delegate: self)

    override init() {
        super.init()
        reloadStories()
        databaseStorage.appendDatabaseChangeDelegate(self)

        NotificationCenter.default.addObserver(self, selector: #selector(profileDidChange), name: .localProfileDidChange, object: nil)
    }

    override func loadView() {
        view = tableView
        tableView.delegate = self
        tableView.dataSource = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("STORIES_TITLE", comment: "Title for the stories view.")

        tableView.register(StoryCell.self, forCellReuseIdentifier: StoryCell.reuseIdentifier)
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 116

        updateNavigationBar()

        tableView.addInteraction(contextMenu)
    }

    private var timestampUpdateTimer: Timer?
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        timestampUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            AssertIsOnMainThread()

            for indexPath in self.tableView.indexPathsForVisibleRows ?? [] {
                guard let cell = self.tableView.cellForRow(at: indexPath) as? StoryCell else { continue }
                guard let model = self.model(for: indexPath) else { continue }
                cell.configureTimestamp(with: model)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Whether or not the theme has changed, always ensure
        // the right theme is applied. The initial collapsed
        // state of the split view controller is determined between
        // `viewWillAppear` and `viewDidAppear`, so this is the soonest
        // we can know the right thing to display.
        applyTheme()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        // We could be changing between collapsed and expanded
        // split view state, so we must re-apply the theme.
        coordinator.animate { _ in
            self.applyTheme()
        } completion: { _ in
            self.applyTheme()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        timestampUpdateTimer?.invalidate()
        timestampUpdateTimer = nil
    }

    override func applyTheme() {
        super.applyTheme()

        emptyStateLabel.textColor = Theme.secondaryTextAndIconColor

        contextMenu.dismissMenu(animated: true) {}

        for indexPath in self.tableView.indexPathsForVisibleRows ?? [] {
            guard let cell = self.tableView.cellForRow(at: indexPath) as? StoryCell else { continue }
            guard let model = self.model(for: indexPath) else { continue }
            cell.configure(with: model)
        }

        if splitViewController?.isCollapsed == true {
            view.backgroundColor = Theme.backgroundColor
            tableView.backgroundColor = Theme.backgroundColor
        } else {
            view.backgroundColor = Theme.secondaryBackgroundColor
            tableView.backgroundColor = Theme.secondaryBackgroundColor
        }

        updateNavigationBar()
    }

    @objc
    func profileDidChange() { updateNavigationBar() }

    private func updateNavigationBar() {
        let avatarButton = UIButton(type: .custom)
        avatarButton.accessibilityLabel = CommonStrings.openSettingsButton
        avatarButton.addTarget(self, action: #selector(showAppSettings), for: .touchUpInside)

        let avatarView = ConversationAvatarView(sizeClass: .twentyEight, localUserDisplayMode: .asUser)
        databaseStorage.read { transaction in
            avatarView.update(transaction) { config in
                if let address = tsAccountManager.localAddress(with: transaction) {
                    config.dataSource = .address(address)
                    config.applyConfigurationSynchronously()
                }
            }
        }

        avatarButton.addSubview(avatarView)
        avatarView.autoPinEdgesToSuperviewEdges()

        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: avatarButton)

        let cameraButton = UIBarButtonItem(image: Theme.iconImage(.cameraButton), style: .plain, target: self, action: #selector(showCameraView))
        cameraButton.accessibilityLabel = NSLocalizedString("CAMERA_BUTTON_LABEL", comment: "Accessibility label for camera button.")
        cameraButton.accessibilityHint = NSLocalizedString("CAMERA_BUTTON_HINT", comment: "Accessibility hint describing what you can do with the camera button")

        navigationItem.rightBarButtonItems = [cameraButton]
    }

    @objc
    func showCameraView() {
        AssertIsOnMainThread()

        // Dismiss any message actions if they're presented
        conversationSplitViewController?.selectedConversationViewController?.dismissMessageContextMenu(animated: true)

        ows_askForCameraPermissions { cameraGranted in
            guard cameraGranted else {
                return Logger.warn("camera permission denied.")
            }
            self.ows_askForMicrophonePermissions { micGranted in
                if !micGranted {
                    // We can still continue without mic permissions, but any captured video will
                    // be silent.
                    Logger.warn("proceeding, though mic permission denied.")
                }

                let modal = CameraFirstCaptureNavigationController.cameraFirstModal()
                modal.cameraFirstCaptureSendFlow.delegate = self
                self.presentFullScreen(modal, animated: true)
            }
        }
    }

    @objc
    func showAppSettings() {
        AssertIsOnMainThread()

        conversationSplitViewController?.selectedConversationViewController?.dismissMessageContextMenu(animated: true)
        presentFormSheet(AppSettingsViewController.inModalNavigationController(), animated: true)
    }

    private static let loadingQueue = DispatchQueue(label: "StoriesViewController.loadingQueue", qos: .userInitiated)
    private func reloadStories() {
        Self.loadingQueue.async {
            let incomingMessages = Self.databaseStorage.read { StoryFinder.incomingStories(transaction: $0) }
            let groupedMessages = Dictionary(grouping: incomingMessages) { $0.context }
            let newModels = Self.databaseStorage.read { transaction in
                groupedMessages.compactMap { try? IncomingStoryViewModel(messages: $1, transaction: transaction) }
            }.sorted(by: self.sortStoryModels)
            DispatchQueue.main.async {
                self.models = newModels
                self.tableView.reloadData()
            }
        }
    }

    private func updateStories(forRowIds rowIds: Set<Int64>) {
        guard !rowIds.isEmpty else { return }
        Self.loadingQueue.async {
            let updatedMessages = Self.databaseStorage.read {
                StoryFinder.incomingStoriesWithRowIds(Array(rowIds), transaction: $0)
            }
            var deletedRowIds = rowIds.subtracting(updatedMessages.map { $0.id! })
            var groupedMessages = Dictionary(grouping: updatedMessages) { $0.context }

            let oldContexts = self.models.map { $0.context }
            var changedContexts = [StoryContext]()

            let newModels: [IncomingStoryViewModel]
            do {
                newModels = try Self.databaseStorage.read { transaction in
                    try self.models.compactMap { model in
                        guard let latestMessage = model.messages.first else { return model }

                        let modelDeletedRowIds: [Int64] = model.messages.lazy.compactMap { $0.id }.filter { deletedRowIds.contains($0) }
                        deletedRowIds.subtract(modelDeletedRowIds)

                        let modelUpdatedMessages = groupedMessages.removeValue(forKey: latestMessage.context) ?? []

                        guard !modelUpdatedMessages.isEmpty || !modelDeletedRowIds.isEmpty else { return model }

                        changedContexts.append(model.context)

                        return try model.copy(
                            updatedMessages: modelUpdatedMessages,
                            deletedMessageRowIds: modelDeletedRowIds,
                            transaction: transaction
                        )
                    } + groupedMessages.map { try IncomingStoryViewModel(messages: $1, transaction: transaction) }
                }.sorted(by: self.sortStoryModels)
            } catch {
                owsFailDebug("Failed to build new models, hard reloading \(error)")
                DispatchQueue.main.async { self.reloadStories() }
                return
            }

            let batchUpdateItems: [BatchUpdate<StoryContext>.Item]
            do {
                batchUpdateItems = try BatchUpdate.build(
                    viewType: .uiTableView,
                    oldValues: oldContexts,
                    newValues: newModels.map { $0.context },
                    changedValues: changedContexts
                )
            } catch {
                owsFailDebug("Failed to calculate batch updates, hard reloading \(error)")
                DispatchQueue.main.async { self.reloadStories() }
                return
            }

            DispatchQueue.main.async {
                self.models = newModels
                guard self.isViewLoaded else { return }
                self.tableView.beginUpdates()
                for update in batchUpdateItems {
                    switch update.updateType {
                    case .delete(let oldIndex):
                        self.tableView.deleteRows(at: [IndexPath(row: oldIndex, section: 0)], with: .automatic)
                    case .insert(let newIndex):
                        self.tableView.insertRows(at: [IndexPath(row: newIndex, section: 0)], with: .automatic)
                    case .move(let oldIndex, let newIndex):
                        self.tableView.deleteRows(at: [IndexPath(row: oldIndex, section: 0)], with: .automatic)
                        self.tableView.insertRows(at: [IndexPath(row: newIndex, section: 0)], with: .automatic)
                    case .update(_, let newIndex):
                        // If the cell is visible, reconfigure it directly without reloading.
                        let path = IndexPath(row: newIndex, section: 0)
                        if (self.tableView.indexPathsForVisibleRows ?? []).contains(path),
                            let visibleCell = self.tableView.cellForRow(at: path) as? StoryCell {
                            guard let model = self.models[safe: newIndex] else {
                                return owsFailDebug("Missing model for story")
                            }
                            visibleCell.configure(with: model)
                        } else {
                            self.tableView.reloadRows(at: [path], with: .none)
                        }
                    }
                }
                self.tableView.endUpdates()
            }
        }
    }

    // Sort story models for display.
    // * We show unviewed stories first, sorted by their sent timestamp, with the most recently sent at the top
    // * We then show viewed stories, sorted by when they were viewed, with the most recently viewed at the top
    private func sortStoryModels(lhs: IncomingStoryViewModel, rhs: IncomingStoryViewModel) -> Bool {
        if let lhsViewedTimestamp = lhs.latestMessageViewedTimestamp,
            let rhsViewedTimestamp = rhs.latestMessageViewedTimestamp {
            return lhsViewedTimestamp > rhsViewedTimestamp
        } else if lhs.latestMessageViewedTimestamp != nil {
            return false
        } else if rhs.latestMessageViewedTimestamp != nil {
            return true
        } else {
            return lhs.latestMessageTimestamp > rhs.latestMessageTimestamp
        }
    }
}

extension StoriesViewController: CameraFirstCaptureDelegate {
    func cameraFirstCaptureSendFlowDidComplete(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow) {
        dismiss(animated: true)
    }

    func cameraFirstCaptureSendFlowDidCancel(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow) {
        dismiss(animated: true)
    }
}

extension StoriesViewController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        updateStories(forRowIds: databaseChanges.storyMessageRowIds)
    }

    func databaseChangesDidUpdateExternally() {
        reloadStories()
    }

    func databaseChangesDidReset() {
        reloadStories()
    }
}

extension StoriesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let model = model(for: indexPath) else {
            owsFailDebug("Missing model for story")
            return
        }
        let vc = StoryPageViewController(context: model.context)
        vc.contextDataSource = self
        presentFullScreen(vc, animated: true)
    }
}

extension StoriesViewController: UITableViewDataSource {
    func model(for indexPath: IndexPath) -> IncomingStoryViewModel? {
        models[safe: indexPath.row]
    }

    func model(for context: StoryContext) -> IncomingStoryViewModel? {
        models.first { $0.context == context }
    }

    func cell(for context: StoryContext) -> StoryCell? {
        guard let row = models.firstIndex(where: { $0.context == context }) else { return nil }
        let indexPath = IndexPath(row: row, section: 0)
        guard tableView.indexPathsForVisibleRows?.contains(indexPath) == true else { return nil }
        return tableView.cellForRow(at: indexPath) as? StoryCell
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: StoryCell.reuseIdentifier) as! StoryCell
        guard let model = model(for: indexPath) else {
            owsFailDebug("Missing model for story")
            return cell
        }
        cell.configure(with: model)
        return cell
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let numberOfRows = models.count
        emptyStateLabel.isHidden = numberOfRows > 0
        return numberOfRows
    }
}

extension StoriesViewController: StoryPageViewControllerDataSource {
    func storyPageViewControllerAvailableContexts(_ storyPageViewController: StoryPageViewController) -> [StoryContext] {
        models.map { $0.context }
    }
}

extension StoriesViewController: ContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: ContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> ContextMenuConfiguration? {
        guard let indexPath = tableView.indexPathForRow(at: location),
                let model = model(for: indexPath) else { return nil }

        return .init(identifier: indexPath as NSCopying) { _ in

            var actions = [ContextMenuAction]()

            actions.append(.init(
                title: NSLocalizedString(
                    "STORIES_HIDE_STORY_ACTION",
                    comment: "Context menu action to hide the selected story"),
                image: Theme.iconImage(.xCircle24),
                handler: { _ in
                    OWSActionSheets.showActionSheet(title: LocalizationNotNeeded("Hiding stories is not yet implemented."))
                }))

            func appendForwardAction() {
                actions.append(.init(
                    title: NSLocalizedString(
                        "STORIES_FORWARD_STORY_ACTION",
                        comment: "Context menu action to forward the selected story"),
                    image: Theme.iconImage(.messageActionForward),
                    handler: { [weak self] _ in
                        guard let self = self else { return }
                        switch model.latestMessageAttachment {
                        case .file(let attachment):
                            ForwardMessageViewController.present([attachment], from: self, delegate: self)
                        case .text:
                            OWSActionSheets.showActionSheet(title: LocalizationNotNeeded("Forwarding text stories is not yet implemented."))
                        case .missing:
                            owsFailDebug("Unexpectedly missing attachment for story.")
                        }
                    }))
            }

            func appendShareAction() {
                actions.append(.init(
                    title: NSLocalizedString(
                        "STORIES_SHARE_STORY_ACTION",
                        comment: "Context menu action to share the selected story"),
                    image: Theme.iconImage(.messageActionShare),
                    handler: { [weak self] _ in
                        guard let self = self else { return }
                        guard let cell = self.tableView.cellForRow(at: indexPath) else { return }

                        switch model.latestMessageAttachment {
                        case .file(let attachment):
                            guard let attachment = attachment as? TSAttachmentStream else {
                                return owsFailDebug("Unexpectedly tried to share undownloaded attachment")
                            }
                            AttachmentSharing.showShareUI(forAttachment: attachment, sender: cell)
                        case .text(let attachment):
                            if let url = attachment.preview?.urlString {
                                AttachmentSharing.showShareUI(for: URL(string: url)!, sender: cell)
                            } else if let text = attachment.text {
                                AttachmentSharing.showShareUI(forText: text, sender: cell)
                            }
                        case .missing:
                            owsFailDebug("Unexpectedly missing attachment for story.")
                        }
                    }))
            }

            switch model.latestMessageAttachment {
            case .file(let attachment):
                guard attachment is TSAttachmentStream else { break }
                appendForwardAction()
                appendShareAction()
            case .text:
                appendForwardAction()
                appendShareAction()
            case .missing:
                owsFailDebug("Unexpectedly missing attachment for story.")
                break
            }

            actions.append(.init(
                title: NSLocalizedString(
                    "STORIES_GO_TO_CHAT_ACTION",
                    comment: "Context menu action to open the chat associated with the selected story"),
                image: Theme.iconImage(.open24),
                handler: { _ in
                    switch model.context {
                    case .groupId(let groupId):
                        guard let thread = Self.databaseStorage.read(block: { TSGroupThread.fetch(groupId: groupId, transaction: $0) }) else {
                            return owsFailDebug("Unexpectedly missing thread for group story")
                        }
                        Self.signalApp.presentConversation(for: thread, action: .compose, animated: true)
                    case .authorUuid(let authorUuid):
                        guard let thread = Self.databaseStorage.read(
                            block: { TSContactThread.getWithContactAddress(SignalServiceAddress(uuid: authorUuid), transaction: $0) }
                        ) else {
                            return owsFailDebug("Unexpectedly missing thread for 1:1 story")
                        }
                        Self.signalApp.presentConversation(for: thread, action: .compose, animated: true)
                    case .none:
                        owsFailDebug("Unexpectedly missing context for story")
                    }
                }))

            return .init(actions)
        }
    }

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: ContextMenuConfiguration) -> ContextMenuTargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath else { return nil }

        guard let cell = tableView.cellForRow(at: indexPath) as? StoryCell,
            let cellSnapshot = cell.contentHStackView.snapshotView(afterScreenUpdates: false) else { return nil }

        // Build a custom preview that wraps the cell contents in a bubble.
        // Normally, our context menus just present the cell row full width.

        let previewView = UIView()
        previewView.frame = cell.contentView
            .convert(cell.contentHStackView.frame, to: cell.superview)
            .insetBy(dx: -12, dy: -12)
        previewView.layer.cornerRadius = 18
        previewView.backgroundColor = Theme.backgroundColor
        previewView.clipsToBounds = true

        previewView.addSubview(cellSnapshot)
        cellSnapshot.frame.origin = CGPoint(x: 12, y: 12)

        let preview = ContextMenuTargetedPreview(
            view: cell,
            previewView: previewView,
            alignment: .leading,
            accessoryViews: []
        )
        preview.alignmentOffset = CGPoint(x: 12, y: 12)
        return preview
    }

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, willDisplayMenuForConfiguration: ContextMenuConfiguration) {}

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, willEndForConfiguration: ContextMenuConfiguration) {}

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, didEndForConfiguration configuration: ContextMenuConfiguration) {}
}

extension StoriesViewController: ForwardMessageDelegate {
    public func forwardMessageFlowDidComplete(items: [ForwardMessageItem],
                                              recipientThreads: [TSThread]) {
        AssertIsOnMainThread()

        self.dismiss(animated: true) {
            ForwardMessageViewController.finalizeForward(items: items,
                                                         recipientThreads: recipientThreads,
                                                         fromViewController: self)
        }
    }

    public func forwardMessageFlowDidCancel() {
        self.dismiss(animated: true)
    }
}
