//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

protocol ReplaceAdminViewControllerDelegate: AnyObject {
    func replaceAdmin(newAdminAci: Aci)
}

// MARK: -

class ReplaceAdminViewController: OWSTableViewController2 {

    weak var replaceAdminViewControllerDelegate: ReplaceAdminViewControllerDelegate?

    private let candidates: Set<SignalServiceAddress>

    required init(candidates: Set<SignalServiceAddress>,
                  replaceAdminViewControllerDelegate: ReplaceAdminViewControllerDelegate) {
        assert(!candidates.isEmpty)

        self.candidates = candidates
        self.replaceAdminViewControllerDelegate = replaceAdminViewControllerDelegate

        super.init()
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("REPLACE_ADMIN_VIEW_TITLE",
                                  comment: "The title for the 'replace group admin' view.")

        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()

        let sortedCandidates = databaseStorage.read { tx in
            self.contactsManagerImpl.sortSignalServiceAddresses(self.candidates, transaction: tx)
        }
        for address in sortedCandidates {
            section.add(OWSTableItem(
                dequeueCellBlock: { tableView in
                    guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                        owsFailDebug("Missing cell.")
                        return UITableViewCell()
                    }

                    Self.databaseStorage.read { transaction in
                        let configuration = ContactCellConfiguration(address: address, localUserDisplayMode: .asUser)
                        let imageView = CVImageView()
                        imageView.setTemplateImageName(Theme.iconName(.circle), tintColor: .ows_gray25)
                        configuration.accessoryView = ContactCellAccessoryView(accessoryView: imageView, size: .square(24))

                        cell.configure(configuration: configuration, transaction: transaction)
                    }

                    return cell
                },
                actionBlock: { [weak self] in
                    self?.candidateWasSelected(candidate: address)
                }
            ))
        }

        contents.add(section)

        self.contents = contents
    }

    private func candidateWasSelected(candidate: SignalServiceAddress) {
        guard let replacementAdminAci = candidate.serviceId as? Aci else {
            owsFailDebug("Invalid replacement Admin.")
            return
        }

        replaceAdminViewControllerDelegate?.replaceAdmin(newAdminAci: replacementAdminAci)
    }
}
