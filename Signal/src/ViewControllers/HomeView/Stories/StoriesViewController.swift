//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import UIKit
import SignalUI

private let loadingQueue = DispatchQueue(label: "StoriesViewController.loadingQueue", qos: .userInitiated)

class StoriesViewController: OWSViewController {
    let tableView = UITableView()
    private let syncingModels = SyncingStoryViewModelArray()
    private var myStoryModel = AtomicOptional<MyStoryViewModel>(nil)

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

        tableView.register(MyStoryCell.self, forCellReuseIdentifier: MyStoryCell.reuseIdentifier)
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
                switch Section(rawValue: indexPath.section) {
                case .myStory:
                    guard let cell = self.tableView.cellForRow(at: indexPath) as? MyStoryCell else { continue }
                    guard let model = self.myStoryModel.get() else { continue }
                    cell.configureTimestamp(with: model)
                case .visibleStories:
                    guard let cell = self.tableView.cellForRow(at: indexPath) as? StoryCell else { continue }
                    guard let model = self.model(for: indexPath) else { continue }
                    cell.configureTimestamp(with: model)
                case .hiddenStories:
                    // TODO:
                    break
                default:
                    owsFailDebug("Unexpected story type")
                }
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
            switch Section(rawValue: indexPath.section) {
            case .myStory:
                guard let cell = self.tableView.cellForRow(at: indexPath) as? MyStoryCell else { continue }
                guard let model = self.myStoryModel.get() else { continue }
                cell.configure(with: model) { [weak self] in self?.showCameraView() }
            case .visibleStories:
                guard let cell = self.tableView.cellForRow(at: indexPath) as? StoryCell else { continue }
                guard let model = self.model(for: indexPath) else { continue }
                cell.configure(with: model)
            case .hiddenStories:
                // TODO:
                break
            default:
                owsFailDebug("Unexpected story type")
            }
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

                let modal = CameraFirstCaptureNavigationController.cameraFirstModal(storiesOnly: true)
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

    private func reloadStories() {
        loadingQueue.async {
            self.syncingModels.mutate { _ -> ([StoryViewModel], Void)? in
                let (listStories, outgoingStories) = Self.databaseStorage.read {
                    (
                        StoryFinder.storiesForListView(transaction: $0),
                        StoryFinder.outgoingStories(limit: 2, transaction: $0)
                    )
                }
                let myStoryModel = Self.databaseStorage.read { MyStoryViewModel(messages: outgoingStories, transaction: $0) }
                let groupedMessages = Dictionary(grouping: listStories) { $0.context }
                self.myStoryModel.set(myStoryModel)
                let newValues = Self.databaseStorage.read { transaction in
                    groupedMessages.compactMap { try? StoryViewModel(messages: $1, transaction: transaction) }
                }.sorted(by: self.sortStoryModels)
                return (newValues, ())
            } sync: { (_, _) in
                self.tableView.reloadData()
            }
        }
    }

    private func updateStories(forRowIds rowIds: Set<Int64>) {
        AssertIsOnMainThread()

        guard !rowIds.isEmpty else { return }

        loadingQueue.async {
            let ok =
            self.syncingModels.mutate { models -> ([StoryViewModel], (Bool, [BatchUpdate<StoryContext>.Item]))? in
                let myStoryModel = self.myStoryModel.get()

                let (updatedListMessages, outgoingStories) = Self.databaseStorage.read {
                    (
                        StoryFinder.listStoriesWithRowIds(Array(rowIds), transaction: $0),
                        StoryFinder.outgoingStories(limit: 2, transaction: $0)
                    )
                }
                var deletedRowIds = rowIds.subtracting(updatedListMessages.lazy.map { $0.id! })
                var groupedMessages = Dictionary(grouping: updatedListMessages) { $0.context }

                let oldContexts = models.map { $0.context }
                var changedContexts = [StoryContext]()

                let newModels: [StoryViewModel]
                do {
                    newModels = try Self.databaseStorage.read { transaction in
                        try models.compactMap { model in
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
                        } + groupedMessages.map { try StoryViewModel(messages: $1, transaction: transaction) }
                    }.sorted(by: self.sortStoryModels)
                } catch {
                    owsFailDebug("Failed to build new models, hard reloading \(error)")
                    return nil
                }
                let myStoryChanged = rowIds.intersection(outgoingStories.map { $0.id! }).count > 0
                    || Set(myStoryModel?.messages.map { $0.uniqueId } ?? []) != Set(outgoingStories.map { $0.uniqueId })
                let newMyStoryModel = myStoryChanged
                    ? Self.databaseStorage.read { MyStoryViewModel(messages: outgoingStories, transaction: $0) }
                    : myStoryModel

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
                    return nil
                }
                self.myStoryModel.set(newMyStoryModel)
                return (newModels, (myStoryChanged, batchUpdateItems))
            } sync: { (newModels, userInfo: (Bool, [BatchUpdate<StoryContext>.Item])) in
                let (myStoryChanged, batchUpdateItems) = userInfo
                guard self.isViewLoaded else { return }
                self.tableView.beginUpdates()
                if myStoryChanged {
                    self.tableView.reloadRows(at: [IndexPath(row: 0, section: Section.myStory.rawValue)], with: .automatic)
                }

                for update in batchUpdateItems {
                    switch update.updateType {
                    case .delete(let oldIndex):
                        self.tableView.deleteRows(at: [IndexPath(row: oldIndex, section: Section.visibleStories.rawValue)], with: .automatic)
                    case .insert(let newIndex):
                        self.tableView.insertRows(at: [IndexPath(row: newIndex, section: Section.visibleStories.rawValue)], with: .automatic)
                    case .move(let oldIndex, let newIndex):
                        self.tableView.deleteRows(at: [IndexPath(row: oldIndex, section: Section.visibleStories.rawValue)], with: .automatic)
                        self.tableView.insertRows(at: [IndexPath(row: newIndex, section: Section.visibleStories.rawValue)], with: .automatic)
                    case .update(_, let newIndex):
                        // If the cell is visible, reconfigure it directly without reloading.
                        let path = IndexPath(row: newIndex, section: Section.visibleStories.rawValue)
                        if (self.tableView.indexPathsForVisibleRows ?? []).contains(path),
                            let visibleCell = self.tableView.cellForRow(at: path) as? StoryCell {
                            guard let model = newModels[safe: newIndex] else {
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

            if !ok {
                DispatchQueue.main.async { self.reloadStories() }
                return
            }
        }
    }

    // Sort story models for display.
    // * We show system stories first, then other stories. Within each bucket:
    //   * We show unviewed stories first, sorted by their sent timestamp, with the most recently sent at the top
    //   * We then show viewed stories, sorted by when they were viewed, with the most recently viewed at the top
    private func sortStoryModels(lhs: StoryViewModel, rhs: StoryViewModel) -> Bool {
        if lhs.isSystemStory {
            return true
        } else if rhs.isSystemStory {
            return false
        } else if
            let lhsViewedTimestamp = lhs.latestMessageViewedTimestamp,
            let rhsViewedTimestamp = rhs.latestMessageViewedTimestamp
        {
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

        switch Section(rawValue: indexPath.section) {
        case .myStory:
            navigationController?.pushViewController(MyStoriesViewController(), animated: true)
        case .visibleStories:
            guard let model = model(for: indexPath) else {
                owsFailDebug("Missing model for story")
                return
            }

            // If we tap on a story with unviewed stories, we only want the viewer
            // to page through unviewed contexts.
            let viewableContexts: [StoryContext]
            if model.hasUnviewedMessages {
                viewableContexts = syncingModels.get().lazy.filter { $0.hasUnviewedMessages }.map { $0.context }
            } else {
                viewableContexts = syncingModels.allContexts
            }

            let vc = StoryPageViewController(context: model.context, viewableContexts: viewableContexts)
            vc.contextDataSource = self
            presentFullScreen(vc, animated: true)
        case .hiddenStories:
            // TODO:
            break
        default:
            owsFailDebug("Unexpected section \(indexPath.section)")
        }
    }
}

extension StoriesViewController: UITableViewDataSource {
    enum Section: Int {
        case myStory = 0
        case visibleStories = 1
        case hiddenStories = 2
    }

    func model(for indexPath: IndexPath) -> StoryViewModel? {
        // TODO: Hidden stories
        guard indexPath.section == Section.visibleStories.rawValue else { return nil }
        return syncingModels.get()[safe: indexPath.row]
    }

    func model(for context: StoryContext) -> StoryViewModel? {
        syncingModels.get().first { $0.context == context }
    }

    func cell(for context: StoryContext) -> StoryCell? {
        guard let row = syncingModels.get().firstIndex(where: { $0.context == context }) else { return nil }
        let indexPath = IndexPath(row: row, section: Section.visibleStories.rawValue)
        guard tableView.indexPathsForVisibleRows?.contains(indexPath) == true else { return nil }
        return tableView.cellForRow(at: indexPath) as? StoryCell
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .myStory:
            let cell = tableView.dequeueReusableCell(withIdentifier: MyStoryCell.reuseIdentifier) as! MyStoryCell
            guard let myStoryModel = myStoryModel.get() else {
                owsFailDebug("Missing my story model")
                return cell
            }
            cell.configure(with: myStoryModel) { [weak self] in self?.showCameraView() }
            return cell
        case .visibleStories:
            let cell = tableView.dequeueReusableCell(withIdentifier: StoryCell.reuseIdentifier) as! StoryCell
            guard let model = model(for: indexPath) else {
                owsFailDebug("Missing model for story")
                return cell
            }
            cell.configure(with: model)
            return cell
        case .hiddenStories:
            return UITableViewCell()
        default:
            owsFailDebug("Unexpected section \(indexPath.section)")
            return UITableViewCell()
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        emptyStateLabel.isHidden = syncingModels.get().count > 0 || myStoryModel.get()?.messages.isEmpty == false

        switch Section(rawValue: section) {
        case .myStory:
            return 1
        case .visibleStories:
            return syncingModels.get().count
        case .hiddenStories:
            return 0 // TODO: Hidden stories
        default:
            owsFailDebug("Unexpected section \(section)")
            return 0
        }
    }
}

extension StoriesViewController: StoryPageViewControllerDataSource {
    func storyPageViewControllerAvailableContexts(_ storyPageViewController: StoryPageViewController) -> [StoryContext] {
        syncingModels.allContexts
    }
}

extension StoriesViewController: ContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: ContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> ContextMenuConfiguration? {
        guard
            let indexPath = tableView.indexPathForRow(at: location),
            let model = model(for: indexPath)
        else {
            return nil
        }

        return .init(identifier: indexPath as NSCopying) { _ in

            var actions = [ContextMenuAction]()

            actions.append(StoryHidingManager(model: model).contextMenuAction(forPresentingController: self))

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

            // Don't add sharing and forwarding actions for system stories.
            if model.messages.first?.authorAddress.isSystemStoryAddress != true {
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
                }
            }

            let goToChatAction: ContextMenuActionHandler?
            switch model.context {
            case .groupId(let groupId):
                goToChatAction = { _ in
                    guard let thread = Self.databaseStorage.read(block: { TSGroupThread.fetch(groupId: groupId, transaction: $0) }) else {
                        return owsFailDebug("Unexpectedly missing thread for group story")
                    }
                    Self.signalApp.presentConversation(for: thread, action: .compose, animated: true)
                }
            case .authorUuid(let authorUuid):
                guard !authorUuid.asSignalServiceAddress().isSystemStoryAddress else {
                    goToChatAction = nil
                    break
                }
                goToChatAction = { _ in
                    guard let thread = Self.databaseStorage.read(
                        block: { TSContactThread.getWithContactAddress(SignalServiceAddress(uuid: authorUuid), transaction: $0) }
                    ) else {
                        return owsFailDebug("Unexpectedly missing thread for 1:1 story")
                    }
                    Self.signalApp.presentConversation(for: thread, action: .compose, animated: true)
                }
            case .privateStory:
                owsFailDebug("Unexpectedly had private story on stories list")
                goToChatAction = nil
            case .none:
                owsFailDebug("Unexpectedly missing context for story")
                goToChatAction = nil
            }
            if let goToChatAction = goToChatAction {
                actions.append(.init(
                    title: NSLocalizedString(
                        "STORIES_GO_TO_CHAT_ACTION",
                        comment: "Context menu action to open the chat associated with the selected story"),
                    image: Theme.iconImage(.open24),
                    handler: goToChatAction
                ))
            }

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

@propertyWrapper
struct ThreadBoundValue<T> {
    private var value: T
    private var queue: DispatchQueue

    var wrappedValue: T {
        get {
            dispatchPrecondition(condition: .onQueue(queue))
            return value
        }
        set {
            dispatchPrecondition(condition: .onQueue(queue))
            value = newValue
        }
    }

    init(wrappedValue: T, queue: DispatchQueue) {
        self.value = wrappedValue
        self.queue = queue
    }
}

private class SyncingStoryViewModelArray {
    // This is always the most up-to-date collection of models.
    @ThreadBoundValue(wrappedValue: [], queue: loadingQueue) private var trueModels: [StoryViewModel]

    // This may lag behind `trueModels` and is eventually consistent. It is exposed to UITableView.
    @ThreadBoundValue(wrappedValue: [], queue: .main) private var exposedModels: [StoryViewModel]

    private var contexts = AtomicArray<StoryContext>()

    /// Safely modify the list of models. This method must be called on the loading queue.
    ///
    /// - Parameters
    ///   - closure: Called synchronously. Returns nil to abort mutation without side-effects. Otherwise, it returns the new values for the models array and user data to pass to `sync`.
    ///   - models: The existing array of models.
    ///   - sync: Runs asynchronously on the main queue after `closure` returns.
    ///   - newModels: The array of models returned by `closure`.
    ///   - userData: The second value returned by `closure`.
    ///
    /// - Returns whether the closure returned a nonnil list of models.
    @discardableResult
    func mutate<T>(_ closure: (_ models: [StoryViewModel]) -> ([StoryViewModel], T)?,
                   sync: @escaping (_ newModels: [StoryViewModel], _ userData: T) -> Void) -> Bool {
        dispatchPrecondition(condition: .onQueue(loadingQueue))

        guard let (newModels, userInfo) = closure(trueModels) else {
            return false
        }
        trueModels = newModels
        DispatchQueue.main.async {
            self.contexts.set(newModels.map { $0.context })
            self.exposedModels = newModels
            sync(newModels, userInfo)
        }
        return true
    }

    func get() -> [StoryViewModel] {
        return exposedModels
    }

    /// Thread safe list of all contexts currently exposed
    var allContexts: [StoryContext] {
        contexts.get()
    }
}
