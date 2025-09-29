//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PhotosUI
import SignalServiceKit
import SignalUI
import UIKit

final class MyStoriesViewController: OWSViewController, FailedStorySendDisplayController {
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private var items = OrderedDictionary<String, [OutgoingStoryItem]>() {
        didSet { emptyStateLabel.isHidden = items.orderedKeys.count > 0 }
    }
    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.secondaryTextAndIconColor
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

    public init(spoilerState: SpoilerRenderState) {
        self.spoilerState = spoilerState
        super.init()
        hidesBottomBarWhenPushed = true
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
    }

    override func loadView() {
        view = tableView
        tableView.delegate = self
        tableView.dataSource = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("MY_STORIES_TITLE", comment: "Title for the 'My Stories' view")

        tableView.register(SentStoryCell.self, forCellReuseIdentifier: SentStoryCell.reuseIdentifier)
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 116

        reloadStories()

        navigationItem.rightBarButtonItem = .init(
            title: OWSLocalizedString("STORY_PRIVACY_SETTINGS", comment: "Button to access the story privacy settings menu"),
            style: .plain,
            target: self,
            action: #selector(showPrivacySettings)
        )

        applyTheme()
    }

    override func themeDidChange() {
        super.themeDidChange()
        applyTheme()
    }

    private func applyTheme() {
        emptyStateLabel.textColor = Theme.secondaryTextAndIconColor

        tableView.reloadData()

        view.backgroundColor = Theme.backgroundColor
    }

    @objc
    private func showPrivacySettings() {
        let vc = StoryPrivacySettingsViewController()
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
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
                    StoryManager.storyName(for: rhs)
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
            onlyRenderMyStories: true
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
                thread: item.thread
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
                transaction: transaction
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
                    transaction: tx
                )
            }
        }()

        cell.configure(
            with: item,
            spoilerState: spoilerState,
            contextMenuActions: contextMenuActions,
            indexPath: indexPath
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
        textView.font = UIFont.dynamicTypeBodyClamped.semibold()
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
    public func forwardMessageFlowDidComplete(items: [ForwardMessageItem], recipientThreads: [TSThread]) {
        AssertIsOnMainThread()

        dismiss(animated: true) {
            ForwardMessageViewController.finalizeForward(items: items,
                                                         recipientThreads: recipientThreads,
                                                         fromViewController: self)
        }
    }

    public func forwardMessageFlowDidCancel() {
        dismiss(animated: true)
    }
}

extension MyStoriesViewController: StoryPageViewControllerDataSource {
    func storyPageViewControllerAvailableContexts(
        _ storyPageViewController: StoryPageViewController,
        hiddenStoryFilter: Bool?
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
                thread: $0
            )
        }
    }
}

final class SentStoryCell: UITableViewCell {
    static let reuseIdentifier = "SentStoryCell"

    private class ContextButtonContainer: UIView {
        func setContextButton(_ contextButton: ContextMenuButton) {
            removeAllSubviews()

            addSubview(contextButton)
            contextButton.autoPinEdgesToSuperviewEdges()
            contextButton.layer.cornerRadius = 16
            contextButton.clipsToBounds = true
        }
    }

    let attachmentThumbnail = UIView()

    fileprivate let contentHStackView = UIStackView()

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let saveButton = OWSButton()
    private let contextButtonContainer = ContextButtonContainer()

    private let failedIconContainer = UIView()
    private let failedIconView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear

        contentHStackView.axis = .horizontal
        contentHStackView.alignment = .center
        contentView.addSubview(contentHStackView)
        contentHStackView.autoPinEdgesToSuperviewMargins()

        attachmentThumbnail.autoSetDimensions(to: CGSize(width: 56, height: 84))
        contentHStackView.addArrangedSubview(attachmentThumbnail)

        contentHStackView.addArrangedSubview(.spacer(withWidth: 16))

        contentHStackView.addArrangedSubview(failedIconContainer)
        failedIconContainer.autoSetDimension(.width, toSize: 28)
        failedIconContainer.addSubview(failedIconView)
        failedIconView.autoPinHeightToSuperview()
        failedIconView.autoPinEdge(toSuperviewEdge: .leading)
        failedIconView.autoSetDimension(.width, toSize: 16)
        failedIconView.contentMode = .scaleAspectFit
        failedIconView.tintColor = .ows_accentRed

        let vStackView = UIStackView()
        vStackView.axis = .vertical
        vStackView.alignment = .leading
        contentHStackView.addArrangedSubview(vStackView)

        titleLabel.font = .dynamicTypeHeadline

        vStackView.addArrangedSubview(titleLabel)

        subtitleLabel.font = .dynamicTypeSubheadline
        vStackView.addArrangedSubview(subtitleLabel)

        contentHStackView.addArrangedSubview(.hStretchingSpacer())

        saveButton.autoSetDimensions(to: CGSize(square: 32))
        saveButton.layer.cornerRadius = 16
        saveButton.clipsToBounds = true
        contentHStackView.addArrangedSubview(saveButton)

        contentHStackView.addArrangedSubview(.spacer(withWidth: 20))

        contextButtonContainer.autoSetDimensions(to: CGSize(square: 32))
        contentHStackView.addArrangedSubview(contextButtonContainer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var attachment: StoryThumbnailView.Attachment?

    fileprivate func configure(
        with item: OutgoingStoryItem,
        spoilerState: SpoilerRenderState,
        contextMenuActions: [UIAction],
        indexPath: IndexPath
    ) {
        if self.attachment != item.attachment {
            self.attachment = item.attachment
            let thumbnailView = StoryThumbnailView(
                attachment: item.attachment,
                interactionIdentifier: .fromStoryMessage(item.message),
                spoilerState: spoilerState
            )
            attachmentThumbnail.removeAllSubviews()
            attachmentThumbnail.addSubview(thumbnailView)
            thumbnailView.autoPinEdgesToSuperviewEdges()
        }

        titleLabel.textColor = Theme.primaryTextColor
        subtitleLabel.textColor = Theme.isDarkThemeEnabled ? Theme.secondaryTextAndIconColor : .ows_gray45

        switch item.message.sendingState {
        case .pending, .sending:
            titleLabel.text = OWSLocalizedString("STORY_SENDING", comment: "Text indicating that the story is currently sending")
            subtitleLabel.text = ""
            failedIconContainer.isHiddenInStackView = true
        case .failed:
            failedIconView.image = Theme.iconImage(.error16)
            failedIconContainer.isHiddenInStackView = false
            titleLabel.text = item.message.hasSentToAnyRecipients
                ? OWSLocalizedString("STORY_SEND_PARTIALLY_FAILED", comment: "Text indicating that the story send has partially failed")
                : OWSLocalizedString("STORY_SEND_FAILED", comment: "Text indicating that the story send has failed")
            subtitleLabel.text = OWSLocalizedString("STORY_SEND_FAILED_RETRY", comment: "Text indicating that you can tap to retry sending")
        case .sent:
            if StoryManager.areViewReceiptsEnabled {
                let format = OWSLocalizedString(
                    "STORY_VIEWS_%d", tableName: "PluralAware",
                    comment: "Text explaining how many views a story has. Embeds {{ %d number of views }}"
                )
                titleLabel.text = String.localizedStringWithFormat(format, item.message.remoteViewCount(in: item.thread.storyContext))
            } else {
                titleLabel.text = OWSLocalizedString(
                    "STORY_VIEWS_OFF",
                    comment: "Text indicating that the user has views turned off"
                )
            }
            subtitleLabel.text = DateUtil.formatTimestampRelatively(item.message.timestamp)
            failedIconContainer.isHiddenInStackView = true
        case .sent_OBSOLETE, .delivered_OBSOLETE:
            owsFailDebug("Unexpected legacy sending state")
        }

        saveButton.tintColor = Theme.primaryIconColor
        saveButton.setImage(UIImage(imageLiteralResourceName: "save-20"), for: .normal)
        saveButton.setBackgroundImage(UIImage.image(color: Theme.secondaryBackgroundColor), for: .normal)

        if item.attachment.isSaveable {
            saveButton.isHiddenInStackView = false
            saveButton.block = { item.attachment.save(
                interactionIdentifier: .fromStoryMessage(item.message),
                spoilerState: spoilerState
            ) }
        } else {
            saveButton.isHiddenInStackView = true
            saveButton.block = {}
        }

        let contextButton = ContextMenuButton(actions: contextMenuActions)
        contextButton.tintColor = Theme.primaryIconColor
        contextButton.setImage(UIImage(imageLiteralResourceName: "more-compact"), for: .normal)
        contextButton.setBackgroundImage(UIImage.image(color: Theme.secondaryBackgroundColor), for: .normal)
        contextButtonContainer.setContextButton(contextButton)

        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = Theme.tableCell2SelectedBackgroundColor
        self.selectedBackgroundView = selectedBackgroundView
    }
}
