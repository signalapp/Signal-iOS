//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import UIKit
import SignalUI

class StoriesViewController: OWSViewController, StoryListDataSourceDelegate {
    let tableView = UITableView()

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

    private lazy var dataSource = StoryListDataSource(delegate: self)

    override init() {
        super.init()
        // Want to start loading right away to prevent cases where things aren't loaded
        // when you tab over into the stories list.
        dataSource.reloadStories()
        dataSource.beginObservingDatabase()

        NotificationCenter.default.addObserver(self, selector: #selector(profileDidChange), name: .localProfileDidChange, object: nil)
    }

    override func loadView() {
        view = tableView
        tableView.delegate = self
        tableView.dataSource = self
    }

    var tableViewIfLoaded: UITableView? {
        return viewIfLoaded as? UITableView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("STORIES_TITLE", comment: "Title for the stories view.")

        tableView.register(MyStoryCell.self, forCellReuseIdentifier: MyStoryCell.reuseIdentifier)
        tableView.register(StoryCell.self, forCellReuseIdentifier: StoryCell.reuseIdentifier)
        tableView.register(HiddenStoryHeaderView.self, forHeaderFooterViewReuseIdentifier: HiddenStoryHeaderView.reuseIdentifier)
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
                    guard let model = self.dataSource.myStory else { continue }
                    cell.configureTimestamp(with: model)
                case .visibleStories, .hiddenStories:
                    guard let cell = self.tableView.cellForRow(at: indexPath) as? StoryCell else { continue }
                    guard let model = self.model(for: indexPath) else { continue }
                    cell.configureSubtitle(with: model)
                case .none:
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
                guard let model = dataSource.myStory else { continue }
                cell.configure(with: model) { [weak self] in self?.showCameraView() }
            case .visibleStories, .hiddenStories:
                guard let cell = self.tableView.cellForRow(at: indexPath) as? StoryCell else { continue }
                guard let model = self.model(for: indexPath) else { continue }
                cell.configure(with: model)
            case .none:
                owsFailDebug("Unexpected story type")
            }
        }

        // No easy way to get visible headers, but just update the header view since theres only one.
        (
            tableView.headerView(forSection: Section.hiddenStories.rawValue) as? HiddenStoryHeaderView
        )?.configure(isCollapsed: dataSource.isHiddenStoriesSectionCollapsed)

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
}

extension StoriesViewController: CameraFirstCaptureDelegate {
    func cameraFirstCaptureSendFlowDidComplete(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow) {
        dismiss(animated: true)
    }

    func cameraFirstCaptureSendFlowDidCancel(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow) {
        dismiss(animated: true)
    }
}

extension StoriesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section) {
        case .myStory:
            navigationController?.pushViewController(MyStoriesViewController(), animated: true)
        case .visibleStories, .hiddenStories:
            guard let model = model(for: indexPath) else {
                owsFailDebug("Missing model for story")
                return
            }

            // Navigate to "My Stories" rather than the viewer if the message is failed
            if model.latestMessageSendingState == .failed {
                guard let latestMessage = model.messages.last else {
                    owsFailDebug("Missing message for failed send")
                    return
                }
                guard let latestMessageThread = databaseStorage.read(block: { latestMessage.context.thread(transaction: $0) }) else {
                    owsFailDebug("Missing thread for failed send")
                    return
                }
                StoryUtil.askToResend(latestMessage, in: latestMessageThread, from: self)
                return
            }

            // If we tap on a story with unviewed stories, we only want the viewer
            // to page through unviewed contexts.
            let filterViewed = model.hasUnviewedMessages
            // If we tap on a non-hidden story, we only want the viewer to page through
            // non-hidden contexts.
            let filterHidden = !model.isHidden
            let viewableContexts: [StoryContext] = dataSource.allStories
                .lazy
                .filter { !filterViewed || $0.hasUnviewedMessages }
                .filter { !filterHidden || !$0.isHidden }
                .map(\.context)

            let vc = StoryPageViewController(context: model.context, viewableContexts: viewableContexts)
            vc.contextDataSource = self
            presentFullScreen(vc, animated: true)
        case .none:
            owsFailDebug("Unexpected section \(indexPath.section)")
        }
    }
}

extension StoriesViewController: UITableViewDataSource {
    typealias Section = StoryListDataSource.Section

    func model(for indexPath: IndexPath) -> StoryViewModel? {
        switch Section(rawValue: indexPath.section) {
        case .visibleStories:
            return dataSource.visibleStories[safe: indexPath.row]
        case .hiddenStories:
            return dataSource.hiddenStories[safe: indexPath.row]
        case .myStory, .none:
            return nil
        }
    }

    func model(for context: StoryContext) -> StoryViewModel? {
        dataSource.allStories.first { $0.context == context }
    }

    func cell(for context: StoryContext) -> StoryCell? {
        let indexPath: IndexPath
        if let visibleRow = dataSource.visibleStories.firstIndex(where: { $0.context == context }) {
            indexPath = IndexPath(row: visibleRow, section: Section.visibleStories.rawValue)
        } else if
            !dataSource.isHiddenStoriesSectionCollapsed,
            let hiddenRow = dataSource.hiddenStories.firstIndex(where: { $0.context == context }) {
            indexPath = IndexPath(row: hiddenRow, section: Section.hiddenStories.rawValue)
        } else {
            return nil
        }
        guard tableView.indexPathsForVisibleRows?.contains(indexPath) == true else { return nil }
        return tableView.cellForRow(at: indexPath) as? StoryCell
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .myStory:
            let cell = tableView.dequeueReusableCell(withIdentifier: MyStoryCell.reuseIdentifier) as! MyStoryCell
            guard let myStoryModel = dataSource.myStory else {
                owsFailDebug("Missing my story model")
                return cell
            }
            cell.configure(with: myStoryModel) { [weak self] in self?.showCameraView() }
            return cell
        case .visibleStories, .hiddenStories:
            let cell = tableView.dequeueReusableCell(withIdentifier: StoryCell.reuseIdentifier) as! StoryCell
            guard let model = model(for: indexPath) else {
                owsFailDebug("Missing model for story")
                return cell
            }
            cell.configure(with: model)
            return cell
        case .none:
            owsFailDebug("Unexpected section \(indexPath.section)")
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch Section(rawValue: section) {
        case .myStory, .visibleStories, .none:
            return nil
        case .hiddenStories:
            guard !dataSource.hiddenStories.isEmpty else {
                return nil
            }
            let header = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: HiddenStoryHeaderView.reuseIdentifier
            ) as! HiddenStoryHeaderView
            header.configure(isCollapsed: dataSource.isHiddenStoriesSectionCollapsed)
            header.tapHandler = { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.dataSource.isHiddenStoriesSectionCollapsed = !strongSelf.dataSource.isHiddenStoriesSectionCollapsed
            }
            return header
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch Section(rawValue: section) {
        case .myStory, .visibleStories, .none:
            return 0
        case .hiddenStories:
            return dataSource.hiddenStories.isEmpty ? 0 : 44
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        emptyStateLabel.isHidden = !dataSource.allStories.isEmpty || dataSource.myStory?.messages.isEmpty == false

        switch Section(rawValue: section) {
        case .myStory:
            return dataSource.myStory == nil ? 0 : 1
        case .visibleStories:
            return dataSource.visibleStories.count
        case .hiddenStories:
            return dataSource.isHiddenStoriesSectionCollapsed ? 0 : dataSource.hiddenStories.count
        case .none:
            owsFailDebug("Unexpected section \(section)")
            return 0
        }
    }
}

extension StoriesViewController: StoryPageViewControllerDataSource {
    func storyPageViewControllerAvailableContexts(_ storyPageViewController: StoryPageViewController) -> [StoryContext] {
        return dataSource.threadSafeStoryContexts
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
