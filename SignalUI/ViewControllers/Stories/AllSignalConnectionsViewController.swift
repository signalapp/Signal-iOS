//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public class AllSignalConnectionsViewController: OWSTableViewController2 {
    let collation = UILocalizedIndexedCollation.current()

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("ALL_SIGNAL_CONNECTIONS_TITLE", comment: "Title for the view of all your signal connections")
        navigationItem.leftBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(done))

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing

        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)
        updateTableContents()
    }

    @objc
    private func done() {
        dismiss(animated: true)
    }

    private func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let allConnections = databaseStorage.read { transaction in
            profileManager.allWhitelistedRegisteredAddresses(with: transaction)
                .lazy
                .filter { !$0.isLocalAddress }
                .map { ConnectionModel(address: $0, transaction: transaction) }
                .sorted { lhs, rhs in
                    lhs.comparableName.localizedCaseInsensitiveCompare(rhs.comparableName) == .orderedAscending
                }
        }

        let collatedConnections = Dictionary(grouping: allConnections) {
            collation.section(for: $0, collationStringSelector: #selector(ConnectionModel.stringForCollation))
        }

        for (idx, title) in collation.sectionTitles.enumerated() {
            if let connections = collatedConnections[idx] {
                contents.addSection(OWSTableSection(title: title, items: items(for: connections)))
            } else {
                // Add an empty section to maintain collation
                contents.addSection(OWSTableSection())
            }
        }

        contents.sectionForSectionIndexTitleBlock = { [weak self] _, index in
            return self?.collation.section(forSectionIndexTitle: index) ?? 0
        }
        contents.sectionIndexTitlesForTableViewBlock = { [weak self] in
            self?.collation.sectionTitles ?? []
        }
    }

    private func items(for connections: [ConnectionModel]) -> [OWSTableItem] {
        var items = [OWSTableItem]()
        for connection in connections {
            items.append(.init(dequeueCellBlock: { tableView in
                guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                    return UITableViewCell()
                }

                cell.selectionStyle = .none
                cell.configureWithSneakyTransaction(address: connection.address, localUserDisplayMode: .asLocalUser)

                return cell
            }))
        }
        return items
    }
}

private class ConnectionModel: Dependencies {
    let address: SignalServiceAddress
    let comparableName: String

    init(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) {
        self.address = address
        self.comparableName = Self.contactsManager.comparableName(for: address, transaction: transaction)
    }

    @objc
    func stringForCollation() -> String { comparableName }
}
