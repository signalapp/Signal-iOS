//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import UIKit

private struct Viewer {
    let address: SignalServiceAddress
    let displayName: String
    let comparableName: String
    let viewedTimestamp: UInt64
}

class StoryViewsViewController: OWSViewController {
    private(set) var storyMessage: StoryMessage
    let context: StoryContext

    let tableView = UITableView(frame: .zero, style: .grouped)

    private let emptyStateView = UIView()

    init(storyMessage: StoryMessage, context: StoryContext) {
        self.storyMessage = storyMessage
        self.context = context
        super.init()
        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.tableHeaderView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 0, height: CGFloat.leastNormalMagnitude)))
        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        tableView.register(StoryViewCell.self, forCellReuseIdentifier: StoryViewCell.reuseIdentifier)

        view.addSubview(emptyStateView)
        emptyStateView.autoPinEdgesToSuperviewEdges()

        updateViewers()
    }

    private var viewers = [Viewer]()
    private func updateViewers(reloadStoryMessage: Bool = false) {
        defer {
            tableView.reloadData()
            updateEmptyStateView()
        }

        guard StoryManager.areViewReceiptsEnabled else {
            self.viewers = []
            return
        }

        databaseStorage.read { transaction in
            if reloadStoryMessage {
                guard let latestStoryMessage = StoryMessage.anyFetch(uniqueId: storyMessage.uniqueId, transaction: transaction) else {
                    owsFailDebug("Missing story message")
                    self.viewers = []
                    return
                }

                self.storyMessage = latestStoryMessage
            }

            guard case .outgoing(let recipientStates) = storyMessage.manifest else {
                owsFailDebug("Invalid story message for views")
                self.viewers = []
                return
            }

            self.viewers = recipientStates
                .lazy
                .filter { $1.isValidForContext(self.context) }
                .compactMap {
                    guard let viewedTimestamp = $0.value.viewedTimestamp else { return nil }
                    return Viewer(
                        address: .init(uuid: $0.key),
                        displayName: Self.contactsManager.displayName(for: .init(uuid: $0.key), transaction: transaction),
                        comparableName: Self.contactsManager.comparableName(for: .init(uuid: $0.key), transaction: transaction),
                        viewedTimestamp: viewedTimestamp
                    )
                }.sorted { lhs, rhs in
                    if lhs.viewedTimestamp == rhs.viewedTimestamp {
                        return lhs.comparableName.caseInsensitiveCompare(rhs.comparableName) == .orderedAscending
                    }
                    return lhs.viewedTimestamp > rhs.viewedTimestamp
                }
        }
    }

    private func updateEmptyStateView() {
        emptyStateView.removeAllSubviews()
        emptyStateView.isHidden = viewers.count > 0

        let label = UILabel()
        label.textAlignment = .center

        if StoryManager.areViewReceiptsEnabled {
            label.font = .ows_dynamicTypeBody
            label.textColor = .ows_gray45
            label.text = NSLocalizedString(
                "STORIES_NO_VIEWS_YET",
                comment: "Indicates that this story has no views yet"
            )

            emptyStateView.isUserInteractionEnabled = false
            emptyStateView.addSubview(label)
            label.autoPinEdgesToSuperviewEdges()
        } else {
            label.font = .ows_dynamicTypeCallout
            label.textColor = .ows_gray25
            label.text = NSLocalizedString(
                "STORIES_VIEWS_OFF_DESCRIPTION",
                comment: "Text explaining that you will not see any views for your story because you have view receipts turned off"
            )
            label.numberOfLines = 0
            label.setContentHuggingVerticalHigh()

            let settingsButton = OWSButton { [weak self] in
                let privacySettings = OWSNavigationController(rootViewController: StoryPrivacySettingsViewController())

                // Dismiss the story view and present the privacy settings screen
                owsAssertDebug(self?.presentingViewController?.presentingViewController is ConversationSplitViewController)
                self?.presentingViewController?.presentingViewController?.dismiss(animated: true, completion: {
                    CurrentAppContext().frontmostViewController()?.present(privacySettings, animated: true)
                })
            }
            settingsButton.setTitle(CommonStrings.goToSettingsButton, for: .normal)
            settingsButton.titleLabel?.font = UIFont.ows_dynamicTypeCaption1.ows_semibold
            settingsButton.setTitleColor(.ows_gray25, for: .normal)
            settingsButton.contentEdgeInsets = UIEdgeInsets(hMargin: 14, vMargin: 6)
            settingsButton.layer.borderWidth = 1.5
            settingsButton.layer.borderColor = UIColor.ows_gray25.cgColor

            let settingsButtonPillWrapper = ManualLayoutView(name: "SettingsButton")
            settingsButtonPillWrapper.shouldDeactivateConstraints = false
            settingsButtonPillWrapper.addSubview(settingsButton) { view in
                settingsButton.layer.cornerRadius = settingsButton.height / 2
            }
            settingsButton.autoPinEdgesToSuperviewEdges()

            let topSpacer = UIView.vStretchingSpacer()
            let bottomSpacer = UIView.vStretchingSpacer()

            let stackView = UIStackView(arrangedSubviews: [
                topSpacer,
                label,
                settingsButtonPillWrapper,
                bottomSpacer
            ])
            stackView.isLayoutMarginsRelativeArrangement = true
            stackView.layoutMargins = UIEdgeInsets(hMargin: 65, vMargin: 0)
            stackView.axis = .vertical
            stackView.spacing = 20
            stackView.alignment = .center
            emptyStateView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges()

            topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

            emptyStateView.isUserInteractionEnabled = true
        }
    }
}

extension StoryViewsViewController: UITableViewDelegate {}

extension StoryViewsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: StoryViewCell.reuseIdentifier, for: indexPath) as! StoryViewCell
        guard let viewer = viewers[safe: indexPath.row] else {
            owsFailDebug("Unexpectedly missing viewer")
            return UITableViewCell()
        }
        cell.configure(with: viewer)
        return cell
    }
}

extension StoryViewsViewController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if databaseChanges.storyMessageRowIds.contains(storyMessage.id!) {
            updateViewers(reloadStoryMessage: true)
        }
    }

    func databaseChangesDidUpdateExternally() {
        updateViewers(reloadStoryMessage: true)
    }

    func databaseChangesDidReset() {
        updateViewers(reloadStoryMessage: true)
    }
}

private class StoryViewCell: UITableViewCell {
    static let reuseIdentifier = "StoryViewCell"

    let avatarView = ConversationAvatarView(sizeClass: .thirtySix, localUserDisplayMode: .asUser, badged: true)

    lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = .ows_dynamicTypeBodyClamped
        label.textColor = Theme.darkThemePrimaryColor
        return label
    }()

    lazy var timestampLabel: UILabel = {
        let label = UILabel()
        label.font = .ows_dynamicTypeFootnoteClamped
        label.textColor = Theme.darkThemeSecondaryTextAndIconColor
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        backgroundColor = .clear

        let hStack = UIStackView(arrangedSubviews: [avatarView, nameLabel, .hStretchingSpacer(), timestampLabel])
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 12
        contentView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with viewer: Viewer) {
        avatarView.updateWithSneakyTransactionIfNecessary { $0.dataSource = .address(viewer.address) }
        nameLabel.text = viewer.displayName
        timestampLabel.text = DateUtil.formatPastTimestampRelativeToNow(viewer.viewedTimestamp)
    }
}
