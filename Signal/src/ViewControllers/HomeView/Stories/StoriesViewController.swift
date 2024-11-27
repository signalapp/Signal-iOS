//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Photos
import SignalServiceKit
import SignalUI
import UIKit

class StoriesViewController: OWSViewController, StoryListDataSourceDelegate, HomeTabViewController {
    let tableView = UITableView()

    private lazy var searchController = UISearchController()

    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.secondaryTextAndIconColor
        label.font = .dynamicTypeBody
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = OWSLocalizedString("STORIES_NO_RECENT_MESSAGES", comment: "Indicates that there are no recent stories to render")
        label.isHidden = true
        label.isUserInteractionEnabled = false
        tableView.backgroundView = label
        return label
    }()

    private lazy var dataSource = StoryListDataSource(delegate: self, spoilerState: spoilerState)

    private lazy var contextMenuGenerator = StoryContextMenuGenerator(presentingController: self, delegate: self)

    private let appReadiness: AppReadinessSetter
    private let spoilerState: SpoilerRenderState

    public init(appReadiness: AppReadinessSetter, spoilerState: SpoilerRenderState) {
        self.appReadiness = appReadiness
        self.spoilerState = spoilerState
        super.init()
        // Want to start loading right away to prevent cases where things aren't loaded
        // when you tab over into the stories list.
        dataSource.reloadStories()
        dataSource.beginObservingDatabase()

        NotificationCenter.default.addObserver(self, selector: #selector(profileDidChange), name: UserProfileNotifications.localProfileDidChange, object: nil)
    }

    var tableViewIfLoaded: UITableView? {
        return viewIfLoaded == nil ? nil : tableView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        tableView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)
        tableView.delegate = self
        tableView.dataSource = self

        // Search
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController

        title = OWSLocalizedString("STORIES_TITLE", comment: "Title for the stories view.")

        tableView.register(MyStoryCell.self, forCellReuseIdentifier: MyStoryCell.reuseIdentifier)
        tableView.register(StoryCell.self, forCellReuseIdentifier: StoryCell.reuseIdentifier)
        tableView.register(HiddenStoryHeaderCell.self, forCellReuseIdentifier: HiddenStoryHeaderCell.reuseIdentifier)
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 116

        updateNavigationBar()

        OWSTableViewController2.removeBackButtonText(viewController: self)
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
                    cell.configureSubtitle(with: model)
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

    private var viewIsAppeared = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.viewIsAppeared = true

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

        defer {
            self.viewIsAppeared = false
        }

        timestampUpdateTimer?.invalidate()
        timestampUpdateTimer = nil
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if !searchController.searchBar.text.isEmptyOrNil {
            searchController.isActive = false
            dataSource.setSearchText(nil)
        }
    }

    override func themeDidChange() {
        super.themeDidChange()
        applyTheme()
    }

    private func applyTheme() {
        emptyStateLabel.textColor = Theme.secondaryTextAndIconColor

        for indexPath in self.tableView.indexPathsForVisibleRows ?? [] {
            switch Section(rawValue: indexPath.section) {
            case .myStory:
                guard let cell = self.tableView.cellForRow(at: indexPath) as? MyStoryCell else { continue }
                guard let model = dataSource.myStory else { continue }
                cell.configure(with: model, spoilerState: spoilerState) { [weak self] in self?.showCameraView() }
            case .visibleStories:
                guard let cell = self.tableView.cellForRow(at: indexPath) as? StoryCell else { continue }
                guard let model = self.model(for: indexPath) else { continue }
                cell.configure(with: model, spoilerState: spoilerState)
            case .hiddenStories:
                let cell = self.tableView.cellForRow(at: indexPath)
                if
                    let storyCell = cell as? StoryCell,
                    let model = self.model(for: indexPath)
                {
                    storyCell.configure(with: model, spoilerState: spoilerState)
                } else if
                    let headerCell = cell as? HiddenStoryHeaderCell
                {
                    headerCell.configure(isCollapsed: dataSource.isHiddenStoriesSectionCollapsed)
                }
            case .none:
                owsFailDebug("Unexpected story type")
            }
        }

        view.backgroundColor = Theme.backgroundColor
        tableView.backgroundColor = Theme.backgroundColor

        updateNavigationBar()
    }

    @objc
    private func profileDidChange() { updateNavigationBar() }

    private func updateNavigationBar() {
        navigationItem.leftBarButtonItem = createSettingsBarButtonItem(
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            buildActions: { settingsAction -> [UIAction] in
                return [
                    UIAction(
                        title: OWSLocalizedString(
                            "STORY_PRIVACY_TITLE",
                            comment: "Title for the story privacy settings view"
                        ),
                        image: Theme.iconImage(.contextMenuPrivacy),
                        handler: { [weak self] _ in
                            self?.showPrivacySettings()
                        }
                    ),
                    settingsAction,
                ]
            },
            showAppSettings: { [weak self] in
                self?.showAppSettings()
            }
        )

        let cameraButton = UIBarButtonItem(image: Theme.iconImage(.buttonCamera), style: .plain, target: self, action: #selector(showCameraView))
        cameraButton.accessibilityLabel = OWSLocalizedString("CAMERA_BUTTON_LABEL", comment: "Accessibility label for camera button.")
        cameraButton.accessibilityHint = OWSLocalizedString("CAMERA_BUTTON_HINT", comment: "Accessibility hint describing what you can do with the camera button")

        navigationItem.rightBarButtonItems = [cameraButton]
    }

    @objc
    private func showCameraView() {
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

                let modal = CameraFirstCaptureNavigationController.cameraFirstModal(storiesOnly: true, delegate: self)
                self.presentFullScreen(modal, animated: true)
            }
        }
    }

    public func showMyStories(animated: Bool) {
        navigationController?.pushViewController(MyStoriesViewController(spoilerState: spoilerState), animated: animated)
    }

    func showAppSettings() {
        AssertIsOnMainThread()

        conversationSplitViewController?.selectedConversationViewController?.dismissMessageContextMenu(animated: true)
        presentFormSheet(AppSettingsViewController.inModalNavigationController(appReadiness: appReadiness), animated: true)
    }

    func showPrivacySettings() {
        AssertIsOnMainThread()

        let vc = StoryPrivacySettingsViewController()
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    // MARK: - Scrolling after reload

    private enum ScrollTarget {
        // Scroll to a section so its first cell is at the top.
        case section(Section)
        // Scroll to a context, optionally restricted to a given section.
        // Highlights after scroll.
        case context(StoryContext, section: Section?)
    }

    private var scrollTarget: ScrollTarget?

    public func tableViewDidUpdate() {
        emptyStateLabel.isHidden = !dataSource.isEmpty
        tableView.isScrollEnabled = !dataSource.isEmpty
        // Because scrolling is disabled when data is empty, disable
        // collapsing to ensure the search bar stays visible.
        navigationItem.hidesSearchBarWhenScrolling = !dataSource.isEmpty

        guard let scrollTarget = scrollTarget else {
            return
        }
        switch scrollTarget {
        case .section(let section):
            guard tableView.numberOfRows(inSection: section.rawValue) > 0 else {
                return
            }
            tableView.scrollToRow(at: IndexPath(item: 0, section: section.rawValue), at: .top, animated: true)
            self.scrollTarget = nil
        case let .context(context, sectionConstraint):
            let section: Section
            let index: Int
            if
                sectionConstraint ?? .visibleStories == .visibleStories,
                let visibleStoryIndex = dataSource.visibleStories.firstIndex(where: { $0.context == context }) {
                section = .visibleStories
                index = visibleStoryIndex
            } else if
                sectionConstraint ?? .hiddenStories == .hiddenStories,
                let hiddenStoryIndex = dataSource.hiddenStories.firstIndex(where: { $0.context == context }),
                dataSource.shouldDisplayHiddenStories {
                section = .hiddenStories
                // Offset for the header
                let headerOffset = dataSource.shouldDisplayHiddenStoriesHeader ? 1 : 0
                index = hiddenStoryIndex + headerOffset
            } else {
                // Not found.
                return
            }
            let indexPath = IndexPath(row: index, section: section.rawValue)
            tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
            self.scrollTarget = nil
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

extension StoriesViewController: UITableViewDelegate {

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard
            searchController.isActive,
            searchController.searchBar.text.isEmptyOrNil
        else { return }
        tableView.contentOffset.y += 1
        searchController.isActive = false
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section) {
        case .myStory:
            if dataSource.myStory?.messages.isEmpty == true {
                showCameraView()
            } else {
                showMyStories(animated: true)
            }
        case .hiddenStories:
            if indexPath.row == 0, dataSource.shouldDisplayHiddenStoriesHeader {
                // Tapping the collapsing header.
                let wasCollapsed = dataSource.isHiddenStoriesSectionCollapsed
                dataSource.isHiddenStoriesSectionCollapsed = !wasCollapsed
                if wasCollapsed {
                    // Scroll to it once we reload.
                    self.scrollTarget = .section(.hiddenStories)
                }
            } else {
                fallthrough
            }
        case .visibleStories:
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
                guard let latestMessageThread = SSKEnvironment.shared.databaseStorageRef.read(block: { latestMessage.context.thread(transaction: $0) }) else {
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
            // non-hidden contexts, and vice versa.
            let startedFromHidden = model.isHidden
            let viewableContexts: [StoryContext] = dataSource.allStories
                .lazy
                .filter { !filterViewed || $0.hasUnviewedMessages }
                .filter { startedFromHidden == $0.isHidden }
                .map(\.context)

            let vc = StoryPageViewController(
                context: model.context,
                spoilerState: spoilerState,
                viewableContexts: viewableContexts,
                hiddenStoryFilter: startedFromHidden
            )
            vc.contextDataSource = self
            presentFullScreen(vc, animated: true)
        case .none:
            owsFailDebug("Unexpected section \(indexPath.section)")
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        switch Section(rawValue: indexPath.section) {
        case .hiddenStories, .visibleStories:
            return true
        case .myStory, .none:
            return false
        }
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        switch Section(rawValue: indexPath.section) {
        case .hiddenStories, .visibleStories:
            guard
                let model = model(for: indexPath),
                let action = contextMenuGenerator.goToChatContextualAction(for: model)
            else {
                return nil
            }
            return .init(actions: [action])
        case .myStory, .none:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        switch Section(rawValue: indexPath.section) {
        case .hiddenStories, .visibleStories:
            guard
                let model = model(for: indexPath),
                let action = contextMenuGenerator.hideTableRowContextualAction(for: model)
            else {
                return nil
            }
            return .init(actions: [action])
        case .myStory, .none:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let model = model(for: indexPath) else {
            return nil
        }

        return .init(identifier: indexPath as NSCopying, previewProvider: nil, actionProvider: { [weak self] _ in
            guard let self else { return .init(children: []) }
            let actions = self.contextMenuGenerator.nativeContextMenuActions(
                for: model,
                spoilerState: self.spoilerState,
                sourceView: { [weak self] in
                    return self?.tableView.cellForRow(at: indexPath)
                }
            )
            return .init(children: actions)
        })
    }
}

extension StoriesViewController: UITableViewDataSource {
    typealias Section = StoryListDataSource.Section

    func model(for indexPath: IndexPath) -> StoryViewModel? {
        switch Section(rawValue: indexPath.section) {
        case .visibleStories:
            return dataSource.visibleStories[safe: indexPath.row]
        case .hiddenStories:
            // Offset by 1 to account for the header cell.
            let headerOffset = dataSource.shouldDisplayHiddenStoriesHeader ? 1 : 0
            return dataSource.hiddenStories[safe: indexPath.row - headerOffset]
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
            dataSource.shouldDisplayHiddenStories,
            let hiddenRow = dataSource.hiddenStories.firstIndex(where: { $0.context == context }) {
            // Offset by 1 to account for the header cell.
            let headerOffset = dataSource.shouldDisplayHiddenStoriesHeader ? 1 : 0
            indexPath = IndexPath(row: hiddenRow + headerOffset, section: Section.hiddenStories.rawValue)
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
            cell.configure(with: myStoryModel, spoilerState: spoilerState) { [weak self] in self?.showCameraView() }
            return cell
        case .hiddenStories:
            if indexPath.row == 0 && dataSource.shouldDisplayHiddenStoriesHeader {
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: HiddenStoryHeaderCell.reuseIdentifier,
                    for: indexPath
                ) as! HiddenStoryHeaderCell
                cell.configure(isCollapsed: dataSource.isHiddenStoriesSectionCollapsed)
                return cell
            } else {
                fallthrough
            }
        case .visibleStories:
            let cell = tableView.dequeueReusableCell(withIdentifier: StoryCell.reuseIdentifier) as! StoryCell
            guard let model = model(for: indexPath) else {
                owsFailDebug("Missing model for story")
                return cell
            }
            cell.configure(with: model, spoilerState: spoilerState)
            return cell
        case .none:
            owsFailDebug("Unexpected section \(indexPath.section)")
            return UITableViewCell()
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .myStory:
            return dataSource.shouldDisplayMyStory ? 1 : 0
        case .visibleStories:
            return dataSource.visibleStories.count
        case .hiddenStories:
            return (
                dataSource.shouldDisplayHiddenStoriesHeader ? 1 : 0
            ) + (
                dataSource.shouldDisplayHiddenStories ? dataSource.hiddenStories.count : 0
            )
        case .none:
            owsFailDebug("Unexpected section \(section)")
            return 0
        }
    }
}

extension StoriesViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        dataSource.setSearchText(searchController.searchBar.text?.nilIfEmpty)
    }
}

extension StoriesViewController: StoryPageViewControllerDataSource {
    func storyPageViewControllerAvailableContexts(
        _ storyPageViewController: StoryPageViewController,
        hiddenStoryFilter: Bool?
    ) -> [StoryContext] {
        if hiddenStoryFilter == true {
            return dataSource.threadSafeHiddenStoryContexts
        } else if hiddenStoryFilter == false {
            return dataSource.threadSafeVisibleStoryContexts
        } else {
            return dataSource.threadSafeStoryContexts
        }
    }
}

extension StoriesViewController: StoryContextMenuDelegate {

    func storyContextMenuDidUpdateHiddenState(_ message: StoryMessage, isHidden: Bool) -> Bool {
        if isHidden {
            // Uncollapse so we can scroll to the section.
            dataSource.isHiddenStoriesSectionCollapsed = false
        }
        self.scrollTarget = .context(message.context, section: isHidden ? .hiddenStories : .visibleStories)
        // Don't show a toast, we have the scroll action.
        return false
    }
}
