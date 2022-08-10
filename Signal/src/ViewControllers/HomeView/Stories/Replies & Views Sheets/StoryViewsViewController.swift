//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

    let tableView = UITableView(frame: .zero, style: .grouped)

    private lazy var emptyStateView: UIView = {
        let label = UILabel()
        label.font = .ows_dynamicTypeBody
        label.textColor = .ows_gray45
        label.textAlignment = .center
        label.text = NSLocalizedString("STORIES_NO_VIEWS_YET", comment: "Indicates that this story has no views yet")
        label.isHidden = true
        label.isUserInteractionEnabled = false
        return label
    }()

    init(storyMessage: StoryMessage) {
        self.storyMessage = storyMessage
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
    private func updateViewers() {
        defer { tableView.reloadData() }

        guard case .outgoing(let recipientStates) = storyMessage.manifest else {
            owsFailDebug("Invalid story message for views")
            self.viewers = []
            return
        }

        self.viewers = databaseStorage.read { transaction in
            recipientStates.compactMap {
               guard let viewedTimestamp = $0.value.viewedTimestamp else { return nil }
                return Viewer(
                    address: .init(uuid: $0.key),
                    displayName: contactsManager.displayName(for: .init(uuid: $0.key), transaction: transaction),
                    comparableName: contactsManager.comparableName(for: .init(uuid: $0.key), transaction: transaction),
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

    func reloadStoryMessage() {
        guard let latestStoryMessage = databaseStorage.read(block: {
            StoryMessage.anyFetch(uniqueId: storyMessage.uniqueId, transaction: $0)
        }) else {
            owsFailDebug("Missing story message")
            return
        }

        self.storyMessage = latestStoryMessage
        updateViewers()
    }
}

extension StoryViewsViewController: UITableViewDelegate {

}

extension StoryViewsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        emptyStateView.isHidden = viewers.count > 0
        return viewers.count
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
            reloadStoryMessage()
        }
    }

    func databaseChangesDidUpdateExternally() {
        reloadStoryMessage()
    }

    func databaseChangesDidReset() {
        reloadStoryMessage()
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
