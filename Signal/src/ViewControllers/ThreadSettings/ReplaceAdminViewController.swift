//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

protocol ReplaceAdminViewControllerDelegate: class {
    func replaceAdmin(uuid: UUID)
}

// MARK: -

class ReplaceAdminViewController: OWSTableViewController {

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

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("REPLACE_ADMIN_VIEW_TITLE",
                                  comment: "The title for the 'replace group admin' view.")

        self.useThemeBackgroundColors = true
        tableView.separatorColor = .clear

        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()

        let sortedCandidates = databaseStorage.uiRead { transaction in
            self.contactsManager.sortSignalServiceAddresses(Array(self.candidates), transaction: transaction)
        }
        for address in sortedCandidates {
            section.add(OWSTableItem(customCellBlock: {
                let cell = ContactTableViewCell()

                let imageView = UIImageView()
                imageView.setTemplateImageName("empty-circle-outline-24", tintColor: .ows_gray25)
                cell.ows_setAccessoryView(imageView)

                cell.configureWithSneakyTransaction(recipientAddress: address)

                return cell
                },
                                     actionBlock: { [weak self] in
                                        self?.candidateWasSelected(candidate: address)
                }
            ))
        }

        contents.addSection(section)

        self.contents = contents
    }

    private func candidateWasSelected(candidate: SignalServiceAddress) {
        guard let replacementAdminUuid = candidate.uuid else {
            owsFailDebug("Invalid replacement Admin.")
            return
        }

        replaceAdminViewControllerDelegate?.replaceAdmin(uuid: replacementAdminUuid)
    }
}
