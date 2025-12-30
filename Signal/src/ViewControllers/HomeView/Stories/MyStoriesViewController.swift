//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PhotosUI
import SignalServiceKit
import SignalUI
import UIKit

class MyStoriesViewController: OWSViewController, FailedStorySendDisplayController {
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private var items = OrderedDictionary<String, [OutgoingStoryItem]>() {
        didSet { emptyStateLabel.isHidden = items.orderedKeys.count > 0 }
    }

    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.secondaryLabel
        label.font = .dynamicTypeBody
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = OWSLocalizedString("MY_STORIES_NO_STORIES", comment: "Indicates that there are no sent stories to render")
        label.isHidden = true
        label.isUserInteractionEnabled = false
        tableView.backgroundView = label
        return label
    }()

    private lazy var contextMenuGenerator = StoryContextMenuGenerator(presentingController: self)

    private let spoilerState: SpoilerRenderState

    init(spoilerState: SpoilerRenderState) {
        self.spoilerState = spoilerState
        super.init()
        hidesBottomBarWhenPushed = true
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background
        tableView.backgroundColor = .Signal.background

        title = OWSLocalizedString("MY_STORIES_TITLE", comment: "Title for the 'My Stories' view")

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SentStoryCell.self, forCellReuseIdentifier: SentStoryCell.reuseIdentifier)
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 116
        tableView.backgroundColor = .Signal.background
        view.addSubview(tableView)
        tableView.autoPinHeight(toHeightOf: view)
        tableViewHorizontalEdgeConstraints = [
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
        ]
        NSLayoutConstraint.activate(tableViewHorizontalEdgeConstraints)
        updateTableViewPaddingIfNeeded()

        reloadStories()

        navigationItem.rightBarButtonItem = .init(
            title: OWSLocalizedString("STORY_PRIVACY_SETTINGS", comment: "Button to access the story privacy settings menu"),
            style: .plain,
            target: self,
            action: #selector(showPrivacySettings),
        )
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateTableViewPaddingIfNeeded()
    }

    @objc
    private func showPrivacySettings() {
        let vc = StoryPrivacySettingsViewController()
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    /// Set to `true` when list is displayed in split view controller's "sidebar" on iOS 26 and later.
    /// Setting this to `true` would add an extra padding on both sides of the table view.
    /// This value is also passed down to table view cells that make their own layout choices based on the value.
    private var useSidebarStoryListCellAppearance = false {
        didSet {
            guard oldValue != useSidebarStoryListCellAppearance else { return }
            tableViewHorizontalEdgeConstraints.forEach {
                $0.constant = useSidebarStoryListCellAppearance ? 16 : 0
            }
            tableView.reloadData()
        }
    }

    private var tableViewHorizontalEdgeConstraints: [NSLayoutConstraint] = []

    /// iOS 26+: checks if this VC is displayed in the collapsed split view controller and updates `useSidebarCallListCellAppearance` accordingly.
    /// Does nothing on prior iOS versions.
    private func updateTableViewPaddingIfNeeded() {
        guard #available(iOS 26, *) else { return }

        if let splitViewController, !splitViewController.isCollapsed {
            useSidebarStoryListCellAppearance = true
        } else {
            useSidebarStoryListCellAppearance = false
        }
    }

    private func reloadStories() {
        AssertIsOnMainThread()

        let outgoingStories = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            StoryFinder.outgoingStories(transaction: transaction)
                .flatMap { OutgoingStoryItem.build(message: $0, transaction: transaction) }
        }

        let groupedStories = Dictionary(grouping: outgoingStories) { $0.thread.uniqueId }

        items = .init(keyValueMap: groupedStories, orderedKeys: groupedStories.keys.sorted { lhsId, rhsId in
            guard let lhs = groupedStories[lhsId]?.first?.thread, let rhs = groupedStories[rhsId]?.first?.thread else {
                return false
            }
            if (lhs as? TSPrivateStoryThread)?.isMyStory == true { return true }
            if (rhs as? TSPrivateStoryThread)?.isMyStory == true { return false }
            if lhs.lastSentStoryTimestamp == rhs.lastSentStoryTimestamp {
                return StoryManager.storyName(for: lhs).localizedCaseInsensitiveCompare(
                    StoryManager.storyName(for: rhs),
                ) == .orderedAscending
            }
            return (lhs.lastSentStoryTimestamp?.uint64Value ?? 0) > (rhs.lastSentStoryTimestamp?.uint64Value ?? 0)
        })
        tableView.reloadData()
    }

    private func item(for indexPath: IndexPath) -> OutgoingStoryItem? {
        items.orderedValues[safe: indexPath.section]?[safe: indexPath.row]
    }

    private func thread(for section: Int) -> TSThread? {
        return items.orderedValues[safe: section]?.first?.thread
    }

    func cell(for message: StoryMessage, and context: StoryContext) -> SentStoryCell? {
        guard let thread = SSKEnvironment.shared.databaseStorageRef.read(block: { context.thread(transaction: $0) }) else { return nil }
        guard let section = items.orderedKeys.firstIndex(of: thread.uniqueId) else { return nil }
        guard let row = items[thread.uniqueId]?.firstIndex(where: { $0.message.uniqueId == message.uniqueId }) else { return nil }

        let indexPath = IndexPath(row: row, section: section)
        guard tableView.indexPathsForVisibleRows?.contains(indexPath) == true else { return nil }
        return tableView.cellForRow(at: indexPath) as? SentStoryCell
    }
}

extension MyStoriesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let thread = thread(for: indexPath.section), let item = item(for: indexPath) else { return }

        if item.message.sendingState == .failed {
            return StoryUtil.askToResend(item.message, in: item.thread, from: self)
        }

        let vc = StoryPageViewController(
            context: thread.storyContext,
            spoilerState: spoilerState,
            viewableContexts: items.orderedKeys.compactMap { items[$0]?.first?.thread.storyContext },
            loadMessage: item.message,
            onlyRenderMyStories: true,
        )
        vc.contextDataSource = self
        present(vc, animated: true)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard
            let item = item(for: indexPath),
            let action = contextMenuGenerator.goToChatContextualAction(thread: item.thread)
        else {
            return nil
        }
        return .init(actions: [action])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard
            let item = item(for: indexPath),
            let action = contextMenuGenerator.deleteTableRowContextualAction(
                for: item.message,
                thread: item.thread,
            )
        else {
            return nil
        }
        return .init(actions: [action])
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = item(for: indexPath) else {
            return nil
        }

        let actions = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return self.contextMenuGenerator.nativeContextMenuActions(
                for: item.message,
                in: item.thread,
                attachment: item.attachment,
                spoilerState: spoilerState,
                sourceView: { [weak self] in
                    // refetch the cell in case it changes out from underneath us.
                    return self?.tableView(tableView, cellForRowAt: indexPath)
                },
                hideSaveAction: true,
                onlyRenderMyStories: true,
                transaction: transaction,
            )
        }

        return .init(identifier: indexPath as NSCopying, previewProvider: nil) { _ in .init(children: actions) }
    }
}

extension MyStoriesViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        items.orderedKeys.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.orderedValues[safe: section]?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let item = item(for: indexPath) else {
            owsFailDebug("Missing item for row at indexPath \(indexPath)")
            return UITableViewCell()
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: SentStoryCell.reuseIdentifier, for: indexPath) as! SentStoryCell

        let contextMenuActions: [UIAction] = {
            guard let item = self.item(for: indexPath) else { return [] }

            return SSKEnvironment.shared.databaseStorageRef.read { tx -> [UIAction] in
                contextMenuGenerator.nativeContextMenuActions(
                    for: item.message,
                    in: item.thread,
                    attachment: item.attachment,
                    spoilerState: spoilerState,
                    sourceView: { [weak self] in
                        // refetch the cell in case it changes out from underneath us.
                        return self?.tableView.dequeueReusableCell(withIdentifier: SentStoryCell.reuseIdentifier, for: indexPath)
                    },
                    transaction: tx,
                )
            }
        }()

        cell.useSidebarAppearance = useSidebarStoryListCellAppearance
        cell.configure(
            with: item,
            spoilerState: spoilerState,
            contextMenuActions: contextMenuActions,
            indexPath: indexPath,
        )
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let thread = thread(for: section) else {
            owsFailDebug("Missing thread for section \(section)")
            return nil
        }

        let textView = LinkingTextView()
        textView.textColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90
        textView.font = UIFont.dynamicTypeHeadlineClamped
        textView.text = StoryManager.storyName(for: thread)

        var textContainerInset = OWSTableViewController2.cellOuterInsets(in: tableView)
        textContainerInset.top = 32
        textContainerInset.bottom = 10

        textContainerInset.left += OWSTableViewController2.cellHInnerMargin * 0.5
        textContainerInset.left += tableView.safeAreaInsets.left

        textContainerInset.right += OWSTableViewController2.cellHInnerMargin * 0.5
        textContainerInset.right += tableView.safeAreaInsets.right

        textView.textContainerInset = textContainerInset

        return textView
    }
}

extension MyStoriesViewController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        reloadStories()
    }

    func databaseChangesDidUpdateExternally() {
        reloadStories()
    }

    func databaseChangesDidReset() {
        reloadStories()
    }
}

extension MyStoriesViewController: ForwardMessageDelegate {
    func forwardMessageFlowDidComplete(items: [ForwardMessageItem], recipientThreads: [TSThread]) {
        AssertIsOnMainThread()

        dismiss(animated: true) {
            ForwardMessageViewController.finalizeForward(
                items: items,
                recipientThreads: recipientThreads,
                fromViewController: self,
            )
        }
    }

    func forwardMessageFlowDidCancel() {
        dismiss(animated: true)
    }
}

extension MyStoriesViewController: StoryPageViewControllerDataSource {
    func storyPageViewControllerAvailableContexts(
        _ storyPageViewController: StoryPageViewController,
        hiddenStoryFilter: Bool?,
    ) -> [StoryContext] {
        return items.orderedValues.compactMap(\.first?.thread.storyContext)
    }
}

private struct OutgoingStoryItem {
    let message: StoryMessage
    let attachment: StoryThumbnailView.Attachment
    let thread: TSThread

    static func build(message: StoryMessage, transaction: DBReadTransaction) -> [OutgoingStoryItem] {
        message.threads(transaction: transaction).map {
            .init(
                message: message,
                attachment: .from(message, transaction: transaction),
                thread: $0,
            )
        }
    }
}

class SentStoryCell: UITableViewCell {
    static let reuseIdentifier = "SentStoryCell"

    let attachmentThumbnail = UIView()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.label
        label.font = .dynamicTypeHeadline
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.secondaryLabel
        label.font = .dynamicTypeSubheadline
        return label
    }()

    private lazy var saveButton: UIButton = {
        let button = UIButton(
            configuration: .gray(),
            primaryAction: UIAction { [weak self] _ in
                self?.saveAttachmentBlock()
            },
        )
        button.configuration?.image = UIImage(imageLiteralResourceName: "save-20")
        button.configuration?.contentInsets = .init(margin: 6)
        button.configuration?.baseForegroundColor = .Signal.label
        button.configuration?.baseBackgroundColor = .Signal.secondaryBackground
        button.configuration?.cornerStyle = .capsule
        return button
    }()

    private let contextButton: ContextMenuButton = {
        let button = ContextMenuButton(empty: ())
        button.configuration = .gray()
        button.configuration?.image = UIImage(imageLiteralResourceName: "more-compact")
        button.configuration?.contentInsets = .init(margin: 8)
        button.configuration?.baseForegroundColor = .Signal.label
        button.configuration?.baseBackgroundColor = .Signal.secondaryBackground
        button.configuration?.cornerStyle = .capsule
        // ContextMenuButton overrides `intrinsicContentSize` so manually specify size.
        button.addConstraints([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 32),
        ])
        return button
    }()

    private lazy var failedIconContainer: UIView = {
        let imageView = UIImageView(image: Theme.iconImage(.error16))
        imageView.tintColor = .Signal.red
        imageView.contentMode = .scaleAspectFit

        let view = UIView()
        view.addSubview(imageView)
        imageView.autoPinHeightToSuperview()
        imageView.autoPinEdge(toSuperviewEdge: .leading)
        imageView.autoSetDimension(.width, toSize: 16)
        view.autoSetDimension(.width, toSize: 28)
        return view
    }()

    /// If set to `true` background in `selected` state would have rounded corners.
    var useSidebarAppearance = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        automaticallyUpdatesBackgroundConfiguration = false

        let vStackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        vStackView.axis = .vertical
        vStackView.alignment = .leading

        let contentHStackView = UIStackView(
            arrangedSubviews: [
                attachmentThumbnail,
                .spacer(withWidth: 16),
                failedIconContainer,
                vStackView,
                .hStretchingSpacer(),
                saveButton,
                .spacer(withWidth: 20),
                contextButton,
            ],
        )
        contentHStackView.axis = .horizontal
        contentHStackView.alignment = .center
        contentView.addSubview(contentHStackView)
        contentHStackView.autoPinEdgesToSuperviewMargins()

        attachmentThumbnail.autoSetDimensions(to: CGSize(width: 56, height: 84))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var configuration = UIBackgroundConfiguration.clear()
        if state.isSelected || state.isHighlighted {
            configuration.backgroundColor = Theme.tableCell2SelectedBackgroundColor
            if useSidebarAppearance {
                configuration.cornerRadius = 24
            }
        } else {
            configuration.backgroundColor = .Signal.background
        }
        backgroundConfiguration = configuration
    }

    private var attachment: StoryThumbnailView.Attachment?

    fileprivate func configure(
        with item: OutgoingStoryItem,
        spoilerState: SpoilerRenderState,
        contextMenuActions: [UIAction],
        indexPath: IndexPath,
    ) {
        if self.attachment != item.attachment {
            self.attachment = item.attachment
            let thumbnailView = StoryThumbnailView(
                attachment: item.attachment,
                interactionIdentifier: .fromStoryMessage(item.message),
                spoilerState: spoilerState,
            )
            attachmentThumbnail.removeAllSubviews()
            attachmentThumbnail.addSubview(thumbnailView)
            thumbnailView.autoPinEdgesToSuperviewEdges()
        }

        switch item.message.sendingState {
        case .pending, .sending:
            titleLabel.text = OWSLocalizedString("STORY_SENDING", comment: "Text indicating that the story is currently sending")
            subtitleLabel.text = ""
            failedIconContainer.isHiddenInStackView = true
        case .failed:
            failedIconContainer.isHiddenInStackView = false
            titleLabel.text = item.message.hasSentToAnyRecipients
                ? OWSLocalizedString("STORY_SEND_PARTIALLY_FAILED", comment: "Text indicating that the story send has partially failed")
                : OWSLocalizedString("STORY_SEND_FAILED", comment: "Text indicating that the story send has failed")
            subtitleLabel.text = OWSLocalizedString("STORY_SEND_FAILED_RETRY", comment: "Text indicating that you can tap to retry sending")
        case .sent:
            if StoryManager.areViewReceiptsEnabled {
                let format = OWSLocalizedString(
                    "STORY_VIEWS_%d",
                    tableName: "PluralAware",
                    comment: "Text explaining how many views a story has. Embeds {{ %d number of views }}",
                )
                titleLabel.text = String.localizedStringWithFormat(format, item.message.remoteViewCount(in: item.thread.storyContext))
            } else {
                titleLabel.text = OWSLocalizedString(
                    "STORY_VIEWS_OFF",
                    comment: "Text indicating that the user has views turned off",
                )
            }
            subtitleLabel.text = DateUtil.formatTimestampRelatively(item.message.timestamp)
            failedIconContainer.isHiddenInStackView = true
        case .sent_OBSOLETE, .delivered_OBSOLETE:
            owsFailDebug("Unexpected legacy sending state")
        }

        if item.attachment.isSaveable {
            saveButton.isHiddenInStackView = false
            saveAttachmentBlock = { item.attachment.save(
                interactionIdentifier: .fromStoryMessage(item.message),
                spoilerState: spoilerState,
            ) }
        } else {
            saveButton.isHiddenInStackView = true
            saveAttachmentBlock = {}
        }

        contextButton.setActions(actions: contextMenuActions)

    }

    private var saveAttachmentBlock: () -> Void = {}
}
